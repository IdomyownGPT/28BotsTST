#!/usr/bin/env bash
# SKI Bootstrap — VM Step 6: Full VM verification
# Runs all verification scripts from the repo or standalone checks

set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   SKI Bootstrap — VM Verification                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Date:     $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Host:     $(hostname 2>/dev/null || echo 'unknown')"
echo "  User:     $(whoami 2>/dev/null || echo 'unknown')"
echo "  Kernel:   $(uname -r 2>/dev/null || echo 'unknown')"
echo ""

PASS=0; FAIL=0; WARN=0

ok()   { PASS=$((PASS+1)); echo "  [PASS] $*"; }
fail() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
warn() { WARN=$((WARN+1)); echo "  [WARN] $*"; }
info() { echo "  [INFO] $*"; }

HOST_IP="192.168.178.90"
LM_PORT="1234"
VAULT_MOUNT="/mnt/28bots_core"
REPO_DIR="$HOME/28BotsTST"

# ── System ──
echo "--- System ---"
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
RAM_GB=$((RAM_MB / 1024))
if [ "$RAM_GB" -ge 16 ]; then ok "RAM: ${RAM_GB}GB"
elif [ "$RAM_GB" -ge 9 ]; then warn "RAM: ${RAM_GB}GB (16GB recommended)"
else fail "RAM: ${RAM_GB}GB (minimum 9GB)"; fi

DISK_AVAIL=$(df -BG / | awk 'NR==2{gsub("G",""); print $4}')
if [ "$DISK_AVAIL" -ge 20 ]; then ok "Disk: ${DISK_AVAIL}GB free"
elif [ "$DISK_AVAIL" -ge 10 ]; then warn "Disk: ${DISK_AVAIL}GB free (getting low)"
else fail "Disk: ${DISK_AVAIL}GB free (< 10GB!)"; fi

# ── Network ──
echo ""
echo "--- Network ---"
if ping -c 1 -W 3 "$HOST_IP" &>/dev/null; then
    ok "Host $HOST_IP reachable"
else
    fail "Host $HOST_IP unreachable"
fi

# LM Studio
if curl -sf --max-time 5 "http://${HOST_IP}:${LM_PORT}/v1/models" &>/dev/null; then
    ok "LM Studio API responding on $HOST_IP:$LM_PORT"
    MODEL_COUNT=$(curl -sf "http://${HOST_IP}:${LM_PORT}/v1/models" | grep -o '"id"' | wc -l)
    info "Models loaded: $MODEL_COUNT"
else
    fail "LM Studio API not responding"
fi

# Container ports
echo ""
echo "--- Container Ports ---"
for entry in "2024:LangGraph" "2026:DeerFlow-nginx" "3000:OpenClaw" "3100:DeerFlow-Frontend" "8001:Gateway" "8080:AgentZero" "19530:Milvus"; do
    port="${entry%%:*}"
    name="${entry##*:}"
    if nc -z -w 2 127.0.0.1 "$port" 2>/dev/null; then
        ok "$name on :$port"
    else
        fail "$name on :$port not responding"
    fi
done

# ── Vault Mount ──
echo ""
echo "--- Vault Mount ---"
if mountpoint -q "$VAULT_MOUNT" 2>/dev/null; then
    ok "Vault mounted at $VAULT_MOUNT"
    # Check fstab options
    if grep -q "x-systemd.automount" /etc/fstab 2>/dev/null; then
        ok "fstab has x-systemd.automount"
    else
        warn "fstab missing x-systemd.automount"
    fi
    # Write test
    TESTFILE="$VAULT_MOUNT/.ski_verify_$(date +%s)"
    if touch "$TESTFILE" 2>/dev/null; then
        rm -f "$TESTFILE"
        ok "Vault write access confirmed"
    else
        fail "Vault write access denied"
    fi
else
    fail "Vault NOT mounted at $VAULT_MOUNT"
fi

# ── Docker ──
echo ""
echo "--- Docker ---"
if command -v docker &>/dev/null; then
    ok "Docker installed: $(docker --version 2>/dev/null | cut -d' ' -f3)"
else
    fail "Docker not installed"
fi

if docker info &>/dev/null; then
    ok "Docker daemon running"
    RUNNING=$(docker ps --format '{{.Names}}' | wc -l)
    TOTAL=$(docker ps -a --format '{{.Names}}' | wc -l)
    info "Containers: $RUNNING running / $TOTAL total"

    # List containers
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | while IFS= read -r line; do
        info "  $line"
    done
else
    fail "Docker daemon not accessible"
fi

# ── Hermes ──
echo ""
echo "--- Hermes ---"
if command -v hermes &>/dev/null; then
    ok "Hermes CLI available"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qi hermes; then
    ok "Hermes running in Docker"
else
    warn "Hermes not found (CLI or Docker)"
fi

# ── Repo ──
echo ""
echo "--- Repository ---"
if [ -d "$REPO_DIR/.git" ]; then
    ok "Repo present at $REPO_DIR"
    if [ -f "$REPO_DIR/docker-compose.yml" ]; then
        ok "docker-compose.yml present"
    else
        fail "docker-compose.yml missing"
    fi
    if [ -f "$REPO_DIR/.env" ]; then
        ok ".env file configured"
    else
        warn ".env file missing (copy from .env.example)"
    fi
else
    warn "Repo not cloned at $REPO_DIR"
fi

# ── Summary ──
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                     SUMMARY                              ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  PASS: %-3d  FAIL: %-3d  WARN: %-3d  Total: %-3d          ║\n" "$PASS" "$FAIL" "$WARN" "$((PASS+FAIL+WARN))"
echo "╚══════════════════════════════════════════════════════════╝"

if [ "$FAIL" -gt 0 ]; then
    echo "  Result: FAILURES DETECTED"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "  Result: WARNINGS (review recommended)"
    exit 0
else
    echo "  Result: ALL SYSTEMS OPERATIONAL"
    exit 0
fi
