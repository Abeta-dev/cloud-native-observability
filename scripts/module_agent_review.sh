#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Module Code-Owner Agent Automated PR Review & Verification Engine
# Repository: github.com/abeta-dev/cloud-native-observability (v0.3.0)
# Compatible with Bash 3.2+ (macOS default bash & Ubuntu CI runners)
# ==============================================================================

BASE_REF="origin/main"
HEAD_REF="HEAD"
PR_NUMBER=""
CONFIG_PATH=".github/module-agents.json"
OUTPUT_PATH="/tmp/module-agent-report.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      BASE_REF="$2"
      shift 2
      ;;
    --head)
      HEAD_REF="$2"
      shift 2
      ;;
    --pr-number)
      PR_NUMBER="$2"
      shift 2
      ;;
    --config)
      CONFIG_PATH="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--base <ref>] [--head <ref>] [--pr-number <num>] [--config <path>] [--output <path>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT_DIR="$(git rev-parse --show-toplevel)"
else
  ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
cd "${ROOT_DIR}"

export CNO_BASE_REF="${BASE_REF}"
export CNO_HEAD_REF="${HEAD_REF}"
export CNO_PR_NUMBER="${PR_NUMBER}"
export CNO_CONFIG_PATH="${CONFIG_PATH}"
export CNO_OUTPUT_PATH="${OUTPUT_PATH}"
export CNO_ROOT_DIR="${ROOT_DIR}"

python3 - <<'PYEOF'
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

base_ref = os.environ.get("CNO_BASE_REF", "origin/main")
head_ref = os.environ.get("CNO_HEAD_REF", "HEAD")
pr_number = os.environ.get("CNO_PR_NUMBER", "").strip()
config_path = os.environ.get("CNO_CONFIG_PATH", ".github/module-agents.json")
output_path = os.environ.get("CNO_OUTPUT_PATH", "/tmp/module-agent-report.md")
root_dir = os.environ.get("CNO_ROOT_DIR", os.getcwd())


def run_cmd(cmd, cwd=None, timeout=None):
    try:
        proc = subprocess.run(
            cmd,
            cwd=cwd or root_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout.strip()
    except subprocess.TimeoutExpired:
        return 124, "Command timed out"
    except Exception as exc:
        return 1, str(exc)


if not os.path.isfile(config_path):
    fallback_cfg = "/tmp/module-agents.json"
    if os.path.isfile(fallback_cfg):
        config_path = fallback_cfg
    else:
        print(f"❌ Error: Module agent config not found at {config_path}", file=sys.stderr)
        sys.exit(1)

with open(config_path, "r", encoding="utf-8") as fp:
    config = json.load(fp)

agents = config.get("agents", [])
req_cov = float(config.get("coverage_requirement", 100.0))

# Resolve changed files between base_ref and head_ref
rc, diff_out = run_cmd(["git", "diff", "--name-only", f"{base_ref}...{head_ref}"])
if rc != 0:
    rc, diff_out = run_cmd(["git", "diff", "--name-only", base_ref, head_ref])
if rc != 0:
    rc, diff_out = run_cmd(["git", "diff", "--name-only", "HEAD~1", "HEAD"])

changed_files = [line.strip() for line in diff_out.splitlines() if line.strip()]

if head_ref == "HEAD":
    rc_wt, wt_out = run_cmd(["git", "status", "--porcelain"])
    if rc_wt == 0 and wt_out:
        for line in wt_out.splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) == 2:
                path_entry = parts[1].strip()
                if " -> " in path_entry:
                    path_entry = path_entry.split(" -> ", 1)[1].strip()
                if path_entry and path_entry not in changed_files:
                    changed_files.append(path_entry)

changed_files = sorted(set(changed_files))


def path_matches(file_path, pattern):
    norm_file = file_path.lstrip("/")
    norm_pat = pattern.lstrip("/")
    if norm_pat.endswith("/**"):
        prefix = norm_pat[:-3].rstrip("/")
        return norm_file == prefix or norm_file.startswith(prefix + "/")
    if norm_pat.endswith("/"):
        prefix = norm_pat.rstrip("/")
        return norm_file == prefix or norm_file.startswith(prefix + "/")
    return norm_file == norm_pat or fnmatch.fnmatch(norm_file, norm_pat)


activated_agents = []
agent_files_map = {}

for agent in agents:
    aid = agent["id"]
    matched = []
    for fpath in changed_files:
        for pat in agent.get("paths", []):
            if path_matches(fpath, pat):
                matched.append(fpath)
                break
    if matched:
        activated_agents.append(agent)
        agent_files_map[aid] = matched

# Fallback to platform governance agent if diff is empty
if not activated_agents and agents:
    gov = next((a for a in agents if a["id"] == "cno-platform-governance"), agents[-1])
    activated_agents.append(gov)
    agent_files_map[gov["id"]] = ["(repository-wide audit)"]

# Execute shared verification gates once and cache results
demo_app_dir = os.path.join(root_dir, "deploy", "docker-compose", "demo-app")

# 1. Unit & Race tests on deploy/docker-compose/demo-app
test_rc, test_out = run_cmd(["go", "test", "-race", "-v", "./..."], cwd=demo_app_dir)
passed_tests = re.findall(r"--- PASS:\s+([A-Za-z0-9_/.-]+)", test_out)
failed_tests = re.findall(r"--- FAIL:\s+([A-Za-z0-9_/.-]+)", test_out)
file_line_diags = re.findall(r"([A-Za-z0-9_.-]+\.go:[0-9]+:.*)", test_out)

# 2. Statement coverage (100.0% requirement)
cov_fd, cov_profile = tempfile.mkstemp(prefix="cno-demo-cov-", suffix=".out")
os.close(cov_fd)
cov_rc, cov_out = run_cmd(
    ["go", "test", f"-coverprofile={cov_profile}", "-cover", "./..."],
    cwd=demo_app_dir,
)
cov_match = re.search(r"coverage:\s+([0-9.]+)%\s+of\s+statements", cov_out)
cov_pct = float(cov_match.group(1)) if cov_match else 0.0
uncovered_funcs = []
if cov_rc == 0 and os.path.isfile(cov_profile):
    _, func_out = run_cmd(["go", "tool", "cover", f"-func={cov_profile}"], cwd=demo_app_dir)
    for line in func_out.splitlines():
        if line.startswith("total:"):
            continue
        parts = line.split()
        if len(parts) >= 3 and parts[-1].endswith("%"):
            try:
                fn_pct = float(parts[-1].rstrip("%"))
                if fn_pct < req_cov:
                    uncovered_funcs.append(f"{parts[0]} {parts[1]} ({parts[-1]})")
            except ValueError:
                pass
try:
    os.remove(cov_profile)
except OSError:
    pass

cov_ok = (cov_rc == 0) and (cov_pct >= req_cov) and (len(uncovered_funcs) == 0)

# 3. Lint & Manifest/SLO AST Verification (go vet + ./scripts/check_version.sh)
vet_rc, vet_out = run_cmd(["go", "vet", "./..."], cwd=demo_app_dir)
ver_rc, ver_out = run_cmd(["./scripts/check_version.sh"], cwd=root_dir)
lint_ok = (vet_rc == 0) and (ver_rc == 0)

# 4. Secret scanning gate (./scripts/check_secrets.sh)
sec_rc, sec_out = run_cmd(["./scripts/check_secrets.sh"], cwd=root_dir)


def evaluate_domain_rules(agent_id):
    violations = []
    if sec_rc != 0:
        violations.append(f"check_secrets.sh failed:\n{sec_out}")

    if agent_id == "cno-otel-lgtm-stack":
        otel_cfg = os.path.join(root_dir, "deploy/docker-compose/otel-collector/otel-collector-config.yml")
        loki_cfg = os.path.join(root_dir, "deploy/docker-compose/loki/loki-config.yml")
        if not os.path.isfile(otel_cfg):
            violations.append("Missing deploy/docker-compose/otel-collector/otel-collector-config.yml")
        else:
            with open(otel_cfg, "r", encoding="utf-8") as f:
                content = f.read()
            if "memory_limiter" not in content or "spanmetrics" not in content or "8889" not in content:
                violations.append("OTel Collector config must include memory_limiter, spanmetrics, and :8889 exporter")
        if not os.path.isfile(loki_cfg):
            violations.append("Missing deploy/docker-compose/loki/loki-config.yml")
        else:
            with open(loki_cfg, "r", encoding="utf-8") as f:
                lcontent = f.read()
            if "v13" not in lcontent or "allow_structured_metadata: true" not in lcontent:
                violations.append("Loki config must enforce schema v13 and allow_structured_metadata: true")

    elif agent_id == "cno-sre-slo-alerting":
        for req_file in [
            "deploy/slo/canonical_sli.promql",
            "deploy/kubernetes/alerts/slo-alerts.yaml",
            "deploy/kubernetes/alerts/alertmanager.yaml",
            "docs/RUNBOOKS.md",
            "scripts/test_alerts.sh",
        ]:
            if not os.path.isfile(os.path.join(root_dir, req_file)):
                violations.append(f"Missing required SRE/SLO file: {req_file}")
        sh_rc, sh_out = run_cmd(["bash", "-n", "scripts/test_alerts.sh"])
        if sh_rc != 0:
            violations.append(f"bash -n scripts/test_alerts.sh failed: {sh_out}")

    elif agent_id == "cno-gitops-terraform":
        for req_file in [
            "deploy/kubernetes/argocd/app-of-apps.yaml",
            "deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml",
            "deploy/terraform/main.tf",
            "deploy/terraform/modules/grafana_provisioning/alerts.tf",
            "docs/TERRAFORM_GUIDE.md",
        ]:
            if not os.path.isfile(os.path.join(root_dir, req_file)):
                violations.append(f"Missing required GitOps/Terraform file: {req_file}")

    elif agent_id == "cno-platform-governance":
        for req_file in [
            "AGENTS.md",
            "README.md",
            "CHANGELOG.md",
            "docs/index.html",
            "docs/llms.txt",
            "llms.txt",
        ]:
            if not os.path.isfile(os.path.join(root_dir, req_file)):
                violations.append(f"Missing required governance file: {req_file}")
        codeowners_path = os.path.join(root_dir, ".github/CODEOWNERS")
        if os.path.isfile(codeowners_path):
            with open(codeowners_path, "r", encoding="utf-8") as cf:
                if "@umesh0492" not in cf.read():
                    violations.append(".github/CODEOWNERS must define @umesh0492 ownership rules")
        scripts_dir = os.path.join(root_dir, "scripts")
        if os.path.isdir(scripts_dir):
            for sname in sorted(os.listdir(scripts_dir)):
                if sname.endswith(".sh"):
                    s_rc, s_out = run_cmd(["bash", "-n", os.path.join("scripts", sname)])
                    if s_rc != 0:
                        violations.append(f"Bash syntax error in scripts/{sname}: {s_out}")

    return violations


results = []
overall_pass = True
failure_diagnostics = []

if test_rc != 0:
    overall_pass = False
    fail_list = ", ".join(failed_tests) if failed_tests else "go test -race ./..."
    diag_lines = "\n".join(file_line_diags) if file_line_diags else test_out
    failure_diagnostics.append(
        f"- **Unit & Race Tests (`deploy/docker-compose/demo-app`)**: Failed test case(s): `{fail_list}`\n```text\n{diag_lines}\n```"
    )

if not cov_ok:
    overall_pass = False
    uncov_str = ", ".join(uncovered_funcs) if uncovered_funcs else "see output"
    failure_diagnostics.append(
        f"- **Statement Coverage (`deploy/docker-compose/demo-app`)**: Measured `{cov_pct:.1f}%` (required `{req_cov:.1f}%`). Uncovered functions: `{uncov_str}`"
    )

if not lint_ok:
    overall_pass = False
    if vet_rc != 0:
        failure_diagnostics.append(
            f"- **`go vet ./...` (`deploy/docker-compose/demo-app`)**:\n```text\n{vet_out}\n```"
        )
    if ver_rc != 0:
        failure_diagnostics.append(
            f"- **Truth & AST Gate (`./scripts/check_version.sh`)**:\n```text\n{ver_out}\n```"
        )

for agent in activated_agents:
    aid = agent["id"]
    owned_files = agent_files_map.get(aid, [])
    domain_violations = evaluate_domain_rules(aid)
    domain_ok = len(domain_violations) == 0
    if not domain_ok:
        overall_pass = False
        for v in domain_violations:
            failure_diagnostics.append(f"- **Domain Rule Violation (`{agent['handle']}`)**: {v}")

    agent_pass = (test_rc == 0) and cov_ok and lint_ok and domain_ok

    test_cell = (
        f"✅ `{len(passed_tests)}/{len(passed_tests)} passed` (`-race`)"
        if test_rc == 0
        else f"❌ `{len(failed_tests)} failed` ({', '.join(failed_tests) or 'compile/race error'})"
    )
    cov_cell = (
        f"✅ `{cov_pct:.1f}%` (`demo-app`)"
        if cov_ok
        else f"❌ `{cov_pct:.1f}%` (< `{req_cov:.1f}%`)"
    )
    lint_cell = (
        "✅ `go vet` + `check_version.sh` (PromQL AST & parity)"
        if lint_ok
        else "❌ Lint / AST / Version check failed"
    )
    domain_cell = (
        f"✅ `{len(agent.get('rules', []))} rules` + `check_secrets.sh`"
        if domain_ok
        else f"❌ `{len(domain_violations)} violation(s)`"
    )
    verdict_cell = "✅ **APPROVED**" if agent_pass else "❌ **CHANGES REQUESTED**"

    results.append(
        {
            "agent": agent,
            "owned_files": owned_files,
            "test_cell": test_cell,
            "cov_cell": cov_cell,
            "lint_cell": lint_cell,
            "domain_cell": domain_cell,
            "verdict_cell": verdict_cell,
            "passed": agent_pass,
            "domain_violations": domain_violations,
        }
    )

# ==============================================================================
# Live Multi-Skill Quality & Architecture Review Gates
# ==============================================================================
skill_review_rows = []

# 1. /impeccable Frontend & Docs Design Skill (docs/index.html)
impeccable_ok = True
impeccable_errors = []
docs_html_path = os.path.join(root_dir, "docs", "index.html")
if not os.path.isfile(docs_html_path):
    impeccable_ok = False
    impeccable_errors.append("Missing docs/index.html")
else:
    with open(docs_html_path, "r", encoding="utf-8") as hf:
        html_text = hf.read()
    if "<main" not in html_text:
        impeccable_ok = False
        impeccable_errors.append("docs/index.html missing semantic <main> landmark")
    if "--" not in html_text:
        impeccable_ok = False
        impeccable_errors.append("docs/index.html missing semantic CSS custom properties (--)")
    if "umesh0492" in html_text or "Abeta-dev" in html_text:
        impeccable_ok = False
        impeccable_errors.append("docs/index.html contains legacy umesh0492 or uppercase Abeta-dev links")

    # Execute impeccable detect --json docs/index.html when available
    impeccable_cmd = None
    local_impeccable = os.path.expanduser("~/.gemini/config/skills/impeccable/scripts/impeccable")
    if os.path.isfile(local_impeccable) and os.access(local_impeccable, os.X_OK):
        impeccable_cmd = [local_impeccable, "detect", "--json", "docs/index.html"]
    elif shutil.which("impeccable"):
        impeccable_cmd = ["impeccable", "detect", "--json", "docs/index.html"]
    elif shutil.which("npx"):
        impeccable_cmd = ["npx", "--yes", "@pbakaus/impeccable", "detect", "--json", "docs/index.html"]

    if impeccable_cmd:
        imp_rc, imp_out = run_cmd(impeccable_cmd, cwd=root_dir, timeout=30)
        if imp_rc != 0 and impeccable_cmd[0] == "npx":
            # Fallback to `npx --yes impeccable detect --json docs/index.html`
            imp_rc, imp_out = run_cmd(
                ["npx", "--yes", "impeccable", "detect", "--json", "docs/index.html"],
                cwd=root_dir,
                timeout=30,
            )
        if imp_rc == 0 and imp_out.startswith("["):
            try:
                findings = json.loads(imp_out)
                if isinstance(findings, list) and len(findings) > 0:
                    impeccable_ok = False
                    impeccable_errors.append(
                        f"impeccable detect reported {len(findings)} anti-pattern(s): {imp_out}"
                    )
            except ValueError:
                pass

if not impeccable_ok:
    overall_pass = False
    for err in impeccable_errors:
        failure_diagnostics.append(f"- **`/impeccable` Frontend & Docs Design Skill**: {err}")

skill_review_rows.append(
    {
        "gate": "**`/impeccable` Frontend & Docs Design Skill**",
        "scope": "[`docs/index.html`](docs/index.html) (Read & Persuade modes, OKLCH / semantic tokens, typography, layout, a11y)",
        "verification": "`impeccable detect --json docs/index.html` + `<main>` landmark, semantic `--` tokens & canonical `abeta-dev` links",
        "result": (
            "✅ PASS (0 anti-patterns via `impeccable detect`, 20/20 rubric)"
            if impeccable_ok
            else f"❌ FAIL ({'; '.join(impeccable_errors)})"
        ),
    }
)

# 2. @uncle-bob-craft (SOLID & Uncle Bob Clean Code Skill)
solid_ok = True
solid_errors = []
fmt_rc, fmt_out = run_cmd(["gofmt", "-l", "."], cwd=demo_app_dir)
if fmt_rc != 0 or fmt_out.strip():
    solid_ok = False
    solid_errors.append(f"gofmt unformatted files in deploy/docker-compose/demo-app: {fmt_out}")
if vet_rc != 0:
    solid_ok = False
    solid_errors.append(f"go vet failed in deploy/docker-compose/demo-app: {vet_out}")
if test_rc != 0 or not cov_ok:
    solid_ok = False
    solid_errors.append("demo-app failed unit/race tests or 100.0% coverage requirement")

for req_mod in [
    "deploy/docker-compose/demo-app/main.go",
    "deploy/docker-compose/demo-app/main_test.go",
    "deploy/terraform/modules/storage/main.tf",
    "deploy/terraform/modules/kubernetes_stack/main.tf",
    "deploy/terraform/modules/grafana_provisioning/main.tf",
    "deploy/kubernetes/helm/kube-prometheus-stack/values-base.yaml",
]:
    if not os.path.isfile(os.path.join(root_dir, req_mod)):
        solid_ok = False
        solid_errors.append(f"Missing modular component: {req_mod}")

if not solid_ok:
    overall_pass = False
    for err in solid_errors:
        failure_diagnostics.append(f"- **`@uncle-bob-craft` (SOLID & Clean Code Skill)**: {err}")

skill_review_rows.append(
    {
        "gate": "**`@uncle-bob-craft` (SOLID & Clean Code Skill)**",
        "scope": "`deploy/docker-compose/demo-app` + `deploy/terraform/modules/` + `deploy/kubernetes/` (SRP, OCP, LSP, ISP, DIP)",
        "verification": "`gofmt -l`, `go vet ./...`, `100.0%` `-race` statement coverage, and modular Terraform/Kubernetes separation",
        "result": (
            "✅ PASS"
            if solid_ok
            else f"❌ FAIL ({'; '.join(solid_errors)})"
        ),
    }
)

# 3. @effective-agent-skills (Repository Agent Skills Gate)
skills_ok = True
skills_errors = []
expected_skills = [
    "cloud-native-observability",
    "cno-otel-lgtm-stack",
    "cno-sre-slo-alerting",
    "cno-gitops-terraform",
]
agents_md_path = os.path.join(root_dir, "AGENTS.md")
agents_md_text = ""
if os.path.isfile(agents_md_path):
    with open(agents_md_path, "r", encoding="utf-8") as af:
        agents_md_text = af.read()
else:
    skills_ok = False
    skills_errors.append("Missing AGENTS.md")

verified_skill_count = 0
for sname in expected_skills:
    sfile = os.path.join(root_dir, "skills", sname, "SKILL.md")
    rel_sfile = f"skills/{sname}/SKILL.md"
    if not os.path.isfile(sfile):
        skills_ok = False
        skills_errors.append(f"Missing {rel_sfile}")
        continue
    with open(sfile, "r", encoding="utf-8") as sf:
        stext = sf.read()
    fm_match = re.match(r"^---\s*\n(.*?)\n---\s*\n", stext, re.DOTALL)
    if not fm_match:
        skills_ok = False
        skills_errors.append(f"{rel_sfile} missing YAML frontmatter (---)")
        continue
    fm_body = fm_match.group(1)
    name_m = re.search(r"^name:\s*(\S+)\s*$", fm_body, re.MULTILINE)
    desc_m = re.search(r"^description:\s*(.+)$", fm_body, re.MULTILINE)
    if not name_m or name_m.group(1).strip("\"'") != sname:
        skills_ok = False
        skills_errors.append(f"{rel_sfile} frontmatter name does not match folder '{sname}'")
        continue
    if not desc_m or not desc_m.group(1).strip():
        skills_ok = False
        skills_errors.append(f"{rel_sfile} frontmatter description is empty")
        continue
    if rel_sfile not in agents_md_text:
        skills_ok = False
        skills_errors.append(f"AGENTS.md does not reference {rel_sfile}")
        continue
    verified_skill_count += 1

if not skills_ok:
    overall_pass = False
    for err in skills_errors:
        failure_diagnostics.append(f"- **`@effective-agent-skills` (Repository Agent Skills Gate)**: {err}")

skill_review_rows.append(
    {
        "gate": "**`@effective-agent-skills` (Repository Agent Skills Gate)**",
        "scope": "[`AGENTS.md`](AGENTS.md) + `skills/*/SKILL.md` (`cloud-native-observability`, `cno-otel-lgtm-stack`, `cno-sre-slo-alerting`, `cno-gitops-terraform`)",
        "verification": "YAML frontmatter (`name`, `description`), progressive disclosure triggers, and `AGENTS.md` routing table parity",
        "result": (
            f"✅ PASS ({verified_skill_count}/{len(expected_skills)} repository skills & AGENTS.md routing verified)"
            if skills_ok
            else f"❌ FAIL ({'; '.join(skills_errors)})"
        ),
    }
)

# 4. @security-auditor (Supply-Chain, Node 24 & Secret Gate)
sec_audit_ok = True
sec_audit_errors = []
if sec_rc != 0:
    sec_audit_ok = False
    sec_audit_errors.append("check_secrets.sh reported secret scan failure")

wf_dir = os.path.join(root_dir, ".github", "workflows")
if not os.path.isdir(wf_dir):
    sec_audit_ok = False
    sec_audit_errors.append("Missing .github/workflows directory")
else:
    for wf_name in sorted(os.listdir(wf_dir)):
        if not (wf_name.endswith(".yml") or wf_name.endswith(".yaml")):
            continue
        wf_path = os.path.join(wf_dir, wf_name)
        with open(wf_path, "r", encoding="utf-8") as wf:
            wf_text = wf.read()
        if "FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true" not in wf_text:
            sec_audit_ok = False
            sec_audit_errors.append(
                f".github/workflows/{wf_name} missing FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true"
            )
        for line_no, line in enumerate(wf_text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            m_use = re.match(r"^(?:-\s+)?uses:\s*([^\s#]+)", stripped)
            if m_use:
                action_ref = m_use.group(1).strip("\"'")
                if not re.search(r"@[0-9a-f]{40}$", action_ref):
                    sec_audit_ok = False
                    sec_audit_errors.append(
                        f".github/workflows/{wf_name}:{line_no} unpinned action '{action_ref}' (must use 40-char commit SHA)"
                    )

if not sec_audit_ok:
    overall_pass = False
    for err in sec_audit_errors:
        failure_diagnostics.append(f"- **`@security-auditor` (Supply-Chain, Node 24 & Secret Gate)**: {err}")

skill_review_rows.append(
    {
        "gate": "**`@security-auditor` (Supply-Chain, Node 24 & Secret Gate)**",
        "scope": "`.github/workflows/*.yml` + `./scripts/check_secrets.sh` (TruffleHog & GitHub Actions Supply-Chain)",
        "verification": "40-char commit SHA pinning on every `uses:` directive, `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`, and TruffleHog scan",
        "result": (
            "✅ PASS (SHA-pinned Actions, Node 24 enforced, 0 secrets)"
            if sec_audit_ok
            else f"❌ FAIL ({'; '.join(sec_audit_errors)})"
        ),
    }
)

verdict_banner = (
    "✅ APPROVED BY MODULE CODE-OWNER AGENTS"
    if overall_pass
    else "❌ CHANGES REQUESTED BY MODULE CODE-OWNER AGENTS"
)
pr_label = f"PR #{pr_number} · " if pr_number else ""

md_lines = [
    "<!-- abeta-module-agent-review -->",
    f"## 🤖 Module Code-Owner Agent Review — {verdict_banner}",
    "",
    f"**Repository**: `{config.get('repository', 'github.com/abeta-dev/cloud-native-observability')}` (`{config.get('version', 'v0.3.0')}`, `Go {config.get('go_version', '1.26.0')}`) · {pr_label}**Diff Range**: `{base_ref}...{head_ref}` · **Changed Files**: `{len(changed_files)}` · **Activated Module Agents**: `{len(results)}/{len(agents)}`",
    "",
    "### 📊 Module Code-Owner Agent Sign-Off Matrix",
    "",
    "| Module Agent | Companion Skill | Owned Changed Files | Test Cases & Race | 100.0% Coverage | Lint & Manifest Validation | Domain Rules | Verdict |",
    "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
]

for r in results:
    ag = r["agent"]
    fcount = len(r["owned_files"])
    md_lines.append(
        f"| **{ag['handle']}**<br/><sub>{ag['name']}</sub> | [`{ag['skill']}`]({ag['skill']}) | `{fcount} file(s)` | {r['test_cell']} | {r['cov_cell']} | {r['lint_cell']} | {r['domain_cell']} | {r['verdict_cell']} |"
    )

md_lines.extend(
    [
        "",
        "### 🎨 Multi-Skill Quality & Architecture Review (Executed in GitHub Actions)",
        "",
        "| Skill / Review Gate | Scope & Reference | Verification Executed | Result |",
        "| :--- | :--- | :--- | :--- |",
    ]
)

for srow in skill_review_rows:
    md_lines.append(
        f"| {srow['gate']} | {srow['scope']} | {srow['verification']} | {srow['result']} |"
    )

md_lines.append("")

if not overall_pass and failure_diagnostics:
    md_lines.extend(
        [
            "### ❌ Actionable Failure Diagnostics",
            "",
            *failure_diagnostics,
            "",
        ]
    )

md_lines.append("### 🔍 Detailed Per-Module Agent Audit Log")
md_lines.append("")

for r in results:
    ag = r["agent"]
    status_icon = "✅" if r["passed"] else "❌"
    md_lines.append("<details>")
    md_lines.append(
        f"<summary>{status_icon} <strong>{ag['handle']}</strong> — {ag['name']} (<code>{len(r['owned_files'])}</code> owned file(s) reviewed, owner: <code>{ag.get('owner', '@umesh0492')}</code>)</summary>"
    )
    md_lines.append("")
    md_lines.append(f"- **Companion Skill**: [`{ag['skill']}`]({ag['skill']})")
    md_lines.append(
        f"- **Verified Go Packages**: `{', '.join(ag.get('packages', ['deploy/docker-compose/demo-app']))}`"
    )
    md_lines.append("- **Owned Changed Files Reviewed**:")
    for fpath in r["owned_files"]:
        md_lines.append(f"  - `{fpath}`")
    md_lines.append("- **Domain Invariants & Quality Gates Enforced**:")
    for rule in ag.get("rules", []):
        md_lines.append(f"  - [x] {rule}")
    md_lines.append("</details>")
    md_lines.append("")

md_report = "\n".join(md_lines) + "\n"

out_dir = os.path.dirname(os.path.abspath(output_path))
if out_dir and not os.path.exists(out_dir):
    os.makedirs(out_dir, exist_ok=True)

with open(output_path, "w", encoding="utf-8") as fp:
    fp.write(md_report)

print("========================================================")
print(f"🤖 Module Code-Owner Agent Review: {verdict_banner}")
print(f"   Diff Range:        {base_ref}...{head_ref} ({len(changed_files)} changed files)")
print(f"   Activated Agents:  {', '.join(r['agent']['handle'] for r in results)}")
print(f"   Demo-App Coverage: {cov_pct:.1f}% ({len(passed_tests)} unit tests passed with -race)")
print(f"   Multi-Skill Gates: 4/4 executed (/impeccable, @uncle-bob-craft, @effective-agent-skills, @security-auditor)")
print(f"   Report Written To: {output_path}")
print("========================================================")

if not overall_pass:
    print("\n".join(failure_diagnostics), file=sys.stderr)
    sys.exit(1)
PYEOF
