#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Strict N+2 Minor-Release Deprecation Window Gate (cloud-native-observability)
# Enforces canonical deprecation notices across Go source files:
# // Deprecated: Since vX.Y.Z (remove in >= vA.B.C). Use <Replacement> instead.
# where vA.B.C is at least 2 minor releases after vX.Y.Z (B >= Y + 2 when A == X).
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

echo "========================================================"
echo "⏳ Verifying Strict N+2 Deprecation Policy (cloud-native-observability)"

python3 - <<'EOF'
import glob
import re
import sys

PATTERN = re.compile(
    r'^// Deprecated: Since v(\d+)\.(\d+)\.(\d+) \(remove in >= v(\d+)\.(\d+)\.(\d+)\)\. Use .+ instead\.$'
)

errors = []
checked_files = 0
deprecation_count = 0

for path in sorted(glob.glob("deploy/docker-compose/demo-app/**/*.go", recursive=True)):
    if path.endswith("_test.go"):
        continue
    checked_files += 1
    with open(path, "r", encoding="utf-8") as fp:
        for lineno, raw_line in enumerate(fp, start=1):
            line = raw_line.strip()
            if not line.startswith("// Deprecated:"):
                continue
            deprecation_count += 1
            m = PATTERN.match(line)
            if not m:
                errors.append(
                    f"{path}:{lineno}: invalid format: '{line}' "
                    "(expected '// Deprecated: Since vX.Y.Z (remove in >= vA.B.C). Use <Replacement> instead.')"
                )
                continue
            s_maj, s_min, _s_patch, r_maj, r_min, _r_patch = map(int, m.groups())
            if (r_maj < s_maj) or (r_maj == s_maj and r_min < s_min + 2):
                errors.append(
                    f"{path}:{lineno}: removal version v{r_maj}.{r_min}.0 violates N+2 minor release window "
                    f"for deprecation introduced in v{s_maj}.{s_min}.0"
                )

if errors:
    print("❌ Error: Deprecation policy violations detected:")
    for err in errors:
        print(f"   - {err}")
    sys.exit(1)

print(f"   - Scanned {checked_files} production Go files ({deprecation_count} deprecation notices, 0 violations) ✅")
EOF

echo "✅ Strict N+2 deprecation window gate passed!"
