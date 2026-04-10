#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — 06_verify_vm.sh — Comprehensive VM verification
#
# Read-only checks — does NOT modify anything.
# Uses 00_lib.sh for consistent output formatting.
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_lib.sh"

show_banner "VM Verification" "Read-only system health check"

info "Date:     $(date '+%Y-%m-%d %H:%M:%S')"
info "Hostname: $(get_current_hostname)"
info "User:     $(whoami)"
info "Kernel:   $(get_current_kernel)"
info "IP:       $(get_current_ip)"

HOST_IP="${SKI_HOST_IP:-192.168.178.90}"
LM_PORT="${SKI_LM_STUDIO_PORT:-1234}"
VAULT_MOUNT="${SKI_VAULT_MOUNT:-/mnt/28bots_core}"
REPO_DIR="${SKI_REPO_DIR:-$HOME/28BotsTST}"

# ── System ──
header "System Resources"
RAM_GB=$(get_ram_gb)
if (( $(echo "$RAM_GB >= 16" | bc -l 2>/dev/null || echo 0) )); then ok "RAM: ${RAM_GB} GB"
elif (( $(echo "$RAM_GB >= 9" | bc -l 2>/dev/null || echo 0) )); then warn "RAM: ${RAM_GB} GB (16GB recommended)"
else fail "RAM: ${RAM_GB} GB (minimum 9GB)"; fi

DISK_FREE=$(get_disk_free_gb)
if [[ "$DISK_FREE" -ge 20 ]]; then ok "Disk: ${DISK_FREE} GB free"
elif [[ "$DISK_FREE" -ge 10 ]]; then warn "Disk: ${DISK_FREE} GB free (getting low)"
else fail "Disk: ${DISK_FREE} GB free (< 10GB!)"; fi

# Hyper-V integration
KERNEL=$(get_current_kernel)
if [[ "$KERNEL" == *azure* ]]; then
    ok "Azure kernel: $KERNEL (Hyper-V optimized)"
else
    warn "Non-Azure kernel: $KERNEL (consider installing linux-azure)"
fi

# ── Network ──
header "Network"
if ping -c 1 -W 3 "$HOST_IP" &>/dev/null; then
    ok "Host $HOST_IP reachable"
else
    fail "Host $HOST_IP unreachable"
fi

if curl -sf --max-time 5 "http://${HOST_IP}:${LM_PORT}/v1/models" &>/dev/null; then
    ok "LM Studio API responding on $HOST_IP:$LM_PORT"
    MODEL_COUNT=$(curl -sf "http://${HOST_IP}:${LM_PORT}/v1/models" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null || echo "?")
    info "Models loaded: $MODEL_COUNT"
else
    fail "LM Studio API not responding"
fi

# Container ports
header "Container Ports"
for entry in "2024:LangGraph" "2026:DeerFlow-nginx" "3000:OpenClaw" "3100:DeerFlow-Frontend" "8001:Gateway" "8080:AgentZero" "9377:Camofox" "19530:Milvus"; do
    port="${entry%%:*}"
    name="${entry##*:}"
    if nc -z -w 2 127.0.0.1 "$port" 2>/dev/null; then
        ok "$name on :$port"
    else
        fail "$name on :$port not responding"
    fi
done

# ── Vault Mount ──
header "Vault Mount"
if check_mount_active "$VAULT_MOUNT"; then
    ok "Vault mounted at $VAULT_MOUNT"
    if check_fstab_entry "x-systemd.automount"; then
        ok "fstab has x-systemd.automount"
    else
        warn "fstab missing x-systemd.automount"
    fi
    # Write test
    TESTFILE="$VAULT_MOUNT/.ski_verify_$$"
    if touch "$TESTFILE" 2>/dev/null; then
        rm -f "$TESTFILE"
        ok "Vault write access confirmed"
    else
        warn "Vault write access denied (read-only?)"
    fi
    FILE_COUNT=$(find "$VAULT_MOUNT" -maxdepth 2 -type f 2>/dev/null | wc -l)
    info "Files (depth 2): $FILE_COUNT"
else
    fail "Vault NOT mounted at $VAULT_MOUNT"
fi

# ── Docker ──
header "Docker"
if command -v docker &>/dev/null; then
    ok "Docker installed: $(docker --version 2>/dev/null | cut -d' ' -f3)"
else
    fail "Docker not installed"
fi

if docker info &>/dev/null; then
    ok "Docker daemon running"
    RUNNING=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)
    TOTAL=$(docker ps -a --format '{{.Names}}' 2>/dev/null | wc -l)
    info "Containers: $RUNNING running / $TOTAL total"

    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | while IFS= read -r line; do
        info "  $line"
    done
elif docker ps &>/dev/null 2>&1; then
    ok "Docker accessible (via group)"
else
    fail "Docker daemon not accessible (not in docker group?)"
fi

# ── Hermes ──
header "Hermes"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q ski-hermes; then
    ok "Hermes running in Docker"
    # Check profile env
    PROFILE=$(docker exec ski-hermes printenv HERMES_DEFAULT_PROFILE 2>/dev/null || echo "unknown")
    info "Default profile: $PROFILE"
elif command -v hermes &>/dev/null; then
    ok "Hermes CLI available"
else
    warn "Hermes not found (CLI or Docker)"
fi

# ── Repo ──
header "Repository"
if [[ -d "$REPO_DIR/.git" ]]; then
    ok "Repo present at $REPO_DIR"
    BRANCH=$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || echo "unknown")
    info "Branch: $BRANCH"
    if [[ -f "$REPO_DIR/docker-compose.yml" ]]; then
        ok "docker-compose.yml present"
    else
        fail "docker-compose.yml missing"
    fi
    if [[ -f "$REPO_DIR/.env" ]]; then
        ok ".env file configured"
    else
        warn ".env file missing (copy from .env.example)"
    fi
else
    warn "Repo not cloned at $REPO_DIR"
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

print_summary
