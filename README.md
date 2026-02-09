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

## Quick Start

### 1. Harden the host (fresh Ubuntu 24.04)

```bash
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

```
openclaw/<instance>/anthropic-api     → {"api_key": "..."}
openclaw/<instance>/telegram-bot      → {"token": "..."}
openclaw/<instance>/gateway-auth      → {"token": "...", "port": "18789"}
openclaw/<instance>/fireflies-api     → {"api_key": "...", "hooks_token": "...", "hooks_secret": "..."} (optional)
openclaw/shared/brave-search-api      → {"api_key": "..."}
openclaw/shared/elevenlabs-api        → {"api_key": "..."}
openclaw/shared/gemini-api            → {"api_key": "..."}
openclaw/shared/tailscale-authkey     → {"authkey": "tskey-auth-..."}
```

## File Structure

```
├── Dockerfile              # Pinned Ubuntu 24.04 + Node 22 + OpenClaw
├── docker-compose.yml      # Hardened container config (parameterized)
├── entrypoint.sh           # Secrets loading + config generation
├── .dockerignore
├── .gitignore
├── scripts/
│   ├── harden-host.sh      # Host-level security (UFW, SSH, Fail2ban)
│   ├── setup-secrets.sh    # AWS Secrets Manager bootstrapping
│   └── deploy.sh           # Instance deployment helper
└── data/                   # (gitignored) per-instance persistent data
```
