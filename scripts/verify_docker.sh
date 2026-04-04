#!/usr/bin/env bash
# verify_docker.sh — Check Docker daemon, containers, and resources

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
parse_common_args "$@"

section_header "Docker Verification"

# ── Docker Daemon ──
section_header "Docker Daemon"

if command -v docker &>/dev/null; then
    log_ok "Docker CLI is installed"
else
    log_fail "Docker CLI not found"
    print_summary "Docker"
    exit 1
fi

if systemctl is-active --quiet docker 2>/dev/null; then
    log_ok "Docker daemon is running"
else
    log_fail "Docker daemon is not running"
    print_summary "Docker"
    exit 1
fi

DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
log_info "Docker version: $DOCKER_VERSION"

# ── Expected Containers ──
section_header "Container Status"

EXPECTED_CONTAINERS=(
    "deerflow"
    "langgraph"
    "gateway"
    "frontend"
    "nginx"
    "openclaw"
    "hermes"
    "agent-zero"
    "milvus"
)

RUNNING_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null)

for container in "${EXPECTED_CONTAINERS[@]}"; do
    # Fuzzy match: check if any running container name contains the expected name
    if echo "$RUNNING_CONTAINERS" | grep -qi "$container"; then
        MATCHED=$(echo "$RUNNING_CONTAINERS" | grep -i "$container" | head -1)
        log_ok "Container '$MATCHED' is running"
    else
        # Check if it exists but is stopped
        ALL_CONTAINERS=$(docker ps -a --format '{{.Names}}' 2>/dev/null)
        if echo "$ALL_CONTAINERS" | grep -qi "$container"; then
            MATCHED=$(echo "$ALL_CONTAINERS" | grep -i "$container" | head -1)
            log_fail "Container '$MATCHED' exists but is STOPPED"
        else
            log_warn "Container matching '$container' not found"
        fi
    fi
done

# ── Container Restart Counts ──
section_header "Restart Counts"

docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null | while IFS=$'\t' read -r name status; do
    restarts=$(echo "$status" | grep -oP '\(\K[0-9]+' || echo "0")
    if [ "$restarts" -gt 5 ] 2>/dev/null; then
        log_warn "Container '$name' has restarted $restarts times"
    fi
done

# ── Memory Usage ──
section_header "Container Memory Usage"

if docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null; then
    log_info "Memory stats displayed above"
else
    log_warn "Could not retrieve memory stats"
fi

# ── Docker Network ──
section_header "Docker Networks"

if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "deer-flow\|deer_flow\|deerflow"; then
    NETWORK=$(docker network ls --format '{{.Name}}' | grep -i "deer.flow" | head -1)
    log_ok "Docker network '$NETWORK' exists"
else
    log_warn "Docker network 'docker_deer-flow' not found (may use a different name)"
fi

# ── Disk Space ──
section_header "Disk Space"

AVAIL_KB=$(df / --output=avail 2>/dev/null | tail -1 | tr -d ' ')
if [ -n "$AVAIL_KB" ]; then
    AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
    if [ "$AVAIL_GB" -lt 10 ]; then
        log_fail "Low disk space: ${AVAIL_GB}GB available (< 10GB threshold)"
    elif [ "$AVAIL_GB" -lt 20 ]; then
        log_warn "Disk space getting low: ${AVAIL_GB}GB available"
    else
        log_ok "Disk space OK: ${AVAIL_GB}GB available"
    fi
fi

# Docker disk usage
section_header "Docker Disk Usage"
docker system df 2>/dev/null || log_warn "Could not retrieve Docker disk usage"

# ── Summary ──
print_summary "Docker"
