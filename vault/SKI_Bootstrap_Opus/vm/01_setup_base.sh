#!/usr/bin/env bash
# SKI Bootstrap — VM Step 1: Base packages and system configuration
# Run as root or with sudo

set -euo pipefail

echo ""
echo "=== SKI Bootstrap: Base System Setup ==="
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "[WARN] Not running as root. Retrying with sudo..."
    exec sudo bash "$0" "$@"
fi

# Update system
echo "--- Updating system packages ---"
apt update
apt upgrade -y

# Install essential packages
echo ""
echo "--- Installing essential packages ---"
apt install -y \
    curl \
    wget \
    jq \
    git \
    htop \
    net-tools \
    netcat-openbsd \
    cifs-utils \
    openssh-server \
    ca-certificates \
    gnupg \
    lsb-release \
    unzip \
    vim \
    tmux

# Enable SSH
echo ""
echo "--- Configuring SSH ---"
systemctl enable ssh
systemctl start ssh
echo "[OK] SSH server enabled and started"

# Set timezone
echo ""
echo "--- Setting timezone ---"
timedatectl set-timezone Europe/Berlin
echo "[OK] Timezone set to Europe/Berlin"

# Configure hostname
DESIRED_HOSTNAME="28bots-orchestrator"
CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" != "$DESIRED_HOSTNAME" ]; then
    hostnamectl set-hostname "$DESIRED_HOSTNAME"
    echo "[OK] Hostname set to $DESIRED_HOSTNAME"
else
    echo "[OK] Hostname already $DESIRED_HOSTNAME"
fi

# Create mount point for vault
mkdir -p /mnt/28bots_core
echo "[OK] Mount point /mnt/28bots_core created"

echo ""
echo "[DONE] Base system setup complete."
echo "Next: Run 02_setup_smb_mount.sh"
