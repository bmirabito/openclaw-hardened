#!/bin/bash
set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_NAME="${INSTANCE_NAME:-bot}"

echo "=== OpenClaw Docker Entrypoint (hardened) ==="
echo "Instance: ${INSTANCE_NAME}"
echo "AWS Region: ${AWS_REGION}"

# ---------------------------------------------------------------------------
# 1. Pull secrets from AWS Secrets Manager
# ---------------------------------------------------------------------------
echo "Pulling secrets from AWS Secrets Manager..."

get_secret() {
  local secret_id="$1"
  aws secretsmanager get-secret-value \
    --secret-id "$secret_id" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text
}

# Per-instance secrets
ANTHROPIC_SECRET=$(get_secret "openclaw/${INSTANCE_NAME}/anthropic-api")
TELEGRAM_SECRET=$(get_secret "openclaw/${INSTANCE_NAME}/telegram-bot")
GATEWAY_SECRET=$(get_secret "openclaw/${INSTANCE_NAME}/gateway-auth")

# Shared secrets
BRAVE_SECRET=$(get_secret "openclaw/shared/brave-search-api")
ELEVENLABS_SECRET=$(get_secret "openclaw/shared/elevenlabs-api")
GEMINI_SECRET=$(get_secret "openclaw/shared/gemini-api")
TAILSCALE_SECRET=$(get_secret "openclaw/shared/tailscale-authkey")

# Parse JSON secrets
ANTHROPIC_API_KEY=$(echo "$ANTHROPIC_SECRET" | jq -r '.api_key')
TELEGRAM_BOT_TOKEN=$(echo "$TELEGRAM_SECRET" | jq -r '.token')
GATEWAY_AUTH_TOKEN=$(echo "$GATEWAY_SECRET" | jq -r '.token')
GATEWAY_PORT=$(echo "$GATEWAY_SECRET" | jq -r '.port')
BRAVE_API_KEY=$(echo "$BRAVE_SECRET" | jq -r '.api_key')
ELEVENLABS_API_KEY=$(echo "$ELEVENLABS_SECRET" | jq -r '.api_key')
GEMINI_API_KEY=$(echo "$GEMINI_SECRET" | jq -r '.api_key')
TAILSCALE_AUTHKEY=$(echo "$TAILSCALE_SECRET" | jq -r '.authkey')

# Optional per-instance secrets (add your own here)
FIREFLIES_API_KEY=""
HOOKS_TOKEN=""
FIREFLIES_WEBHOOK_SECRET=""
FIREFLIES_SECRET=$(get_secret "openclaw/${INSTANCE_NAME}/fireflies-api" 2>/dev/null || echo "")
if [ -n "$FIREFLIES_SECRET" ] && [ "$FIREFLIES_SECRET" != "" ]; then
  FIREFLIES_API_KEY=$(echo "$FIREFLIES_SECRET" | jq -r '.api_key // empty')
  HOOKS_TOKEN=$(echo "$FIREFLIES_SECRET" | jq -r '.hooks_token // empty')
  FIREFLIES_WEBHOOK_SECRET=$(echo "$FIREFLIES_SECRET" | jq -r '.hooks_secret // empty')
fi

echo "Secrets loaded successfully."

# ---------------------------------------------------------------------------
# 2. Write gateway port for health check
# ---------------------------------------------------------------------------
echo "$GATEWAY_PORT" > /tmp/gateway-port
echo "Gateway port: ${GATEWAY_PORT}"

# ---------------------------------------------------------------------------
# 3. Write .env to tmpfs (root-only permissions)
# ---------------------------------------------------------------------------
cat > /tmp/.env <<EOF
OPENCLAW_GATEWAY_PORT=${GATEWAY_PORT}
GATEWAY_AUTH_TOKEN=${GATEWAY_AUTH_TOKEN}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
GEMINI_API_KEY=${GEMINI_API_KEY}
BRAVE_API_KEY=${BRAVE_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
ELEVENLABS_API_KEY=${ELEVENLABS_API_KEY}
FIREFLIES_API_KEY=${FIREFLIES_API_KEY}
HOOKS_TOKEN=${HOOKS_TOKEN}
FIREFLIES_WEBHOOK_SECRET=${FIREFLIES_WEBHOOK_SECRET}
EOF
chmod 600 /tmp/.env
ln -sf /tmp/.env /home/openclaw/.openclaw/.env

# ---------------------------------------------------------------------------
# 4. Build openclaw.json (NO secrets in config file)
# ---------------------------------------------------------------------------
echo "Building openclaw.json (secrets stripped)..."

# Hooks section — only enable if hooks token was loaded
HOOKS_SECTION='"hooks": { "enabled": false }'
if [ -n "$HOOKS_TOKEN" ]; then
  # hooks.token must remain in config (no env var support in OpenClaw)
  HOOKS_SECTION=$(cat <<HOOKEOF
"hooks": {
    "enabled": true,
    "token": "${HOOKS_TOKEN}",
    "transformsDir": "/home/openclaw/.openclaw/transforms",
    "mappings": [
      {
        "id": "fireflies",
        "match": { "path": "fireflies" },
        "action": "agent",
        "deliver": true,
        "channel": "telegram",
        "transform": { "module": "fireflies.js", "export": "transform" }
      }
    ]
  }
HOOKEOF
)
fi

# Voice ID — override via VOICE_ID env var or defaults
VOICE_ID="${VOICE_ID:-XA2bIQ92TabjGbpO2xRr}"

# Telegram user authorization — set TELEGRAM_ALLOW_FROM env var
TELEGRAM_ALLOW_FROM="${TELEGRAM_ALLOW_FROM:-}"

# All secrets passed via environment variables instead of config.
# Only hooks.token remains in config (when hooks are enabled).
cat > /tmp/secrets/openclaw.json <<CONFIGEOF
{
  "meta": {
    "lastTouchedVersion": "docker-hardened",
    "lastTouchedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  },
  "auth": {
    "profiles": {
      "anthropic:default": {
        "provider": "anthropic",
        "mode": "api_key"
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-haiku-4-5"
      },
      "models": {
        "anthropic/claude-opus-4-5": {
          "alias": "opus",
          "params": { "cache_control": { "type": "ephemeral" } }
        },
        "anthropic/claude-sonnet-4-5": {
          "alias": "sonnet",
          "params": { "cache_control": { "type": "ephemeral" } }
        },
        "anthropic/claude-haiku-4-5": {
          "alias": "haiku",
          "params": { "cache_control": { "type": "ephemeral" } }
        }
      },
      "workspace": "/home/openclaw/clawd",
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 }
    }
  },
  "tools": {
    "web": {
      "search": { "enabled": true },
      "fetch": { "enabled": true }
    }
  },
  "messages": { "ackReactionScope": "group-mentions" },
  "commands": { "native": "auto", "nativeSkills": "auto" },
  "cron": { "enabled": true },
  ${HOOKS_SECTION},
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist",
      "streamMode": "partial"
    }
  },
  "talk": {
    "voiceId": "${VOICE_ID}",
    "modelId": "eleven_v3",
    "interruptOnSpeech": true
  },
  "gateway": {
    "port": ${GATEWAY_PORT},
    "mode": "local",
    "auth": {
      "mode": "token"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "skills": {
    "install": { "nodeManager": "npm" }
  },
  "plugins": {
    "entries": {
      "telegram": { "enabled": true }
    }
  }
}
CONFIGEOF

ln -sf /tmp/secrets/openclaw.json /home/openclaw/.openclaw/openclaw.json

echo "Config written (secrets-free)."

# ---------------------------------------------------------------------------
# 5. Start Tailscale
# ---------------------------------------------------------------------------
echo "Starting Tailscale..."

tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state &
sleep 2

if [ -n "$TAILSCALE_AUTHKEY" ]; then
  tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="docker-${INSTANCE_NAME}"
  echo "Tailscale connected as docker-${INSTANCE_NAME}"
else
  echo "WARNING: No TAILSCALE_AUTHKEY set. Tailscale not connected."
fi

# ---------------------------------------------------------------------------
# 6. Telegram authorization
# ---------------------------------------------------------------------------
if [ -n "$TELEGRAM_ALLOW_FROM" ]; then
  mkdir -p /home/openclaw/.openclaw/credentials
  echo "{ \"version\": 1, \"allowFrom\": [ \"${TELEGRAM_ALLOW_FROM}\" ] }" \
    > /home/openclaw/.openclaw/credentials/telegram-allowFrom.json
fi

# ---------------------------------------------------------------------------
# 7. Fix ownership and start
# ---------------------------------------------------------------------------
chown -R openclaw:openclaw /home/openclaw/.openclaw 2>/dev/null || true
chown openclaw:openclaw /tmp/secrets 2>/dev/null || true
chown openclaw:openclaw /tmp/secrets/openclaw.json 2>/dev/null || true

echo "Starting OpenClaw gateway (secrets via env vars)..."

exec su -s /bin/bash openclaw -c "
  export ANTHROPIC_API_KEY='${ANTHROPIC_API_KEY}'
  export BRAVE_API_KEY='${BRAVE_API_KEY}'
  export TELEGRAM_BOT_TOKEN='${TELEGRAM_BOT_TOKEN}'
  export ELEVENLABS_API_KEY='${ELEVENLABS_API_KEY}'
  export OPENCLAW_GATEWAY_TOKEN='${GATEWAY_AUTH_TOKEN}'
  export GEMINI_API_KEY='${GEMINI_API_KEY}'
  export FIREFLIES_API_KEY='${FIREFLIES_API_KEY}'
  export FIREFLIES_WEBHOOK_SECRET='${FIREFLIES_WEBHOOK_SECRET}'
  cd /home/openclaw && exec openclaw gateway run
"
