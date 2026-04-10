#!/usr/bin/env bash
# SKI Verify — Auto Research
# Checks Auto Research components from the VM side
# (LM Studio API availability, vault results directory, experiment logs)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || {
    # Minimal fallback if common.sh not available
    log_ok()   { echo "  [OK]   $1"; }
    log_fail() { echo "  [FAIL] $1"; }
    log_warn() { echo "  [WARN] $1"; }
    log_info() { echo "  [INFO] $1"; }
    PASS=0; FAIL=0; WARN=0
}

HOST_IP="${SKI_HOST_IP:-192.168.178.90}"
LM_PORT="${SKI_LM_STUDIO_PORT:-1234}"
VAULT_MOUNT="${SKI_VAULT_MOUNT:-/mnt/28bots_core}"
RESULTS_DIR="$VAULT_MOUNT/Obsidian_Vault/SKI_Cookbook/M12_AutoResearch"

echo ""
echo "=== SKI Verify: Auto Research ==="
echo ""

# ── 1. LM Studio API (inference endpoint for agent) ──
echo "--- LM Studio API (Agent Backend) ---"

if curl -sf "http://$HOST_IP:$LM_PORT/v1/models" >/dev/null 2>&1; then
    # FIX: jq statt python für sauberes Parsing
    MODEL_COUNT=$(curl -sf "http://$HOST_IP:$LM_PORT/v1/models" | jq '.data | length' 2>/dev/null || echo "?")
    log_ok "LM Studio API responding ($MODEL_COUNT models loaded)"

    # Test inference
    MODEL_ID=$(curl -sf "http://$HOST_IP:$LM_PORT/v1/models" | jq -r '.data[0].id // empty' 2>/dev/null)
    BODY='{"model":"'$MODEL_ID'","messages":[{"role":"user","content":"Reply OK"}],"max_tokens":5}'

    if [ -n "$MODEL_ID" ]; then
        RESPONSE=$(curl -sf -X POST "http://$HOST_IP:$LM_PORT/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "$BODY" --max-time 30 2>/dev/null)
        if [ -n "$RESPONSE" ]; then
            log_ok "Agent inference test passed"
        else
            log_warn "Agent inference test failed (timeout or error)"
        fi
    fi
else
    log_fail "LM Studio API not responding at $HOST_IP:$LM_PORT"
    log_info "Auto Research agent cannot propose changes without LM Studio"
fi

# ── 2. Vault Results Directory ──
echo ""
echo "--- Vault Integration ---"

if [ -d "$VAULT_MOUNT" ]; then
    log_ok "Vault mounted at $VAULT_MOUNT"

    if [ -d "$RESULTS_DIR" ]; then
        log_ok "Results directory exists: M12_AutoResearch/"

        # Check for experiment logs
        if [ -f "$RESULTS_DIR/results.jsonl" ]; then
            EXP_COUNT=$(wc -l < "$RESULTS_DIR/results.jsonl" 2>/dev/null || echo "0")
            KEPT_COUNT=$(grep -c '"kept": true' "$RESULTS_DIR/results.jsonl" 2>/dev/null || echo "0")
            log_ok "Experiment log: $EXP_COUNT experiments ($KEPT_COUNT kept)"

            # Show latest experiment
            LATEST=$(tail -1 "$RESULTS_DIR/results.jsonl" 2>/dev/null)
            if [ -n "$LATEST" ]; then
                LATEST_BPB=$(echo "$LATEST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('val_bpb','N/A'))" 2>/dev/null || echo "N/A")
                LATEST_DESC=$(echo "$LATEST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('description','?')[:60])" 2>/dev/null || echo "?")
                log_info "Latest: val_bpb=$LATEST_BPB — $LATEST_DESC"
            fi
        else
            log_info "No experiments run yet (results.jsonl not found)"
        fi

        # Check for summary markdown
        if [ -f "$RESULTS_DIR/AutoResearch_Log.md" ]; then
            log_ok "Obsidian summary: AutoResearch_Log.md"
        fi
    else
        log_info "Results directory not yet created (no experiments run)"
    fi
else
    log_warn "Vault not mounted at $VAULT_MOUNT — cannot check results"
fi

# ── 3. GPU Status (via SSH to host, if available) ──
echo ""
echo "--- GPU Status ---"

# Try SSH to check GPU on host
if ssh -o ConnectTimeout=3 -o BatchMode=yes "skiuser@$HOST_IP" "nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader" 2>/dev/null; then
    log_ok "GPU status retrieved via SSH"
else
    log_info "Cannot check GPU status (SSH to host not available)"
    log_info "Check manually: nvidia-smi on the Windows host"
fi

# ── Summary ──
echo ""
echo "--- Auto Research Verify Summary ---"
if type print_summary &>/dev/null; then
    print_summary
fi
echo ""
