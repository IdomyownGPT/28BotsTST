#!/usr/bin/env bash
# verify_network.sh — Check network connectivity between SKI components
# Run this script FROM the Ubuntu VM (192.168.178.124)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
parse_common_args "$@"

section_header "Network Verification"

# ── Check if running on the expected VM ──
CURRENT_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ "$CURRENT_IP" != "$VM_IP" ]; then
    log_warn "Expected to run on VM ($VM_IP), but current IP is: ${CURRENT_IP:-unknown}"
    log_info "Results may differ if not running from the VM"
fi

# ── Ping Host ──
section_header "Host Connectivity"

if ping -c 1 -W 3 "$HOST_IP" &>/dev/null; then
    log_ok "Host $HOST_IP is reachable (ping)"
else
    log_fail "Host $HOST_IP is unreachable (ping)"
fi

# ── LM Studio API ──
section_header "LM Studio API ($HOST_IP:$LM_STUDIO_PORT)"

if test_port "$HOST_IP" "$LM_STUDIO_PORT"; then
    log_ok "LM Studio port $LM_STUDIO_PORT is open"
else
    log_fail "LM Studio port $LM_STUDIO_PORT is closed or unreachable"
fi

if command -v curl &>/dev/null; then
    HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 5 "$LM_STUDIO_URL/v1/models" 2>/dev/null || true)
    if [ "$HTTP_CODE" = "200" ]; then
        log_ok "LM Studio /v1/models returns HTTP 200"
    else
        log_fail "LM Studio /v1/models returned HTTP ${HTTP_CODE:-timeout}"
    fi
fi

# ── Docker Container Ports (on VM) ──
section_header "Container Ports (localhost)"

declare -A PORTS=(
    ["DeerFlow (nginx)"]="2026"
    ["LangGraph Engine"]="2024"
    ["DeerFlow Frontend"]="3100"
    ["DeerFlow Gateway"]="8001"
    ["OpenClaw"]="3000"
    ["Agent Zero"]="8080"
    ["Milvus VDB"]="19530"
)

for service in "${!PORTS[@]}"; do
    port="${PORTS[$service]}"
    if test_port "127.0.0.1" "$port" 2; then
        log_ok "$service on port $port is open"
    else
        log_fail "$service on port $port is closed"
    fi
done

# ── SMB Port (Host) ──
section_header "SMB/CIFS (Host)"

if test_port "$HOST_IP" 445 3; then
    log_ok "SMB port 445 on $HOST_IP is open"
else
    log_fail "SMB port 445 on $HOST_IP is closed"
fi

# ── Summary ──
print_summary "Network"
