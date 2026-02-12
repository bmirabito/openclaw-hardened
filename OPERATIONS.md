# OpenClaw Operations Guide

Day-to-day reference for managing your OpenClaw instances from your MacBook Pro.
The Mac Mini runs headless (lid closed, no monitor) — everything below is done remotely.

---

## Connecting to the Mac Mini

All access goes through Tailscale. The Mac Mini's Tailscale IP is stable and doesn't change.

```bash
# SSH in
ssh user@<mac-mini-tailscale-ip>

# Or use the Tailscale hostname
ssh user@mac-mini
```

Find the Tailscale IP: open Tailscale on either machine, or run `tailscale ip` on the Mac Mini.

---

## Monitoring

### Web Dashboard (Portainer)

Open in any browser on your MacBook:
```
https://<mac-mini-tailscale-ip>:9443
```

Shows: live CPU/memory/network per container, health status, restart counts, logs, container shell.

### Terminal Quick Check

```bash
# From your MacBook — no need to SSH first
ssh user@<mac-mini-tailscale-ip> ~/openclaw/status.sh
```

Shows all container status, resource usage, health, restart counts, and OOM status in one shot.

### Telegram Alerts

Automatic every 5 minutes via cron. You'll get a Telegram message if any container is down, unhealthy, or OOM-killed. No news is good news.

### External Dashboards

| Service | URL | What to check |
|---|---|---|
| ElevenLabs usage | https://elevenlabs.io/app/usage | Credit consumption, plan limits |
| ElevenLabs calls | https://elevenlabs.io/app/conversational-ai → Calls | Call logs, failed calls |
| Twilio | https://console.twilio.com → Usage | Call minutes, spend |
| Anthropic API | https://console.anthropic.com/usage | Token usage, spend, rate limits |
| AWS Secrets Manager | AWS Console → Secrets Manager | Rotation status, access logs |

---

## Transferring Files (MacBook → Mac Mini)

### SCP (single files or folders)

```bash
# Single file
scp ~/Desktop/some-file.json user@<mac-mini-tailscale-ip>:~/openclaw/

# Folder
scp -r ~/Desktop/my-folder/ user@<mac-mini-tailscale-ip>:~/openclaw/
```

### rsync (sync a directory — only sends what changed)

```bash
rsync -avz ~/Desktop/openclaw-updates/ user@<mac-mini-tailscale-ip>:~/openclaw/
```

### Tailscale Taildrop (drag-and-drop, no terminal)

- Tailscale menu bar → right-click Mac Mini → "Send file..."
- Or in Finder: Share → Tailscale
- Files arrive in `~/Downloads` on the Mac Mini

### SFTP (browse like a folder)

- Finder → Go → Connect to Server → `sftp://<mac-mini-tailscale-ip>`
- Or use Cyberduck / Transmit for a GUI

---

## Common Operations

### Check container status

```bash
ssh user@<mac-mini-tailscale-ip> "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

### View logs for an instance

```bash
# Last 100 lines
ssh user@<mac-mini-tailscale-ip> "docker logs --tail 100 openclaw-jake"

# Follow live
ssh user@<mac-mini-tailscale-ip> "docker logs -f openclaw-jake"
```

### Restart a single instance

```bash
ssh user@<mac-mini-tailscale-ip> "docker restart openclaw-jake"
```

### Restart all instances

```bash
ssh user@<mac-mini-tailscale-ip> "cd ~/openclaw && docker compose restart"
```

### Stop / start all instances

```bash
# Stop
ssh user@<mac-mini-tailscale-ip> "cd ~/openclaw && docker compose down"

# Start
ssh user@<mac-mini-tailscale-ip> "cd ~/openclaw && docker compose up -d"
```

### Pull updated image and redeploy

```bash
ssh user@<mac-mini-tailscale-ip> "cd ~/openclaw && docker compose pull && docker compose up -d"
```

### Run a secrets audit

```bash
ssh user@<mac-mini-tailscale-ip> "bash ~/openclaw/scripts/audit-secrets.sh jake"
```

### Check resource usage (snapshot)

```bash
ssh user@<mac-mini-tailscale-ip> "docker stats --no-stream"
```

### Exec into a running container

```bash
ssh user@<mac-mini-tailscale-ip> "docker exec -it openclaw-jake /bin/bash"
```

---

## Updating Secrets

Secrets live in AWS Secrets Manager, not on disk. To rotate a key:

```bash
# Update a secret (from any machine with AWS CLI configured)
aws secretsmanager put-secret-value \
  --secret-id openclaw/jake/anthropic-api \
  --secret-string '{"api_key": "sk-ant-NEW-KEY-HERE"}' \
  --region us-east-2

# Restart the instance to pick up the new secret
ssh user@<mac-mini-tailscale-ip> "docker restart openclaw-jake"
```

The container pulls secrets fresh from AWS on every start via `entrypoint.sh`.

---

## Backup & Recovery

### What's persistent

Each instance stores its data in `~/openclaw/data/<instance>/`:
- `memory/` — conversation history and context
- `config/` — generated `openclaw.json` (no secrets — those come from AWS at startup)

### Backup

```bash
# From your MacBook — pull a backup
rsync -avz user@<mac-mini-tailscale-ip>:~/openclaw/data/ ~/Desktop/openclaw-backup/
```

### Restore

```bash
# Push a backup back
rsync -avz ~/Desktop/openclaw-backup/ user@<mac-mini-tailscale-ip>:~/openclaw/data/
ssh user@<mac-mini-tailscale-ip> "cd ~/openclaw && docker compose restart"
```

---

## Troubleshooting

### Container keeps restarting

```bash
# Check why it died
ssh user@<mac-mini-tailscale-ip> "docker logs --tail 50 openclaw-jake"

# Check if it was OOM-killed
ssh user@<mac-mini-tailscale-ip> "docker inspect --format='OOM: {{.State.OOMKilled}} | Exit: {{.State.ExitCode}}' openclaw-jake"
```

### Can't SSH into Mac Mini

1. Check Tailscale is running on both machines (menu bar icon)
2. Try `ping <mac-mini-tailscale-ip>` from your MacBook
3. If Tailscale is down on the Mac Mini, you need physical access (one-time fix)

### Container is healthy but bot isn't responding

1. Check the logs for errors: `docker logs --tail 100 openclaw-jake`
2. Verify secrets loaded: look for "Secrets loaded" in logs
3. Check external service status (ElevenLabs, Anthropic, Twilio dashboards)
4. Restart the instance: `docker restart openclaw-jake`

### Disk filling up

```bash
# Check disk usage
ssh user@<mac-mini-tailscale-ip> "df -h"

# Check Docker disk usage
ssh user@<mac-mini-tailscale-ip> "docker system df"

# Clean up old images/containers (safe — only removes unused)
ssh user@<mac-mini-tailscale-ip> "docker system prune -f"
```

### Need to access the Mac Mini physically

You should only need physical access if:
- Tailscale/SSH is completely broken
- macOS needs a firmware update that requires restart + login
- Hardware failure

Keep a keyboard and HDMI adapter nearby, just in case.

---

## Instance Reference

| Instance | Container | Port | Secrets Path |
|----------|-----------|------|--------------|
| Jake | `openclaw-jake` | 18789 | `openclaw/jake/*` |
| Clay | `openclaw-clay` | 18790 | `openclaw/clay/*` |
| Reed | `openclaw-reed` | 18791 | `openclaw/reed/*` |

Shared secrets (used by all instances): `openclaw/shared/*`

---

## Key Paths on the Mac Mini

```
~/openclaw/                     # Project root
~/openclaw/docker-compose.yml   # Container definitions
~/openclaw/data/jake/           # Jake's persistent data
~/openclaw/data/clay/           # Clay's persistent data
~/openclaw/data/reed/           # Reed's persistent data
~/openclaw/scripts/             # Setup and audit scripts
~/openclaw/status.sh            # Quick status script
~/openclaw/health-alert.sh      # Cron-based Telegram alerts
```
