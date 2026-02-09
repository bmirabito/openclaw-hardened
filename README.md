# OpenClaw Hardened Docker

Hardened Docker deployment for OpenClaw bot instances. Packages all host-level and container-level security measures into a reusable template.

## Security Measures

### Container Hardening
- **Read-only root filesystem** — container cannot write to its own filesystem
- **No new privileges** — prevents privilege escalation via setuid/setgid
- **Capability dropping** — drops ALL capabilities, adds back only what's needed (NET_ADMIN, NET_RAW, DAC_OVERRIDE, SETUID, SETGID, FOWNER, CHOWN)
- **Resource limits** — memory (1.5GB), CPU (1.5 cores), PIDs (256)
- **Secrets in tmpfs** — API keys live in RAM-backed `/tmp/secrets`, never written to disk
- **Secrets via env vars** — `openclaw.json` contains zero secrets; all API keys passed as environment variables
- **AWS Secrets Manager** — secrets pulled at startup, not stored in config files or images
- **Bounded logging** — JSON file driver with 10MB max, 3 file rotation
- **Health checks** — automatic restart on gateway health failure
- **Pinned base image** — Ubuntu 24.04 with SHA256 digest pinning

### Host Hardening (`scripts/harden-host.sh`)
- **UFW firewall** — deny all incoming, allow SSH + Tailscale + Syncthing
- **SSH hardening** — pubkey-only auth, no root login, max 3 retries, `AllowUsers` restriction, client keepalive
- **Fail2ban** — SSH jail with 3 retries / 10min window / 1hr ban
- **Unattended upgrades** — automatic security patches

## Prerequisites

Before deploying, you need the following accounts and credentials ready.

### Required Accounts

These are needed for the bot to start:

1. **AWS account** with IAM credentials that have access to Secrets Manager
2. **Anthropic API key** — https://console.anthropic.com/settings/keys
3. **Telegram bot** — message [@BotFather](https://t.me/BotFather) on Telegram, run `/newbot`, and save the bot token
4. **Telegram user ID** — message [@userinfobot](https://t.me/userinfobot) to get your numeric user ID (used for `TELEGRAM_ALLOW_FROM`)

### Optional Accounts

Skip any of these — the bot will start without them and disable the corresponding features:

5. **Tailscale** — private networking between instances. https://login.tailscale.com/admin/settings/keys
6. **Brave Search API** — web search capability. https://brave.com/search/api/
7. **ElevenLabs API** — voice/TTS. https://elevenlabs.io/app/settings/api-keys
8. **Google Gemini API** — alternative model. https://aistudio.google.com/apikey
9. **Fireflies API** — meeting transcript ingestion. https://fireflies.ai/

### Host Requirements

The `scripts/install-prereqs.sh` script handles all of these automatically, but for reference:

- Ubuntu 24.04 LTS
- Docker Engine + Docker Compose v2
- AWS CLI v2 (configured with `aws configure`)

```bash
# Install Docker, AWS CLI, and configure prerequisites
sudo bash scripts/install-prereqs.sh

# Configure AWS credentials (interactive)
aws configure
```

## Quick Start

### 1. Install prerequisites and harden the host (fresh Ubuntu 24.04)

```bash
sudo bash scripts/install-prereqs.sh
sudo bash scripts/harden-host.sh ubuntu
```

### 2. Create secrets in AWS Secrets Manager

```bash
bash scripts/setup-secrets.sh mybot us-east-2
```

Then update the placeholder values with real API keys.

### 3. Deploy

```bash
bash scripts/deploy.sh mybot us-east-2
```

### Environment Variables

Set these in `docker-compose.yml` or pass via shell:

| Variable | Description | Default |
|----------|-------------|---------|
| `INSTANCE_NAME` | Bot instance name (used for secrets path and container name) | `bot` |
| `AWS_REGION` | AWS region for Secrets Manager | `us-east-2` |
| `VOICE_ID` | ElevenLabs voice ID | `XA2bIQ92TabjGbpO2xRr` |
| `TELEGRAM_ALLOW_FROM` | Telegram user ID to authorize | (none) |

### AWS Secrets Manager Structure

Required:
```
openclaw/<instance>/anthropic-api     → {"api_key": "..."}
openclaw/<instance>/telegram-bot      → {"token": "..."}
openclaw/<instance>/gateway-auth      → {"token": "...", "port": "18789"}
```

Optional (skip any you don't need — the bot will start without them):
```
openclaw/shared/brave-search-api      → {"api_key": "..."}          # Web search
openclaw/shared/elevenlabs-api        → {"api_key": "..."}          # Voice/TTS
openclaw/shared/gemini-api            → {"api_key": "..."}          # Gemini model
openclaw/shared/tailscale-authkey     → {"authkey": "tskey-auth-..."} # Private networking
openclaw/<instance>/fireflies-api     → {"api_key": "...", ...}     # Meeting transcripts
```

## Secrets Audit

A secrets audit runs automatically after every deployment. You can also run it manually.

### Single instance (run on the instance itself)

```bash
bash scripts/audit-secrets.sh mybot
```

### Single instance (run remotely via SSH)

```bash
ssh myserver "bash -s" < scripts/audit-secrets.sh mybot
```

### All instances at once (run from your local machine)

```bash
bash scripts/audit-all.sh jake:jake clay:clay reed:reed
```

Or create `~/.openclaw-instances` so you don't have to type them every time:

```
# ~/.openclaw-instances
jake:jake
clay:clay
reed:reed
```

Then just run:

```bash
bash scripts/audit-all.sh
```

### What the audit checks

- `.env` files on persistent storage (should only exist in tmpfs)
- Hardcoded API keys, tokens, or passwords in config files
- Secrets leaked into shell history
- Secrets visible in `docker inspect` output
- Private keys outside of `~/.ssh/`
- Loose file permissions on sensitive files
- Secrets inside the running container's workspace or config
- Credential files that should be in Secrets Manager

Any findings should be resolved by moving the secret to AWS Secrets Manager and removing it from disk.

## File Structure

```
├── Dockerfile              # Pinned Ubuntu 24.04 + Node 22 + OpenClaw
├── docker-compose.yml      # Hardened container config (parameterized)
├── entrypoint.sh           # Secrets loading + config generation
├── .dockerignore
├── .gitignore
├── scripts/
│   ├── install-prereqs.sh  # Docker + AWS CLI installation
│   ├── harden-host.sh      # Host-level security (UFW, SSH, Fail2ban)
│   ├── setup-secrets.sh    # AWS Secrets Manager bootstrapping
│   ├── deploy.sh           # Instance deployment helper
│   ├── audit-secrets.sh    # Post-deploy secrets audit (single instance)
│   └── audit-all.sh        # Audit all instances via SSH
└── data/                   # (gitignored) per-instance persistent data
```
