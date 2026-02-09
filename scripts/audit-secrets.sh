#!/bin/bash
# =============================================================================
# OpenClaw Secrets Audit
#
# Scans the host and container for credentials, tokens, API keys, passwords,
# and other sensitive material that should be in AWS Secrets Manager instead
# of on disk. Run this after deployment or periodically to catch drift.
#
# Usage: bash audit-secrets.sh [instance-name]
#
# Example: bash audit-secrets.sh jake
# =============================================================================
set -euo pipefail

INSTANCE_NAME="${1:-}"
CONTAINER_NAME=""
if [ -n "$INSTANCE_NAME" ]; then
  CONTAINER_NAME="openclaw-${INSTANCE_NAME}"
fi

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

FINDINGS=0
WARNINGS=0

finding() {
  echo -e "  ${RED}FINDING:${NC} $1"
  FINDINGS=$((FINDINGS + 1))
}

warning() {
  echo -e "  ${YELLOW}WARNING:${NC} $1"
  WARNINGS=$((WARNINGS + 1))
}

ok() {
  echo -e "  ${GREEN}OK:${NC} $1"
}

echo "=== OpenClaw Secrets Audit ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Host: $(hostname)"
[ -n "$INSTANCE_NAME" ] && echo "Instance: ${INSTANCE_NAME}"
echo ""

# Patterns that indicate secrets (used across multiple checks)
SECRET_PATTERNS='(sk-ant-|tskey-auth-|api_key|api-key|apikey|secret_key|secretkey|access_key|accesskey|password|passwd|token|bearer|authorization|private_key|BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY)'
# Narrower pattern for config files (catches key-value assignments)
CONFIG_PATTERNS='(api_key|api-key|apiKey|secret|token|password|auth_token|authkey|private_key)\s*[:=]\s*["\x27]?[A-Za-z0-9_\-]{8,}'

# ---------------------------------------------------------------------------
# 1. Scan home directory for exposed secrets
# ---------------------------------------------------------------------------
echo "[1/8] Scanning home directory for hardcoded secrets..."

# Check common locations
SCAN_DIRS=("/home/ubuntu" "/root")
for dir in "${SCAN_DIRS[@]}"; do
  [ -d "$dir" ] || continue

  # .env files (outside of tmpfs)
  while IFS= read -r envfile; do
    # Skip tmpfs locations
    if [[ "$envfile" == /tmp/* ]] || [[ "$envfile" == /run/* ]]; then
      continue
    fi
    finding "Env file on persistent storage: ${envfile}"
  done < <(find "$dir" -name '.env' -o -name '*.env' 2>/dev/null || true)

  # Config files with embedded secrets
  while IFS= read -r match; do
    finding "Possible secret in config file: ${match}"
  done < <(grep -rlEi "$CONFIG_PATTERNS" \
    --include='*.json' --include='*.yml' --include='*.yaml' \
    --include='*.toml' --include='*.conf' --include='*.cfg' \
    --include='*.ini' --include='*.properties' \
    "$dir" 2>/dev/null \
    | grep -v node_modules \
    | grep -v '.npm' \
    | grep -v 'package.json' \
    | grep -v 'package-lock.json' \
    | grep -v 'openclaw-hardened' \
    || true)
done

# ---------------------------------------------------------------------------
# 2. Check openclaw.json on disk (should be secrets-free)
# ---------------------------------------------------------------------------
echo "[2/8] Checking openclaw.json files on disk..."

while IFS= read -r ocfile; do
  # Skip tmpfs
  if [[ "$ocfile" == /tmp/* ]]; then
    ok "openclaw.json in tmpfs (expected): ${ocfile}"
    continue
  fi
  # Check for actual secret values (not just field names)
  if grep -qEi '(sk-ant-|"api_key"\s*:\s*"[^"]{10,}|"token"\s*:\s*"[^"]{10,}|"authkey"\s*:\s*"tskey-)' "$ocfile" 2>/dev/null; then
    finding "openclaw.json contains secrets on persistent storage: ${ocfile}"
  elif [ -f "$ocfile" ]; then
    ok "openclaw.json exists but appears secrets-free: ${ocfile}"
  fi
done < <(find / -name 'openclaw.json' -not -path '*/node_modules/*' -not -path '*/openclaw-hardened/*' 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 3. Check bash history for leaked secrets
# ---------------------------------------------------------------------------
echo "[3/8] Scanning shell history for secrets..."

HISTORY_FILES=(
  "/home/ubuntu/.bash_history"
  "/home/ubuntu/.zsh_history"
  "/root/.bash_history"
  "/root/.zsh_history"
)

for hfile in "${HISTORY_FILES[@]}"; do
  [ -f "$hfile" ] || continue
  if grep -qEi "$SECRET_PATTERNS" "$hfile" 2>/dev/null; then
    # Count matches
    count=$(grep -cEi "$SECRET_PATTERNS" "$hfile" 2>/dev/null || echo 0)
    warning "Shell history may contain ${count} secret(s): ${hfile}"
    echo "         Consider: history -c && rm ${hfile}"
  else
    ok "No secrets detected in: ${hfile}"
  fi
done

# ---------------------------------------------------------------------------
# 4. Check environment variables of running processes
# ---------------------------------------------------------------------------
echo "[4/8] Checking environment variables in running processes..."

if [ -n "$CONTAINER_NAME" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
  # Check that secrets are only in the openclaw process, not in docker inspect
  INSPECT_ENV=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)
  if echo "$INSPECT_ENV" | grep -qEi '(ANTHROPIC_API_KEY|TELEGRAM_BOT_TOKEN|GATEWAY_AUTH_TOKEN|ELEVENLABS_API_KEY|BRAVE_API_KEY|GEMINI_API_KEY)'; then
    finding "Secrets visible in 'docker inspect' — they should only be in entrypoint env, not docker-compose environment"
  else
    ok "No secrets exposed in docker inspect environment"
  fi
else
  [ -n "$CONTAINER_NAME" ] && warning "Container ${CONTAINER_NAME} not running — skipping container inspection"
fi

# ---------------------------------------------------------------------------
# 5. Check docker-compose files for hardcoded secrets
# ---------------------------------------------------------------------------
echo "[5/8] Scanning docker-compose files..."

while IFS= read -r composefile; do
  [[ "$composefile" == *openclaw-hardened* ]] && continue
  if grep -qEi '(sk-ant-|ANTHROPIC_API_KEY=.{10,}|TELEGRAM_BOT_TOKEN=.{10,}|api_key=.{10,})' "$composefile" 2>/dev/null; then
    finding "Docker compose file contains hardcoded secrets: ${composefile}"
  else
    ok "Clean: ${composefile}"
  fi
done < <(find /home -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 6. Check for credential files on disk
# ---------------------------------------------------------------------------
echo "[6/8] Scanning for credential files..."

CRED_PATTERNS=("credentials" "secrets" "keyfile" "service-account" "gcloud" ".boto")
for pattern in "${CRED_PATTERNS[@]}"; do
  while IFS= read -r credfile; do
    [[ "$credfile" == *node_modules* ]] && continue
    [[ "$credfile" == *openclaw-hardened* ]] && continue
    [[ "$credfile" == */man/* ]] && continue
    [[ "$credfile" == */.aws/credentials ]] && { warning "AWS credentials file exists: ${credfile} (expected if using IAM user)"; continue; }
    warning "Potential credential file: ${credfile}"
  done < <(find /home -iname "*${pattern}*" -type f -not -path '*/node_modules/*' -not -path '*/.npm/*' 2>/dev/null || true)
done

# Check for private keys outside .ssh
while IFS= read -r keyfile; do
  [[ "$keyfile" == */.ssh/* ]] && continue
  [[ "$keyfile" == *node_modules* ]] && continue
  if grep -ql 'PRIVATE KEY' "$keyfile" 2>/dev/null; then
    finding "Private key found outside .ssh: ${keyfile}"
  fi
done < <(find /home -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 7. Check file permissions on sensitive files
# ---------------------------------------------------------------------------
echo "[7/8] Checking file permissions..."

# SSH keys should be 600
while IFS= read -r sshfile; do
  perms=$(stat -c '%a' "$sshfile" 2>/dev/null || stat -f '%A' "$sshfile" 2>/dev/null || echo "unknown")
  if [ "$perms" != "600" ] && [ "$perms" != "400" ] && [[ "$sshfile" != *".pub" ]] && [[ "$sshfile" != *"known_hosts"* ]] && [[ "$sshfile" != *"config" ]] && [[ "$sshfile" != *"authorized_keys" ]]; then
    warning "SSH key has loose permissions (${perms}): ${sshfile}"
  fi
done < <(find /home -path '*/.ssh/*' -type f 2>/dev/null || true)

# AWS credentials should be 600
AWS_CREDS="/home/ubuntu/.aws/credentials"
if [ -f "$AWS_CREDS" ]; then
  perms=$(stat -c '%a' "$AWS_CREDS" 2>/dev/null || stat -f '%A' "$AWS_CREDS" 2>/dev/null || echo "unknown")
  if [ "$perms" != "600" ]; then
    warning "AWS credentials have loose permissions (${perms}): ${AWS_CREDS}"
  else
    ok "AWS credentials permissions: ${perms}"
  fi
fi

# ---------------------------------------------------------------------------
# 8. Check inside container (if running)
# ---------------------------------------------------------------------------
echo "[8/8] Auditing inside container..."

if [ -n "$CONTAINER_NAME" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
  # Verify openclaw.json in container has no secrets
  CONTAINER_CONFIG=$(docker exec "$CONTAINER_NAME" cat /home/openclaw/.openclaw/openclaw.json 2>/dev/null || echo "")
  if [ -n "$CONTAINER_CONFIG" ]; then
    if echo "$CONTAINER_CONFIG" | grep -qEi '(sk-ant-|"api_key"\s*:\s*"[^"]{10,})'; then
      finding "openclaw.json INSIDE container contains API keys"
    else
      ok "openclaw.json inside container is secrets-free"
    fi
  fi

  # Check that .env on tmpfs is root-only
  ENV_PERMS=$(docker exec "$CONTAINER_NAME" stat -c '%a %U' /tmp/.env 2>/dev/null || echo "unknown")
  if [[ "$ENV_PERMS" == "600 root" ]]; then
    ok ".env in tmpfs is root-only (600 root)"
  elif [ "$ENV_PERMS" != "unknown" ]; then
    finding ".env in tmpfs has wrong permissions: ${ENV_PERMS} (expected: 600 root)"
  fi

  # Check no secrets leaked to writable volumes
  LEAKED=$(docker exec "$CONTAINER_NAME" grep -rlEi 'sk-ant-|tskey-auth-' /home/openclaw/clawd/ 2>/dev/null || true)
  if [ -n "$LEAKED" ]; then
    finding "Secrets found in workspace volume: ${LEAKED}"
  else
    ok "No secrets found in workspace volume"
  fi
else
  [ -n "$CONTAINER_NAME" ] && echo "  Container ${CONTAINER_NAME} not running — skipping container audit"
  [ -z "$CONTAINER_NAME" ] && echo "  No instance specified — skipping container audit (pass instance name as argument)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==========================================="
if [ "$FINDINGS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo -e "${GREEN}PASS: No findings or warnings.${NC}"
elif [ "$FINDINGS" -eq 0 ]; then
  echo -e "${YELLOW}PASS with ${WARNINGS} warning(s). Review items above.${NC}"
else
  echo -e "${RED}FAIL: ${FINDINGS} finding(s) and ${WARNINGS} warning(s).${NC}"
  echo ""
  echo "Findings indicate secrets on persistent storage that should"
  echo "be moved to AWS Secrets Manager. To fix:"
  echo ""
  echo "  1. Add the secret to AWS Secrets Manager:"
  echo "     aws secretsmanager create-secret --name 'openclaw/...' \\"
  echo "       --secret-string '{\"key\":\"value\"}' --region us-east-2"
  echo ""
  echo "  2. Update entrypoint.sh to load it at startup"
  echo ""
  echo "  3. Remove the hardcoded value from the file on disk"
  echo ""
  echo "  4. Re-run this audit to verify: bash scripts/audit-secrets.sh ${INSTANCE_NAME}"
fi
echo "==========================================="
exit "$FINDINGS"
