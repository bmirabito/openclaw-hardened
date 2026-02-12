# Mac Mini Setup Plan — OpenClaw Migration

Fresh Mac Mini → fully hardened, running jake, clay, and reed locally.

---

## Phase 1: Unbox and Initial macOS Setup

### 1.1 First Boot
- [ ] Power on, connect to monitor/keyboard, complete macOS setup
- [ ] Create your local user account (this becomes your admin user)
- [ ] Connect to Wi-Fi or Ethernet (Ethernet preferred for a server)
- [ ] Run all pending macOS updates: **System Settings → General → Software Update**

### 1.2 Enable Remote Access
- [ ] Enable SSH: **System Settings → General → Sharing → Remote Login → ON**
- [ ] Set "Allow access for" to **Only these users** → add your account
- [ ] Note the Mac Mini's local IP (System Settings → Network) — you'll SSH in from here on

### 1.3 Prevent Sleep
- [ ] **System Settings → Energy → Prevent automatic sleeping when the display is off** → ON
- [ ] **Start up automatically after a power failure** → ON
- [ ] **Wake for network access** → ON
- [ ] Set display to turn off after 5 minutes (saves energy, box stays awake)

### 1.4 Disable Unnecessary Services
- [ ] Turn off Bluetooth (unless you need it)
- [ ] Turn off AirDrop
- [ ] Turn off AirPlay Receiver (**System Settings → General → AirDrop & Handoff**)

At this point you can disconnect the monitor/keyboard and work via SSH.

---

## Phase 2: Install Prerequisites

### 2.1 Homebrew
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
Follow the post-install instructions to add Homebrew to your PATH.

### 2.2 Core Tools
```bash
brew install git jq coreutils
```

### 2.3 Docker Desktop for Mac
```bash
brew install --cask docker
```
Then open Docker Desktop once to complete setup. In Docker Desktop settings:
- **General → Start Docker Desktop when you log in** → ON
- **Resources → Memory** → at least 6 GB (you're running 3 containers)
- **Resources → CPUs** → at least 4
- Verify Docker works:
```bash
docker --version
docker compose version
```

### 2.4 AWS CLI v2 (Apple Silicon native)
```bash
brew install awscli
```
Then configure:
```bash
aws configure
# AWS Access Key ID: (your IAM key)
# AWS Secret Access Key: (your IAM secret)
# Default region: us-east-2
# Default output format: json
```
Verify:
```bash
aws sts get-caller-identity
```

### 2.5 Tailscale
```bash
brew install --cask tailscale
```
Open Tailscale from Applications, sign in, and connect. The Mac Mini will appear in your tailnet as a machine (not just a Docker container).

Alternatively, install the CLI-only version if you prefer headless:
```bash
brew install tailscale
sudo tailscaled &
sudo tailscale up
```

### 2.6 Syncthing (optional — for syncing data between machines)
```bash
brew install syncthing
brew services start syncthing
```
Access the web UI at http://localhost:8384 to configure folder sync.

---

## Phase 3: Harden the Mac Mini

### 3.1 macOS Firewall
```bash
# Enable the application firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Enable stealth mode (don't respond to pings from unknown sources)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Block all incoming except essential services
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
```
Tailscale and Docker handle their own networking and bypass the application firewall, so your bot traffic still works.

You can also enable via: **System Settings → Network → Firewall → ON → Options → Enable stealth mode**.

### 3.2 Harden SSH
```bash
# Backup the SSH config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Apply hardened settings
sudo tee -a /etc/ssh/sshd_config.d/hardened.conf > /dev/null << 'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowUsers YOUR_USERNAME_HERE
EOF
```
Replace `YOUR_USERNAME_HERE` with your actual macOS username.

Then reload SSH:
```bash
sudo launchctl kickstart -k system/com.openssh.sshd
```

Make sure your SSH key is set up first (`~/.ssh/authorized_keys`) or you'll lock yourself out!

### 3.3 FileVault Disk Encryption
- [ ] **System Settings → Privacy & Security → FileVault → Turn On**
- [ ] Save the recovery key somewhere safe (password manager, not on the Mac itself)

### 3.4 Automatic Updates
- [ ] **System Settings → General → Software Update → Automatic Updates → ON** (all toggles)

### 3.5 Reduce Attack Surface
```bash
# Disable guest account
sudo sysadminctl -guestAccount off

# Require password immediately after sleep/screen saver
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
```

---

## Phase 4: Clone the Repo and Adapt for Apple Silicon

### 4.1 Clone
```bash
mkdir -p ~/openclaw && cd ~/openclaw
git clone git@github.com:bmirabito/openclaw-hardened.git
cd openclaw-hardened
```

### 4.2 Key Dockerfile Changes for ARM64
The existing Dockerfile pulls x86_64 binaries. On Apple Silicon you need:

**AWS CLI** — change the download URL:
```
# FROM (x86_64):
# curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
# TO (ARM64):
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
```

**Everything else** (Node.js, Tailscale, Ubuntu base image) automatically provides ARM64 variants when building on Apple Silicon — no changes needed.

### 4.3 Docker Compose — TUN Device
macOS Docker Desktop doesn't expose `/dev/net/tun` the same way. Remove or conditionally handle:
```yaml
# Remove this block from docker-compose.yml:
# devices:
#   - /dev/net/tun:/dev/net/tun
```
Tailscale will run on the **host** Mac instead of inside each container. The containers reach the tailnet through the host's network. This is simpler and more reliable on macOS.

### 4.4 Resource Limits
With 3 instances sharing one Mac Mini, adjust the per-container limits in docker-compose.yml:
```yaml
deploy:
  resources:
    limits:
      memory: 1536M    # 1.5 GB each = 4.5 GB for 3 instances
      cpus: "1.5"      # adjust based on your Mac Mini's core count
      pids: 256
```
A Mac Mini M4 with 16 GB RAM can comfortably run 3 instances at these limits. If you have 24+ GB, you could bump memory to 2 GB each.

---

## Phase 5: Set Up Secrets

Your secrets are already in AWS Secrets Manager from the existing deployment. The Mac Mini just needs AWS CLI access to pull them.

### 5.1 Verify Access
```bash
# Test that you can read each instance's secrets
aws secretsmanager get-secret-value --secret-id "openclaw/jake/anthropic-api" --region us-east-2 --query 'SecretString' --output text
aws secretsmanager get-secret-value --secret-id "openclaw/clay/anthropic-api" --region us-east-2 --query 'SecretString' --output text
aws secretsmanager get-secret-value --secret-id "openclaw/reed/anthropic-api" --region us-east-2 --query 'SecretString' --output text
```

If any fail, check your IAM permissions. The Mac Mini's IAM user needs `secretsmanager:GetSecretValue` on `openclaw/*`.

### 5.2 Gateway Ports
Each instance needs a unique gateway port. Verify they're set differently in AWS Secrets Manager:
```
openclaw/jake/gateway-auth → {"token":"...","port":"18789"}
openclaw/clay/gateway-auth → {"token":"...","port":"18790"}
openclaw/reed/gateway-auth → {"token":"...","port":"18791"}
```

---

## Phase 6: Deploy the First Instance (Test Run)

Start with one instance to make sure everything works before migrating all three.

### 6.1 Deploy Jake
```bash
cd ~/openclaw/openclaw-hardened
bash scripts/deploy.sh jake us-east-2
```

### 6.2 Verify
```bash
# Check container is running
docker ps

# Follow logs
docker logs -f openclaw-jake

# Check health
curl -sf http://localhost:18789/health

# Run secrets audit
bash scripts/audit-secrets.sh jake
```

### 6.3 Test the Bot
Send a message to Jake's Telegram bot. Verify it responds. If it does, you're ready to migrate.

---

## Phase 7: Migrate Jake, Clay, and Reed

### 7.1 Migration Strategy

For each instance (jake, clay, reed), the process is:

1. **Export persistent data** from the cloud VPS
2. **Stop the cloud instance** (so no writes happen during migration)
3. **Transfer data** to the Mac Mini
4. **Start on Mac Mini**
5. **Verify** the bot works
6. **Decommission** the cloud VPS

### 7.2 Export Data from Cloud VPS

SSH into each cloud instance and tar up the persistent data:

```bash
# On the cloud VPS (e.g., ssh jake)
cd ~/openclaw-hardened
docker compose down
tar czf /tmp/openclaw-jake-data.tar.gz data/jake/
```

### 7.3 Transfer to Mac Mini

```bash
# From your Mac Mini (or local machine)
scp jake:/tmp/openclaw-jake-data.tar.gz /tmp/

# Extract into the Mac Mini's openclaw directory
cd ~/openclaw/openclaw-hardened
tar xzf /tmp/openclaw-jake-data.tar.gz
```

If both machines are on Tailscale, use Tailscale hostnames instead of IP addresses for the SCP.

### 7.4 Start on Mac Mini

```bash
cd ~/openclaw/openclaw-hardened
bash scripts/deploy.sh jake us-east-2
```

### 7.5 Repeat for Clay and Reed

```bash
# Clay
scp clay:/tmp/openclaw-clay-data.tar.gz /tmp/
cd ~/openclaw/openclaw-hardened && tar xzf /tmp/openclaw-clay-data.tar.gz
bash scripts/deploy.sh clay us-east-2

# Reed
scp reed:/tmp/openclaw-reed-data.tar.gz /tmp/
cd ~/openclaw/openclaw-hardened && tar xzf /tmp/openclaw-reed-data.tar.gz
bash scripts/deploy.sh reed us-east-2
```

### 7.6 Verify All Three
```bash
docker ps
# Should show: openclaw-jake, openclaw-clay, openclaw-reed

bash scripts/audit-secrets.sh jake
bash scripts/audit-secrets.sh clay
bash scripts/audit-secrets.sh reed
```

---

## Phase 8: Decommission Cloud VPS Instances

Only after you've verified all three bots are working on the Mac Mini:

- [ ] Stop the Docker containers on each cloud VPS
- [ ] Take a final backup of `/data/` from each VPS (just in case)
- [ ] Terminate/delete the cloud VPS instances
- [ ] Remove old Tailscale nodes from your tailnet (Tailscale admin console)
- [ ] Remove old SSH keys from `~/.ssh/known_hosts` and `authorized_keys`
- [ ] Remove DNS records pointing to old VPS IPs (if any)

---

## Phase 9: Ongoing Maintenance

### Auto-Start on Boot
Docker Desktop starts automatically (configured in Phase 2). Containers with `restart: unless-stopped` will restart when Docker starts. Your bots survive reboots.

### Monitoring
```bash
# Quick status of all instances
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check all logs
docker logs --tail 50 openclaw-jake
docker logs --tail 50 openclaw-clay
docker logs --tail 50 openclaw-reed
```

### Updates
```bash
cd ~/openclaw/openclaw-hardened

# Pull latest hardened config
git pull

# Rebuild and restart all instances
INSTANCE_NAME=jake AWS_REGION=us-east-2 docker compose up -d --build
INSTANCE_NAME=clay AWS_REGION=us-east-2 docker compose up -d --build
INSTANCE_NAME=reed AWS_REGION=us-east-2 docker compose up -d --build
```

### Secrets Audit
```bash
bash scripts/audit-all.sh jake:localhost clay:localhost reed:localhost
# Or just run individually:
bash scripts/audit-secrets.sh jake
```

### Backups
Set up a periodic backup of the data directory:
```bash
# Simple cron job — runs nightly at 2 AM
crontab -e
# Add:
0 2 * * * tar czf ~/backups/openclaw-$(date +\%Y\%m\%d).tar.gz -C ~/openclaw/openclaw-hardened data/
```

---

## Phase 10: Adding a New Agent in the Future

When you want to spin up a new bot instance (e.g., "nova"), the whole process takes about 10 minutes.

### 10.1 Pick a Name and Port

Choose a name (lowercase, no spaces) and the next available gateway port:

| Instance | Port |
|---|---|
| jake | 18789 |
| clay | 18790 |
| reed | 18791 |
| **nova** | **18792** |

### 10.2 Create a Telegram Bot

1. Open Telegram, message [@BotFather](https://t.me/BotFather)
2. Send `/newbot`
3. Choose a display name and username
4. Save the bot token — you'll need it in the next step

### 10.3 Create Secrets in AWS

```bash
bash scripts/setup-secrets.sh nova us-east-2
```

This creates placeholder secrets. Now fill in the real values:

```bash
# Anthropic API key (can reuse your existing key or create a new one)
aws secretsmanager put-secret-value \
  --secret-id "openclaw/nova/anthropic-api" \
  --secret-string '{"api_key":"sk-ant-YOUR_KEY_HERE"}' \
  --region us-east-2

# Telegram bot token (from BotFather)
aws secretsmanager put-secret-value \
  --secret-id "openclaw/nova/telegram-bot" \
  --secret-string '{"token":"YOUR_BOT_TOKEN_HERE"}' \
  --region us-east-2

# Gateway auth (generate a random token, pick the next port)
aws secretsmanager put-secret-value \
  --secret-id "openclaw/nova/gateway-auth" \
  --secret-string "{\"token\":\"$(openssl rand -hex 32)\",\"port\":\"18792\"}" \
  --region us-east-2
```

The shared secrets (Brave, ElevenLabs, Gemini, Tailscale) are already set up — every instance reads from the same `openclaw/shared/*` keys automatically.

### 10.4 Authorize Your Telegram User

Get your Telegram user ID (message [@userinfobot](https://t.me/userinfobot) if you don't have it) and set it as an environment variable when deploying. You can add it to docker-compose.yml or pass it inline:

```bash
export TELEGRAM_ALLOW_FROM="YOUR_TELEGRAM_USER_ID"
```

### 10.5 Deploy

```bash
cd ~/openclaw/openclaw-hardened
bash scripts/deploy.sh nova us-east-2
```

### 10.6 Verify

```bash
# Container running?
docker ps | grep nova

# Healthy?
curl -sf http://localhost:18792/health

# Logs look good?
docker logs -f openclaw-nova

# Secrets audit clean?
bash scripts/audit-secrets.sh nova
```

Send a test message to your new bot on Telegram. If it responds, you're done.

### 10.7 Update Your Instance List

Add the new instance to `~/.openclaw-instances` so audits cover it:

```bash
echo "nova:nova" >> ~/.openclaw-instances
```

Now `bash scripts/audit-all.sh` will include nova.

### 10.8 Capacity Check

Each instance uses up to 1.5 GB RAM and 1.5 CPU cores. Before adding an instance, check you have room:

```bash
# See current resource usage
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

| Mac Mini | RAM | Safe # of instances |
|---|---|---|
| 16 GB | ~10 GB usable for Docker | 5-6 instances |
| 24 GB | ~18 GB usable for Docker | 10+ instances |
| 32 GB+ | ~26 GB usable for Docker | 15+ instances |

If you're pushing limits, adjust the per-container memory/CPU in `docker-compose.yml`.

### Quick Checklist: New Agent

```
[ ] Name chosen, port assigned
[ ] Telegram bot created via BotFather
[ ] AWS secrets created (setup-secrets.sh) and filled with real values
[ ] Deployed (deploy.sh)
[ ] Health check passing
[ ] Telegram bot responds to messages
[ ] Secrets audit clean
[ ] Added to ~/.openclaw-instances
```

---

## Phase 11: Voice Conversations with ElevenLabs

Each agent can respond with voice messages in Telegram using ElevenLabs text-to-speech. The infrastructure is already wired up — the API key is already in AWS Secrets Manager at `openclaw/shared/elevenlabs-api`, shared across all instances. You just need to pick a voice per agent.

### 11.1 Verify the API Key

The ElevenLabs key should already be in AWS. Confirm it's there:

```bash
aws secretsmanager get-secret-value \
  --secret-id "openclaw/shared/elevenlabs-api" \
  --region us-east-2 \
  --query 'SecretString' --output text | jq -r '.api_key[:12]'
# Should print the first 12 chars of your key
```

**Pricing reference** (in case you need to upgrade your plan): the free tier gives ~10,000 characters/month. Starter ($5/month) gives 30,000. For three chatty bots, the Creator plan ($22/month) at 100,000 characters is a safer bet.

### 11.2 Choose a Voice for Each Agent

Browse voices at [elevenlabs.io/app/voice-library](https://elevenlabs.io/app/voice-library). Each voice has an ID (a string like `XA2bIQ92TabjGbpO2xRr`). You can find the ID by clicking a voice → **Use voice** → check the URL or API payload.

Pick distinct voices so your agents feel different:

| Agent | Voice Style | Voice ID |
|---|---|---|
| jake | (your choice) | `...` |
| clay | (your choice) | `...` |
| reed | (your choice) | `...` |

If you don't set a `VOICE_ID`, the default is `XA2bIQ92TabjGbpO2xRr`.

### 11.3 Deploy with Per-Agent Voices

Each instance reads `VOICE_ID` from its environment. Pass it at deploy time:

```bash
# Deploy each with its own voice
VOICE_ID="voice_id_for_jake" bash scripts/deploy.sh jake us-east-2
VOICE_ID="voice_id_for_clay" bash scripts/deploy.sh clay us-east-2
VOICE_ID="voice_id_for_reed" bash scripts/deploy.sh reed us-east-2
```

Or set them directly in `docker-compose.yml` if you prefer a persistent config:

```yaml
environment:
  - VOICE_ID=voice_id_for_this_instance
```

### 11.4 How It Works Under the Hood

When `ELEVENLABS_API_KEY` is present at startup, `entrypoint.sh` injects a `"talk"` block into the runtime config:

```json
"talk": {
  "voiceId": "<your VOICE_ID>",
  "modelId": "eleven_v3",
  "interruptOnSpeech": true
}
```

When the key is **absent**, voice is disabled automatically:
```json
"talk": { "enabled": false }
```

So removing the API key from AWS is all you need to do to turn voice off.

### 11.5 Test Voice Output

1. Deploy an instance with a valid ElevenLabs key and voice ID
2. Open Telegram, send a voice message to the bot (hold the mic button and speak)
3. The bot should reply with a voice message (audio file) instead of or alongside text
4. If you only get text replies, check:
   ```bash
   # Is the API key loaded?
   docker exec openclaw-jake env | grep ELEVENLABS
   # Should print ELEVENLABS_API_KEY=sk-... (non-empty)

   # Check the runtime config
   docker exec openclaw-jake cat /tmp/secrets/openclaw.json | jq '.talk'
   # Should show voiceId, modelId, interruptOnSpeech
   ```

### 11.6 Disable Voice for a Specific Agent

If you want some agents text-only while others use voice, deploy without `VOICE_ID` and without the ElevenLabs key for that instance. The simplest approach: remove the shared secret reference for that container. But since the key is shared, the easier method is to override the talk config.

Set `VOICE_ID` to empty:
```bash
VOICE_ID="" bash scripts/deploy.sh reed us-east-2
```

The entrypoint will still inject the `"talk"` block, but with an empty voice ID, which effectively disables speech synthesis.

### 11.7 Cost & Usage Monitoring

ElevenLabs bills by character count. Monitor usage at [elevenlabs.io/app/usage](https://elevenlabs.io/app/usage).

**Rough estimates:**
| Activity | Characters/day | Monthly cost (Creator plan) |
|---|---|---|
| Light use (10-20 voice replies/day) | ~2,000 | Well within 100k limit |
| Moderate (50-100 replies/day) | ~10,000 | ~30% of limit |
| Heavy (200+ replies/day across 3 bots) | ~40,000+ | May need Scale plan |

Set a usage alert in ElevenLabs settings to avoid surprise overages.

### Quick Checklist: Voice Setup

```
[x] ElevenLabs API key in AWS (openclaw/shared/elevenlabs-api)
[ ] Voice IDs chosen for each agent
[ ] Deployed with VOICE_ID set per instance
[ ] Voice replies working in Telegram
[ ] Usage alerts configured in ElevenLabs dashboard
```

---

## Phase 12: Real-Time Voice Calls (Phone + Web Widget)

Telegram voice notes are async — you record, send, wait. For a true call-like experience where you speak and hear the agent respond in real time, use **ElevenLabs Conversational AI**. This is a separate product from the TTS API used in Phase 11 — it handles full-duplex voice: speech recognition, LLM processing, and speech synthesis in a single streaming pipeline with ~1-2s latency.

You'll create one ElevenLabs Conversational AI agent per bot, then connect each agent to both a phone number (primary) and a web widget (convenience).

### 12.1 Create Conversational AI Agents

Do this once per bot (jake, clay, reed) in the ElevenLabs dashboard:

1. Go to [ElevenLabs Agents](https://elevenlabs.io/app/conversational-ai)
2. Click **Create Agent**
3. Configure each agent:

| Setting | Value |
|---|---|
| **Name** | jake (or clay, reed) |
| **LLM** | Claude — select your preferred model (Sonnet for low latency, Opus for deeper reasoning) |
| **Anthropic API Key** | Paste the same key from `openclaw/<instance>/anthropic-api` |
| **Voice** | Pick the same voice ID you chose in Phase 11 for consistency |
| **System Prompt** | Copy the agent's personality/instructions from your OpenClaw config |
| **First Message** | e.g., "Hey, what's up?" (what the agent says when the call connects) |

4. Save the agent. Note the **Agent ID** (visible in the URL or agent settings).

Repeat for each bot — you'll end up with three agents, each with its own personality and voice.

### 12.2 Set Up Phone Numbers (via Twilio)

ElevenLabs uses Twilio for phone integration. You need a Twilio account with phone numbers.

**Create a Twilio account** (if you don't have one):
1. Sign up at [twilio.com](https://www.twilio.com)
2. Buy a phone number ($1.00-1.50/month per number) — one per agent
3. Note your **Account SID** and **Auth Token** from the Twilio console

**Connect Twilio to ElevenLabs:**
1. In the ElevenLabs dashboard, go to **Conversational AI → Phone Numbers**
2. Click **Add Phone Number**
3. Enter:
   - **Label**: jake-phone (or clay-phone, reed-phone)
   - **Phone Number**: your Twilio number
   - **Twilio Account SID**: from Twilio console
   - **Twilio Auth Token**: from Twilio console
4. **Assign Agent**: select the matching agent (jake, clay, or reed)
5. ElevenLabs automatically configures the Twilio webhook routing

**Test it:** Call the phone number from your cell phone. The agent should answer and start talking.

| Agent | Twilio Number | ElevenLabs Agent ID |
|---|---|---|
| jake | +1 (xxx) xxx-xxxx | `...` |
| clay | +1 (xxx) xxx-xxxx | `...` |
| reed | +1 (xxx) xxx-xxxx | `...` |

### 12.3 Set Up Web Widget

Each agent gets an embeddable widget you can open in a browser — no server needed.

**Get the embed code** from the ElevenLabs dashboard:
1. Open the agent → **Widget** tab
2. Copy the embed snippet

The snippet looks like this:
```html
<script src="https://unpkg.com/@11labs/client@latest/dist/convai-widget.js"></script>
<elevenlabs-convai agent-id="YOUR_AGENT_ID"></elevenlabs-convai>
```

**Create a simple local HTML page** for quick access:

```bash
mkdir -p ~/openclaw/voice-widgets
```

Create one HTML file per agent (example for jake):

```html
<!DOCTYPE html>
<html>
<head><title>Talk to Jake</title></head>
<body style="display:flex; justify-content:center; align-items:center;
             height:100vh; background:#111; color:#fff; font-family:sans-serif;">
  <div style="text-align:center;">
    <h1>Jake</h1>
    <p>Click the mic button to start talking</p>
    <elevenlabs-convai agent-id="JAKE_AGENT_ID"></elevenlabs-convai>
  </div>
  <script src="https://unpkg.com/@11labs/client@latest/dist/convai-widget.js"></script>
</body>
</html>
```

**Open it locally:**
```bash
open ~/openclaw/voice-widgets/jake.html    # macOS
# or
xdg-open ~/openclaw/voice-widgets/jake.html  # Linux
```

No web server required — the widget connects directly to ElevenLabs from the browser.

**Optional: host all three on a single page:**
```html
<!-- All agents on one page with tabs or side-by-side -->
<elevenlabs-convai agent-id="JAKE_AGENT_ID"></elevenlabs-convai>
<elevenlabs-convai agent-id="CLAY_AGENT_ID"></elevenlabs-convai>
<elevenlabs-convai agent-id="REED_AGENT_ID"></elevenlabs-convai>
```

### 12.4 Outbound Calls (Agent Calls You)

The same Twilio numbers support outbound — the agent dials you instead of you dialing it.

**On-demand (call me now):**

```bash
# Have jake call your cell phone right now
curl -X POST "https://api.elevenlabs.io/v1/convai/twilio/outbound-call" \
  -H "xi-api-key: $(aws secretsmanager get-secret-value \
        --secret-id openclaw/shared/elevenlabs-api \
        --region us-east-2 --query SecretString --output text | jq -r .api_key)" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "JAKE_AGENT_ID",
    "agent_phone_number_id": "JAKE_PHONE_NUMBER_ID",
    "to_number": "+1YOURCELLNUMBER"
  }'
```

Your phone rings, you pick up, you're talking to jake.

You can find `agent_phone_number_id` in the ElevenLabs dashboard under **Conversational AI → Phone Numbers**, or via the API:
```bash
curl -s "https://api.elevenlabs.io/v1/convai/phone-numbers" \
  -H "xi-api-key: YOUR_ELEVENLABS_KEY" | jq '.[] | {label, phone_number_id}'
```

**Wrap it in a shell script** for quick use:

```bash
#!/usr/bin/env bash
# ~/openclaw/call-agent.sh — usage: ./call-agent.sh jake
set -euo pipefail

ELEVENLABS_KEY="$(aws secretsmanager get-secret-value \
  --secret-id openclaw/shared/elevenlabs-api \
  --region us-east-2 --query SecretString --output text | jq -r .api_key)"

MY_NUMBER="+1YOURCELLNUMBER"

# Map agent names to their IDs (fill these in after setup)
declare -A AGENTS=(
  [jake]="JAKE_AGENT_ID:JAKE_PHONE_NUMBER_ID"
  [clay]="CLAY_AGENT_ID:CLAY_PHONE_NUMBER_ID"
  [reed]="REED_AGENT_ID:REED_PHONE_NUMBER_ID"
)

AGENT="${1:?Usage: $0 <jake|clay|reed>}"
AGENT_ID="${AGENTS[$AGENT]%%:*}"
PHONE_ID="${AGENTS[$AGENT]##*:}"

curl -s -X POST "https://api.elevenlabs.io/v1/convai/twilio/outbound-call" \
  -H "xi-api-key: $ELEVENLABS_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"agent_id\": \"$AGENT_ID\",
    \"agent_phone_number_id\": \"$PHONE_ID\",
    \"to_number\": \"$MY_NUMBER\"
  }"

echo "Calling you from $AGENT..."
```

Then just:
```bash
chmod +x ~/openclaw/call-agent.sh
~/openclaw/call-agent.sh jake
```

### 12.5 Scheduled Calls (Morning Briefing, etc.)

Use cron on the Mac Mini to have an agent call you on a schedule:

```bash
crontab -e
```

Example — jake calls you every weekday morning at 8 AM:
```
0 8 * * 1-5 /Users/YOUR_USERNAME/openclaw/call-agent.sh jake >> /tmp/openclaw-calls.log 2>&1
```

Example — reed calls you every Sunday evening at 7 PM for a weekly review:
```
0 19 * * 0 /Users/YOUR_USERNAME/openclaw/call-agent.sh reed >> /tmp/openclaw-calls.log 2>&1
```

The agent's **first message** (configured in 12.1) sets the tone — for a morning briefing you might set it to something like *"Good morning — here's what's on your plate today."*

You can create different ElevenLabs agents with different first messages and system prompts for different call types (e.g., a "jake-briefing" agent vs. the normal "jake" agent).

### 12.6 Security Considerations

The Conversational AI agents run on ElevenLabs' infrastructure, not your Mac Mini. Keep in mind:

- **API keys**: Your Anthropic key is stored in ElevenLabs' platform (encrypted). This is a separate copy from the one in AWS Secrets Manager.
- **Agent access**: By default, agents are private — only accessible via your widget or phone number. You can restrict the widget to specific domains if you host it publicly.
- **Phone numbers**: Anyone who has the number can call the agent. Keep numbers private or implement a greeting PIN if needed.
- **Conversations**: ElevenLabs stores call logs and transcripts. Review their data retention policies and enable **Zero Retention** mode if desired (available on higher-tier plans).

### 12.7 Cost Breakdown

| Component | Cost | Notes |
|---|---|---|
| **Twilio phone numbers** | ~$1.15/month per number | 3 numbers = ~$3.45/month |
| **Twilio inbound minutes** | ~$0.02/min | You call the agent |
| **Twilio outbound minutes** | ~$0.04/min | Agent calls you |
| **ElevenLabs Conversational AI** | Included in your ElevenLabs plan | Uses your monthly credit allotment |
| **Anthropic API** | Per-token pricing | Same as your existing usage |

ElevenLabs Conversational AI minutes consume credits faster than plain TTS because they include STT + TTS + orchestration. Monitor at [elevenlabs.io/app/usage](https://elevenlabs.io/app/usage).

### 12.8 How Everything Fits Together

```
You call agent   ──→  Twilio  ──→  ElevenLabs Conversational AI  ──→  Claude  ──→  voice back to you
Agent calls you  ──→  ElevenLabs API  ──→  Twilio  ──→  your phone rings  ──→  real-time conversation
Web widget       ──→  Browser WebSocket  ──→  ElevenLabs Conversational AI  ──→  Claude  ──→  voice back to you
Telegram         ──→  Telegram  ──→  OpenClaw container (Mac Mini)  ──→  Claude  ──→  ElevenLabs TTS  ──→  voice note back
Scheduled call   ──→  cron on Mac Mini  ──→  ElevenLabs API  ──→  Twilio  ──→  your phone rings at 8 AM
```

- **Phone (inbound & outbound) + widget**: real-time, ~1-2s latency, runs on ElevenLabs infrastructure
- **Telegram**: async voice notes, runs on your Mac Mini
- **Scheduled calls**: triggered by cron, same real-time experience once you pick up
- All channels use the same Claude models and can share the same voice per agent

### Quick Checklist: Real-Time Voice Calls

```
[ ] ElevenLabs Conversational AI agent created for each bot
[ ] System prompts match each agent's personality
[ ] Twilio account created, 3 phone numbers purchased
[ ] Phone numbers connected to ElevenLabs and assigned to agents
[ ] Inbound calls tested — agents answer and converse
[ ] Outbound calls tested — call-agent.sh rings your phone
[ ] Scheduled calls configured via cron (if desired)
[ ] Web widget HTML pages created for each agent
[ ] Widget tested — mic works, agent responds in real time
[ ] Usage alerts set for both ElevenLabs and Twilio
```

---

## Phase 13: Demo Prep (Client / PE Presentations)

A live demo where someone dials a number and talks to your AI agent in real time is worth more than any deck. This phase covers setting up a clean, reliable demo environment and a rehearsal plan so nothing goes wrong in the room.

### 13.1 Create Dedicated Demo Agents

Don't demo with your production agents — create purpose-built ones on ElevenLabs with polished system prompts and first messages.

**Suggested demo agents:**

| Demo Agent | Persona | Use Case to Demonstrate |
|---|---|---|
| **demo-ops** | Operations analyst | "Call this number and ask about last quarter's shipping delays" |
| **demo-finance** | Financial controller | "Ask it to walk you through the monthly close process" |
| **demo-customer** | Customer service rep | "Pretend you're a customer with a billing question" |

For each, create an ElevenLabs Conversational AI agent (same process as 12.1) with:

- A **professional, clear voice** — avoid novelty voices. ElevenLabs "Rachel" or "Josh" work well for business settings.
- A **system prompt tailored to the demo scenario** — include realistic sample data (fake company name, fake KPIs) so the agent sounds knowledgeable.
- A **first message** that sets context immediately: *"Hi, I'm your operations analyst. I have last quarter's logistics data ready — what would you like to dig into?"*

Connect each to a dedicated Twilio number (12.2) and create a web widget page (12.3).

### 13.2 Build a Demo Landing Page

Create a single polished HTML page with all demo agents accessible via web widget. This is what you'll pull up on a laptop or share on a screen during the meeting.

```html
<!DOCTYPE html>
<html>
<head>
  <title>AI Agent Demo</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, system-ui, sans-serif;
           background: #0a0a0a; color: #e0e0e0; }
    .header { padding: 40px 20px; text-align: center; }
    .header h1 { font-size: 2rem; font-weight: 300; margin-bottom: 8px; }
    .header p { color: #888; font-size: 1rem; }
    .agents { display: flex; justify-content: center; gap: 40px;
              flex-wrap: wrap; padding: 20px; }
    .agent-card { background: #1a1a1a; border-radius: 16px;
                  padding: 32px; width: 300px; text-align: center;
                  border: 1px solid #333; }
    .agent-card h2 { font-size: 1.2rem; margin-bottom: 4px; }
    .agent-card .role { color: #888; font-size: 0.9rem; margin-bottom: 16px; }
    .agent-card .phone { font-family: monospace; color: #4a9eff;
                         font-size: 1.1rem; margin-bottom: 20px; }
    .footer { text-align: center; padding: 40px; color: #555;
              font-size: 0.85rem; }
  </style>
</head>
<body>
  <div class="header">
    <h1>AI Voice Agents</h1>
    <p>Click a mic button below or dial the phone number to start a live conversation</p>
  </div>
  <div class="agents">
    <div class="agent-card">
      <h2>Operations Analyst</h2>
      <p class="role">Logistics &amp; supply chain</p>
      <p class="phone">+1 (xxx) xxx-xxxx</p>
      <elevenlabs-convai agent-id="DEMO_OPS_AGENT_ID"></elevenlabs-convai>
    </div>
    <div class="agent-card">
      <h2>Financial Controller</h2>
      <p class="role">Monthly close &amp; reporting</p>
      <p class="phone">+1 (xxx) xxx-xxxx</p>
      <elevenlabs-convai agent-id="DEMO_FINANCE_AGENT_ID"></elevenlabs-convai>
    </div>
    <div class="agent-card">
      <h2>Customer Service</h2>
      <p class="role">Billing &amp; account support</p>
      <p class="phone">+1 (xxx) xxx-xxxx</p>
      <elevenlabs-convai agent-id="DEMO_CUSTOMER_AGENT_ID"></elevenlabs-convai>
    </div>
  </div>
  <div class="footer">
    Powered by Claude &middot; ElevenLabs &middot; Self-hosted on hardened infrastructure
  </div>
  <script src="https://unpkg.com/@11labs/client@latest/dist/convai-widget.js"></script>
</body>
</html>
```

Save as `~/openclaw/voice-widgets/demo.html` and open locally, or host on a simple static site if sharing a URL.

### 13.3 Demo Script (What to Show, in What Order)

**Opening (2 min):** Frame the problem. Legacy systems, manual processes, high headcount on repetitive tasks. Don't mention AI yet.

**Live call (5 min):** This is the centerpiece.
1. Hand the prospect a phone number on a card or show it on screen
2. Let *them* call it — not you. Having them initiate builds trust.
3. Let them ask whatever they want. A well-prompted agent handles open-ended questions gracefully.
4. If they hesitate, suggest: *"Ask it about last month's shipping exceptions"* or *"Ask it to explain the variance on line 42"*

**Show the widget (2 min):** Pull up the demo page on your laptop. Click the mic. Show it works from a browser too — no app install, no special hardware.

**Architecture walkthrough (3 min):** Show the diagram from Phase 12.8. Key points:
- "This runs on a Mac Mini under a desk — not a $50k cloud deployment"
- "Secrets never touch disk — they're in AWS Secrets Manager, loaded into RAM at boot"
- "Each agent is isolated in its own container with a read-only filesystem"
- "We can spin up a new agent in 10 minutes" (reference Phase 10)

**Scheduled call demo (2 min):** Explain the morning briefing concept. *"Imagine every portfolio company CEO gets a call at 8 AM with yesterday's KPIs, generated from their actual data systems."* If you want maximum impact, have the agent call the prospect's phone during the meeting (set up ahead of time with their number).

**Close (1 min):** "This took us [X] weeks to build and harden. We can deploy this for your portfolio in [timeframe]."

### 13.4 Talking Points for PE Audiences

**Cost story:**
- Infrastructure: Mac Mini ($600 one-time) + ~$30/month all-in (Twilio + ElevenLabs + API)
- Compare to: a single full-time analyst ($80-120k/year)
- "This isn't replacing people — it's giving your existing team a 24/7 analyst that never sleeps"

**Security story:**
- No data on third-party servers (self-hosted containers)
- Secrets in AWS Secrets Manager, never written to disk
- Read-only filesystems, non-root processes, PID limits
- Audit scripts that verify no secrets have leaked

**Scale story:**
- One Mac Mini runs 5-6 agents comfortably
- Adding a new agent is a 10-minute process
- Each portfolio company can have its own dedicated agent with its own personality, data, and phone number

**Moat story:**
- "Anyone can call an API. The value is in the hardened deployment, the operational playbook, and the domain-specific prompts tuned to your portfolio's actual workflows."

### 13.5 Pre-Demo Rehearsal Checklist

Run through this 30 minutes before every demo:

```
[ ] Laptop charged, audio working (test mic + speakers)
[ ] Demo page loads — all three widget mic buttons visible
[ ] Phone number 1 — call it, agent answers, conversation works
[ ] Phone number 2 — call it, agent answers
[ ] Phone number 3 — call it, agent answers
[ ] Outbound call works — agent calls your phone
[ ] Wi-Fi / cell signal confirmed at demo venue
[ ] Backup: mobile hotspot ready in case venue Wi-Fi is unreliable
[ ] ElevenLabs usage well below plan limit (check dashboard)
[ ] Twilio balance has enough credit for the demo
[ ] Demo agents have realistic, up-to-date sample data in their prompts
[ ] Printed card with phone numbers (in case screen sharing fails)
```

### 13.6 Fallback Plan

Things that can go wrong and what to do:

| Problem | Fallback |
|---|---|
| Venue Wi-Fi blocks WebSocket | Use mobile hotspot, or fall back to phone call (doesn't need browser) |
| ElevenLabs is down | Show a pre-recorded video of a call (record one during rehearsal) |
| Prospect's phone can't receive Twilio calls (some corporate phones block unknown numbers) | Use the web widget instead |
| Agent gives a bad answer | "That's actually a great example of why prompt tuning matters — let me show you how we'd refine that in 30 seconds" (open the ElevenLabs dashboard and tweak the prompt live) |
| Latency feels slow | "We're using Opus for deeper reasoning here — in production we can tune the model/latency tradeoff per use case" |

### Quick Checklist: Demo Environment

```
[ ] Demo agents created with polished prompts and voices
[ ] Demo phone numbers purchased and assigned
[ ] Demo landing page built and tested
[ ] Demo script rehearsed end-to-end
[ ] Pre-recorded fallback video captured
[ ] Phone number cards printed
[ ] Talking points reviewed for target audience
```

---

## Phase 14: Monitoring Dashboard

### 14.1 Portainer (Container Dashboard)

Portainer CE is a free, single-container web UI for monitoring and managing Docker. It shows live CPU/memory/network graphs, container health, restart counts, and logs — all from a browser.

**Deploy it:**
```bash
docker volume create portainer_data

docker run -d \
  --name portainer \
  --restart unless-stopped \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

**Access it:**
```
https://localhost:9443
```

On first visit, create an admin account. Then you'll see all your containers (openclaw-jake, openclaw-clay, openclaw-reed) with:

- **Live stats** — CPU %, memory usage/limit, network I/O per container
- **Health status** — green/red based on your healthcheck in docker-compose.yml
- **Logs** — click any container to tail its logs in the browser
- **Restart counts** — spot containers that are crash-looping
- **Container shell** — exec into a container without SSH if needed

Portainer uses ~30 MB of RAM. Negligible overhead.

**Restrict access to Tailscale only** (recommended — don't expose on the public network):
```bash
docker run -d \
  --name portainer \
  --restart unless-stopped \
  -p 127.0.0.1:9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

Then access via Tailscale IP: `https://<mac-mini-tailscale-ip>:9443`

### 14.2 Quick Status Script

For a terminal-based check when you don't want to open a browser:

```bash
#!/usr/bin/env bash
# ~/openclaw/status.sh — one-line status of all instances
set -euo pipefail

echo "=== Container Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
  | grep -E "openclaw|NAMES"

echo ""
echo "=== Resource Usage ==="
docker stats --no-stream \
  --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" \
  | grep -E "openclaw|NAME"

echo ""
echo "=== Health Checks ==="
for c in $(docker ps --format '{{.Names}}' | grep openclaw); do
  health=$(docker inspect --format='{{.State.Health.Status}}' "$c" 2>/dev/null || echo "no healthcheck")
  restarts=$(docker inspect --format='{{.RestartCount}}' "$c")
  oom=$(docker inspect --format='{{.State.OOMKilled}}' "$c")
  printf "  %-20s health=%-10s restarts=%-3s oom=%s\n" "$c" "$health" "$restarts" "$oom"
done
```

```bash
chmod +x ~/openclaw/status.sh
~/openclaw/status.sh
```

Sample output:
```
=== Container Status ===
NAMES              STATUS                  PORTS
openclaw-jake      Up 3 days (healthy)     0.0.0.0:18789->18789/tcp
openclaw-clay      Up 3 days (healthy)     0.0.0.0:18790->18790/tcp
openclaw-reed      Up 3 days (healthy)     0.0.0.0:18791->18791/tcp

=== Resource Usage ===
NAME               CPU %   MEM USAGE / LIMIT   MEM %   NET I/O
openclaw-jake      2.31%   487MiB / 1.5GiB     31.7%   12.3MB / 8.1MB
openclaw-clay      1.89%   412MiB / 1.5GiB     26.8%   9.8MB / 6.2MB
openclaw-reed      3.02%   531MiB / 1.5GiB     34.6%   15.1MB / 11.3MB

=== Health Checks ===
  openclaw-jake        health=healthy   restarts=0   oom=false
  openclaw-clay        health=healthy   restarts=0   oom=false
  openclaw-reed        health=healthy   restarts=0   oom=false
```

### 14.3 Alerts (Cron-Based)

Get notified when something goes wrong. This script checks all containers and sends an alert via Telegram (using one of your bots) if any are unhealthy:

```bash
#!/usr/bin/env bash
# ~/openclaw/health-alert.sh — alert on unhealthy containers
set -euo pipefail

ALERT_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
ALERT_CHAT_ID="YOUR_TELEGRAM_CHAT_ID"

problems=""

for c in $(docker ps -a --format '{{.Names}}' | grep openclaw); do
  status=$(docker inspect --format='{{.State.Status}}' "$c")
  health=$(docker inspect --format='{{.State.Health.Status}}' "$c" 2>/dev/null || echo "unknown")
  oom=$(docker inspect --format='{{.State.OOMKilled}}' "$c")
  restarts=$(docker inspect --format='{{.RestartCount}}' "$c")

  if [ "$status" != "running" ] || [ "$health" = "unhealthy" ] || [ "$oom" = "true" ]; then
    problems+="$c: status=$status health=$health oom=$oom restarts=$restarts\n"
  fi
done

if [ -n "$problems" ]; then
  message="⚠️ OpenClaw Alert\n\n${problems}"
  curl -s -X POST "https://api.telegram.org/bot${ALERT_BOT_TOKEN}/sendMessage" \
    -d chat_id="$ALERT_CHAT_ID" \
    -d text="$(echo -e "$message")" \
    -d parse_mode="HTML" > /dev/null
fi
```

Run every 5 minutes via cron:
```bash
crontab -e
# Add:
*/5 * * * * /Users/YOUR_USERNAME/openclaw/health-alert.sh >> /tmp/openclaw-alerts.log 2>&1
```

You'll get a Telegram message if any container is down, unhealthy, or OOM-killed. No news is good news.

### 14.4 External Dashboards

Container metrics are only half the picture. Bookmark these for the service-level view:

| What | Where | What to watch |
|---|---|---|
| **ElevenLabs usage** | [elevenlabs.io/app/usage](https://elevenlabs.io/app/usage) | Character/credit consumption, approaching plan limits |
| **ElevenLabs call history** | [elevenlabs.io/app/conversational-ai](https://elevenlabs.io/app/conversational-ai) → Calls | Call duration, transcript quality, failed calls |
| **Twilio usage** | [console.twilio.com](https://console.twilio.com) → Usage | Call minutes, spend, failed deliveries |
| **Anthropic API** | [console.anthropic.com/usage](https://console.anthropic.com/usage) | Token usage, spend per model, rate limit hits |
| **AWS Secrets Manager** | [AWS Console → Secrets Manager](https://console.aws.amazon.com/secretsmanager) | Secret access logs (via CloudTrail), rotation status |

### 14.5 Optional: Grafana + Prometheus (Historical Metrics)

If you want historical graphs (CPU over the last 30 days, memory trends, etc.), add Prometheus + cAdvisor + Grafana. This is heavier (~300 MB RAM total) but gives you time-series dashboards.

Only set this up if you find Portainer's live-only view insufficient. The stack:

```yaml
# Add to a separate monitoring docker-compose.yml
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "127.0.0.1:9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana

volumes:
  prometheus_data:
  grafana_data:
```

Grafana has a pre-built Docker dashboard (ID: 193) that works out of the box with cAdvisor. Import it after setup.

For most use cases, **Portainer + the status script + cron alerts is more than enough**.

### Quick Checklist: Monitoring

```
[ ] Portainer deployed and accessible
[ ] Admin account created
[ ] All openclaw containers visible with live stats
[ ] Portainer bound to localhost or Tailscale only (not public)
[ ] status.sh script created and working
[ ] health-alert.sh configured with Telegram bot token
[ ] Alert cron job running every 5 minutes
[ ] External dashboards bookmarked (ElevenLabs, Twilio, Anthropic)
```

---

## Quick Reference: What Changes vs. Cloud VPS

| Component | Cloud VPS (Ubuntu) | Mac Mini (macOS) |
|---|---|---|
| Docker | Docker Engine (apt) | Docker Desktop (brew cask) |
| Firewall | UFW | macOS Application Firewall |
| SSH hardening | `/etc/ssh/sshd_config` | `/etc/ssh/sshd_config.d/hardened.conf` |
| Fail2ban | Yes | Not available (macOS SSH + firewall sufficient) |
| Unattended upgrades | `apt unattended-upgrades` | macOS auto-update |
| Tailscale | Inside each container | On the host Mac |
| TUN device | `/dev/net/tun` passthrough | Not needed (host Tailscale) |
| AWS CLI | x86_64 binary | aarch64 (Apple Silicon) |
| Disk encryption | LUKS (optional) | FileVault |
| Auto-start | systemd + Docker restart policy | Docker Desktop auto-start + restart policy |
| User | `ubuntu` | Your macOS username |
