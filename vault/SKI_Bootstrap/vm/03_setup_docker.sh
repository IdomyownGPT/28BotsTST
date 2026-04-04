#!/usr/bin/env bash
# SKI Bootstrap — VM Step 3: Install Docker and Docker Compose
# Run as root or with sudo

set -euo pipefail

echo ""
echo "=== SKI Bootstrap: Docker Installation ==="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "[WARN] Not running as root. Retrying with sudo..."
    exec sudo bash "$0" "$@"
fi

TARGET_USER="${SUDO_USER:-archat}"

# Check if Docker is already installed
if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null || echo "unknown")
    echo "[OK] Docker already installed: $DOCKER_VER"
else
    echo "--- Installing Docker ---"

    # Remove old versions
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Install prerequisites
    apt install -y ca-certificates curl gnupg lsb-release

    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "[OK] Docker installed: $(docker --version)"
fi

# Add user to docker group
echo ""
echo "--- Docker Group ---"
if id -nG "$TARGET_USER" | grep -qw docker; then
    echo "[OK] User '$TARGET_USER' is in the docker group"
else
    usermod -aG docker "$TARGET_USER"
    echo "[OK] User '$TARGET_USER' added to docker group"
    echo "[WARN] Log out and back in for group changes to take effect!"
fi

# Enable Docker on boot
systemctl enable docker
systemctl start docker
echo "[OK] Docker enabled on boot"

# Docker Compose check
echo ""
echo "--- Docker Compose ---"
if docker compose version &>/dev/null; then
    echo "[OK] $(docker compose version)"
else
    echo "[FAIL] Docker Compose plugin not found"
    echo "  Try: apt install docker-compose-plugin"
fi

# Verify
echo ""
echo "--- Verification ---"
docker --version
docker compose version
echo ""
docker info --format 'Storage Driver: {{.Driver}}'
echo ""

DISK_FREE=$(df -h / | awk 'NR==2{print $4}')
echo "[INFO] Free disk space: $DISK_FREE"

echo ""
echo "[DONE] Docker installation complete."
echo ""
echo "  IMPORTANT: Log out and back in before running 04_deploy_containers.sh"
echo "  This is needed for the Docker group membership to take effect."
echo ""
echo "Next: Log out, log back in, then run 04_deploy_containers.sh"
