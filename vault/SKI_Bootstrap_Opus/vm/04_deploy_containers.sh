#!/usr/bin/env bash
# SKI Bootstrap — VM Step 4: Clone repo and deploy containers
# Run as the regular user (archat), NOT as root

set -euo pipefail

echo ""
echo "=== SKI Bootstrap: Container Deployment ==="
echo ""

# Verify Docker works without sudo
if ! docker info &>/dev/null; then
    echo "[FAIL] Docker not accessible. Did you log out and back in after Step 3?"
    echo "  If not: log out, log back in, then re-run this script."
    exit 1
fi
echo "[OK] Docker is accessible"

REPO_DIR="$HOME/28BotsTST"
REPO_URL="https://github.com/IdomyownGPT/28BotsTST.git"
VAULT_MOUNT="/mnt/28bots_core"

# Check vault mount (containers need it)
if mountpoint -q "$VAULT_MOUNT" 2>/dev/null; then
    echo "[OK] Vault mount is active at $VAULT_MOUNT"
else
    echo "[WARN] Vault mount not active at $VAULT_MOUNT"
    echo "  Containers that need vault access will have issues."
    echo "  Fix: sudo mount -a"
fi

# Clone or update repo
echo ""
echo "--- Repository ---"
if [ -d "$REPO_DIR/.git" ]; then
    echo "[OK] Repo exists at $REPO_DIR"
    cd "$REPO_DIR"
    git pull origin main 2>/dev/null || echo "[WARN] Could not pull latest (may be offline)"
else
    echo "Cloning repository..."
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
    echo "[OK] Repo cloned to $REPO_DIR"
fi

# Setup .env
echo ""
echo "--- Environment ---"
if [ -f "$REPO_DIR/.env" ]; then
    echo "[OK] .env file exists"
else
    if [ -f "$REPO_DIR/.env.example" ]; then
        cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
        echo "[CREATED] .env from .env.example"
        echo ""
        echo "  IMPORTANT: Edit .env before starting containers:"
        echo "  nano $REPO_DIR/.env"
        echo ""
        read -rp "  Press Enter to continue (or Ctrl+C to edit .env first)... "
    else
        echo "[WARN] No .env.example found"
    fi
fi

# Create Docker network if needed
echo ""
echo "--- Docker Network ---"
if docker network ls --format '{{.Name}}' | grep -q "docker_deer-flow"; then
    echo "[OK] Network 'docker_deer-flow' exists"
else
    docker network create docker_deer-flow
    echo "[CREATED] Network 'docker_deer-flow'"
fi

# Deploy containers
echo ""
echo "--- Deploying Containers ---"
cd "$REPO_DIR"

if [ -f docker-compose.yml ]; then
    docker compose up -d
    echo ""
    echo "--- Container Status ---"
    docker compose ps
else
    echo "[FAIL] docker-compose.yml not found in $REPO_DIR"
    exit 1
fi

echo ""
echo "[DONE] Containers deployed."
echo "Next: Run 05_setup_hermes.sh"
