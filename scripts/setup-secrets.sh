#!/bin/bash
# =============================================================================
# OpenClaw AWS Secrets Manager Setup
#
# Creates the expected secret structure in AWS Secrets Manager for a new
# OpenClaw instance. Run this once per instance from a machine with AWS CLI
# configured.
#
# Usage: bash setup-secrets.sh <instance-name> [aws-region]
#
# Example: bash setup-secrets.sh mybot us-east-2
# =============================================================================
set -euo pipefail

INSTANCE_NAME="${1:?Usage: setup-secrets.sh <instance-name> [aws-region]}"
AWS_REGION="${2:-us-east-2}"

echo "=== OpenClaw Secrets Setup ==="
echo "Instance: ${INSTANCE_NAME}"
echo "Region:   ${AWS_REGION}"
echo ""

create_secret() {
  local secret_id="$1"
  local description="$2"
  local template="$3"

  if aws secretsmanager describe-secret --secret-id "$secret_id" --region "$AWS_REGION" &>/dev/null; then
    echo "  EXISTS: ${secret_id}"
  else
    aws secretsmanager create-secret \
      --name "$secret_id" \
      --description "$description" \
      --secret-string "$template" \
      --region "$AWS_REGION" \
      --output text --query 'ARN'
    echo "  CREATED: ${secret_id} (update the placeholder values!)"
  fi
}

# ---------------------------------------------------------------------------
# Required secrets (bot will not start without these)
# ---------------------------------------------------------------------------
echo "Creating REQUIRED per-instance secrets..."
create_secret "openclaw/${INSTANCE_NAME}/anthropic-api" \
  "Anthropic API key for ${INSTANCE_NAME}" \
  '{"api_key":"sk-ant-REPLACE_ME"}'

create_secret "openclaw/${INSTANCE_NAME}/telegram-bot" \
  "Telegram bot token for ${INSTANCE_NAME}" \
  '{"token":"REPLACE_ME"}'

create_secret "openclaw/${INSTANCE_NAME}/gateway-auth" \
  "Gateway auth token and port for ${INSTANCE_NAME}" \
  '{"token":"REPLACE_ME","port":"18789"}'

# ---------------------------------------------------------------------------
# Optional shared secrets (skip any you don't need)
# ---------------------------------------------------------------------------
echo ""
echo "The following secrets are OPTIONAL. Press Enter to create, or 's' to skip."
echo ""

prompt_optional() {
  local label="$1"
  local secret_id="$2"
  local description="$3"
  local template="$4"

  # Skip prompt if secret already exists
  if aws secretsmanager describe-secret --secret-id "$secret_id" --region "$AWS_REGION" &>/dev/null; then
    echo "  EXISTS: ${secret_id}"
    return
  fi

  read -rp "  Create ${label}? [Enter=yes, s=skip]: " choice
  if [ "${choice,,}" = "s" ]; then
    echo "  SKIPPED: ${secret_id}"
  else
    create_secret "$secret_id" "$description" "$template"
  fi
}

prompt_optional "Brave Search API key" \
  "openclaw/shared/brave-search-api" \
  "Brave Search API key (shared) — enables web search" \
  '{"api_key":"REPLACE_ME"}'

prompt_optional "ElevenLabs API key" \
  "openclaw/shared/elevenlabs-api" \
  "ElevenLabs API key (shared) — enables voice/TTS" \
  '{"api_key":"REPLACE_ME"}'

prompt_optional "Google Gemini API key" \
  "openclaw/shared/gemini-api" \
  "Gemini API key (shared) — enables Gemini model" \
  '{"api_key":"REPLACE_ME"}'

prompt_optional "Tailscale auth key" \
  "openclaw/shared/tailscale-authkey" \
  "Tailscale auth key (shared) — enables Tailscale networking" \
  '{"authkey":"tskey-auth-REPLACE_ME"}'

echo ""

# ---------------------------------------------------------------------------
# Optional per-instance secrets
# ---------------------------------------------------------------------------
echo "Optional per-instance secrets:"

prompt_optional "Fireflies API key" \
  "openclaw/${INSTANCE_NAME}/fireflies-api" \
  "Fireflies API key for ${INSTANCE_NAME} — enables meeting transcripts" \
  '{"api_key":"REPLACE_ME","hooks_token":"REPLACE_ME","hooks_secret":"REPLACE_ME"}'

echo ""
echo "=== Done ==="
echo ""
echo "IMPORTANT: Update any secrets showing 'REPLACE_ME' with real values:"
echo "  aws secretsmanager put-secret-value \\"
echo "    --secret-id 'openclaw/${INSTANCE_NAME}/anthropic-api' \\"
echo "    --secret-string '{\"api_key\":\"sk-ant-xxxxx\"}' \\"
echo "    --region ${AWS_REGION}"
