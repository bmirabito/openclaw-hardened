#!/bin/bash
# =============================================================================
# OpenClaw Host Hardening Script
#
# Run this on a fresh Ubuntu 24.04 instance before deploying the Docker container.
# Must be run as root or with sudo.
#
# Usage: sudo bash harden-host.sh [ALLOWED_SSH_USER]
# =============================================================================
set -euo pipefail

SSH_USER="${1:-ubuntu}"

echo "=== OpenClaw Host Hardening ==="
echo "SSH user: ${SSH_USER}"
echo ""

# ---------------------------------------------------------------------------
# 1. System updates
# ---------------------------------------------------------------------------
echo "[1/6] Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# ---------------------------------------------------------------------------
# 2. Install security packages
# ---------------------------------------------------------------------------
echo "[2/6] Installing security packages..."
apt-get install -y -qq \
  ufw \
  fail2ban \
  unattended-upgrades \
  apt-listchanges

# ---------------------------------------------------------------------------
# 3. Configure UFW firewall
# ---------------------------------------------------------------------------
echo "[3/6] Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# SSH from anywhere
ufw allow 22/tcp

# Allow all traffic on Tailscale interface
ufw allow in on tailscale0

# Syncthing (Tailscale only)
ufw allow in on tailscale0 to any port 22000 proto tcp comment 'Syncthing TCP'
ufw allow in on tailscale0 to any port 22000 proto udp comment 'Syncthing QUIC'

ufw --force enable
echo "UFW configured."

# ---------------------------------------------------------------------------
# 4. Harden SSH
# ---------------------------------------------------------------------------
echo "[4/6] Hardening SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"

# Backup original
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d)"

# Apply hardened settings (idempotent — removes old values first)
declare -A SSH_SETTINGS=(
  ["PermitRootLogin"]="no"
  ["PasswordAuthentication"]="no"
  ["KbdInteractiveAuthentication"]="no"
  ["PubkeyAuthentication"]="yes"
  ["MaxAuthTries"]="3"
  ["AllowUsers"]="$SSH_USER"
  ["ClientAliveInterval"]="300"
  ["ClientAliveCountMax"]="2"
  ["X11Forwarding"]="yes"
)

for key in "${!SSH_SETTINGS[@]}"; do
  value="${SSH_SETTINGS[$key]}"
  # Remove any existing lines for this key (commented or not)
  sed -i "/^#\?${key}\s/d" "$SSHD_CONFIG"
  # Append the hardened value
  echo "${key} ${value}" >> "$SSHD_CONFIG"
done

systemctl restart sshd
echo "SSH hardened."

# ---------------------------------------------------------------------------
# 5. Configure Fail2ban
# ---------------------------------------------------------------------------
echo "[5/6] Configuring Fail2ban..."

cat > /etc/fail2ban/jail.local <<'JAIL'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
JAIL

cat > /etc/fail2ban/jail.d/defaults-debian.conf <<'DEFAULTS'
[DEFAULT]
banaction = nftables
banaction_allports = nftables[type=allports]
backend = systemd

[sshd]
enabled = true
DEFAULTS

systemctl enable fail2ban
systemctl restart fail2ban
echo "Fail2ban configured."

# ---------------------------------------------------------------------------
# 6. Enable unattended security upgrades
# ---------------------------------------------------------------------------
echo "[6/6] Enabling unattended security upgrades..."

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTOUPGRADE'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
AUTOUPGRADE

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades
echo "Unattended upgrades enabled."

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=== Host hardening complete ==="
echo ""
echo "Summary:"
echo "  - UFW: deny incoming, allow SSH + Tailscale + Syncthing"
echo "  - SSH: pubkey-only, no root, max 3 retries, AllowUsers=${SSH_USER}"
echo "  - Fail2ban: SSH jail, 3 retries / 10min window / 1hr ban"
echo "  - Unattended upgrades: security patches auto-installed"
echo ""
echo "Next: deploy the Docker container with docker compose up -d --build"
