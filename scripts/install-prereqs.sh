#!/bin/bash
# =============================================================================
# OpenClaw Prerequisites Installation
#
# Installs Docker Engine, Docker Compose v2, and AWS CLI v2 on Ubuntu 24.04.
# Must be run as root or with sudo.
#
# Usage: sudo bash install-prereqs.sh
# =============================================================================
set -euo pipefail

echo "=== OpenClaw Prerequisites Installation ==="
echo ""

# ---------------------------------------------------------------------------
# 1. System updates
# ---------------------------------------------------------------------------
echo "[1/4] Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# ---------------------------------------------------------------------------
# 2. Install Docker Engine
# ---------------------------------------------------------------------------
if command -v docker &>/dev/null; then
  echo "[2/4] Docker already installed: $(docker --version)"
else
  echo "[2/4] Installing Docker Engine..."

  # Install dependencies
  apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

  # Add Docker's official GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # Add Docker repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources-list.d/docker.list

  apt-get update -qq
  apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  # Add ubuntu user to docker group
  usermod -aG docker ubuntu 2>/dev/null || true

  echo "Docker installed: $(docker --version)"
fi

# ---------------------------------------------------------------------------
# 3. Install AWS CLI v2
# ---------------------------------------------------------------------------
if command -v aws &>/dev/null; then
  echo "[3/4] AWS CLI already installed: $(aws --version 2>&1 | head -1)"
else
  echo "[3/4] Installing AWS CLI v2..."

  apt-get install -y -qq unzip curl

  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
  rm -rf /tmp/aws /tmp/awscliv2.zip

  echo "AWS CLI installed: $(aws --version 2>&1 | head -1)"
fi

# ---------------------------------------------------------------------------
# 4. Install Tailscale
# ---------------------------------------------------------------------------
if command -v tailscale &>/dev/null; then
  echo "[4/4] Tailscale already installed: $(tailscale version | head -1)"
else
  echo "[4/4] Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  echo "Tailscale installed: $(tailscale version | head -1)"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=== Prerequisites installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Log out and back in (for docker group membership)"
echo "  2. Configure AWS credentials:  aws configure"
echo "  3. Connect to Tailscale:        sudo tailscale up"
echo "  4. Harden the host:             sudo bash scripts/harden-host.sh ubuntu"
echo "  5. Set up secrets:              bash scripts/setup-secrets.sh <name> <region>"
echo "  6. Deploy:                      bash scripts/deploy.sh <name> <region>"
