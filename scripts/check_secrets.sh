#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

# ==============================================================================
# Credential & Secret Leak Prevention Gate
# Ensures no private keys, cloud tokens, API keys, .env files, or production
# connection strings are tracked or committed in the repository.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

echo "========================================================"
echo "🔐 Scanning Repository for Leaked Credentials & Secrets"
echo "========================================================"

# 1. Check for forbidden credential/secret files tracked in git
FORBIDDEN_FILES=""
while IFS= read -r file; do
  [ -z "$file" ] && continue
  base="$(basename "$file")"
  case "$base" in
    .env.example|.env.sample|.env.template)
      continue
      ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|*.pkcs12|id_rsa|id_ed25519|id_ecdsa|id_dsa|.netrc|.npmrc|.pypirc|.dockercfg|kubeconfig|*service-account*.json|*client_secret*.json|*credentials*.json)
      FORBIDDEN_FILES="${FORBIDDEN_FILES}${file}"$'\n'
      ;;
  esac
done < <(git ls-files)

if [ -n "$FORBIDDEN_FILES" ]; then
  echo "❌ Error: Forbidden credential or key file(s) tracked in git:"
  printf "%s" "$FORBIDDEN_FILES"
  exit 1
fi
echo "   - Tracked file inventory: zero forbidden key/.env files ✅"

# 2. Check for PEM Private Key headers across all tracked files
PRIVATE_KEY_PATTERN="-----BEGIN ""(RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY-----"
PRIVATE_KEY_MATCHES=$(git grep -I -n -E "$PRIVATE_KEY_PATTERN" -- . ':!scripts/check_secrets.sh' 2>/dev/null || true)
if [ -n "$PRIVATE_KEY_MATCHES" ]; then
  echo "❌ Error: Private key header detected in tracked files:"
  echo "$PRIVATE_KEY_MATCHES"
  exit 1
fi
echo "   - PEM/SSH private key scan: clean ✅"

# 3. Check for high-confidence Cloud, VCS, Payment Gateway & SaaS API tokens
TOKEN_REGEX="((A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{82}|glpat-[A-Za-z0-9\\-_]{20,}|xox[baprs]-[0-9]{10,13}-[0-9]{10,13}-[a-zA-Z0-9]{24,34}|https://hooks\\.slack\\.com/services/T[A-Z0-9]{8,}/B[A-Z0-9]{8,}/[A-Za-z0-9]{24,}|(sk|rk)_live_[0-9a-zA-Z]{24,}|AIza[0-9A-Za-z\\-_]{35}|SG\\.[A-Za-z0-9_\\-]{22}\\.[A-Za-z0-9_\\-]{43}|xkeysib-[a-f0-9]{64}-[A-Za-z0-9]{16}|sk-proj-[A-Za-z0-9_\\-]{40,}|sk-ant-api03-[A-Za-z0-9_\\-]{40,}|rzp_live_[A-Za-z0-9]{14})"

TOKEN_MATCHES=$(git grep -I -n -E "$TOKEN_REGEX" -- . ':!scripts/check_secrets.sh' 2>/dev/null || true)
if [ -n "$TOKEN_MATCHES" ]; then
  echo "❌ Error: Leaked cloud/API/VCS secret token detected in tracked files:"
  echo "$TOKEN_MATCHES"
  exit 1
fi
echo "   - Cloud/VCS/Payment/API token scan: clean ✅"

# 4. Check for non-local database/broker URLs with embedded credentials
DSN_MATCHES=$(git grep -I -n -E '(postgres|postgresql|mysql|mongodb|mongodb\+srv|redis|rediss|amqp|amqps)://[^/\s:@]+:[^/\s@]+@[^/\s"'"'"'`]+' -- . ':!scripts/check_secrets.sh' 2>/dev/null || true)
if [ -n "$DSN_MATCHES" ]; then
  LEAKED_DSNS=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if echo "$line" | grep -qE '@(localhost|127\.0\.0\.1|0\.0\.0\.0|postgres|db|redis|mysql|mongo|rabbitmq|example\.com|host|\$\{|<)'; then
      continue
    fi
    if echo "$line" | grep -qE '://[^/\s:@]+:(\*\*\*|password|pass|secret|postgres|test|admin|\$\{|<)'; then
      continue
    fi
    LEAKED_DSNS="${LEAKED_DSNS}${line}"$'\n'
  done <<< "$DSN_MATCHES"

  if [ -n "$LEAKED_DSNS" ]; then
    echo "❌ Error: Non-local connection string with embedded credentials detected:"
    printf "%s" "$LEAKED_DSNS"
    exit 1
  fi
fi
echo "   - Connection string credential scan: clean ✅"

# 5. Deep git history & entropy scan via TruffleHog (when available in PATH or /tmp/trufflehog)
TRUFFLEHOG_BIN=""
if command -v trufflehog >/dev/null 2>&1; then
  TRUFFLEHOG_BIN="trufflehog"
elif [ -x "/tmp/trufflehog" ]; then
  TRUFFLEHOG_BIN="/tmp/trufflehog"
fi

if [ -n "$TRUFFLEHOG_BIN" ]; then
  "$TRUFFLEHOG_BIN" git file://. --only-verified --fail --no-update
  echo "   - TruffleHog git history secret scan: clean ✅"
else
  echo "   - TruffleHog binary not found in PATH (skipping deep git history entropy scan; enforced in CI) ℹ️"
fi

echo "========================================================"
echo "✅ Zero leaked credentials or secrets detected!"
echo "========================================================"
