#!/usr/bin/env bash
# verify_lm_studio.sh — Check LM Studio API, models, inference, and embeddings

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
parse_common_args "$@"

section_header "LM Studio Verification"

if ! check_command curl; then
    print_summary "LM Studio"
    exit 1
fi

API_BASE="$LM_STUDIO_URL/v1"

# ── API Reachability ──
section_header "API Connectivity"

HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 5 "$API_BASE/models" 2>/dev/null || true)
if [ "$HTTP_CODE" = "200" ]; then
    log_ok "LM Studio API reachable at $API_BASE"
else
    log_fail "LM Studio API unreachable (HTTP ${HTTP_CODE:-timeout})"
    log_info "Ensure LM Studio is running on $HOST_IP:$LM_STUDIO_PORT"
    print_summary "LM Studio"
    exit 1
fi

# ── Model Inventory ──
section_header "Loaded Models"

MODELS_JSON=$(curl -sf --max-time 10 "$API_BASE/models" 2>/dev/null || echo '{}')
MODEL_COUNT=$(echo "$MODELS_JSON" | grep -o '"id"' | wc -l)
log_info "Total models available: $MODEL_COUNT"

# Check for expected models (Bonsai Prism 8B instances + embedding model)
EXPECTED_MODELS=(
    "bonsai-prism-8b:Bonsai Prism 8B (normal)"
    "nomic-embed-text:Nomic Embed Text (embeddings)"
)

for entry in "${EXPECTED_MODELS[@]}"; do
    model_pattern="${entry%%:*}"
    model_label="${entry##*:}"
    if echo "$MODELS_JSON" | grep -qi "$model_pattern"; then
        log_ok "$model_label is loaded"
    else
        log_warn "$model_label not found (pattern: $model_pattern)"
        log_info "Available models may use different naming — check LM Studio GUI"
    fi
done

# Check for Symbolect-trained instance
if echo "$MODELS_JSON" | grep -qi "symbolect\|rune\|prism.*symbol"; then
    log_ok "Bonsai Prism 8B (Symbolect-trained) instance found"
else
    log_warn "No Symbolect-trained model instance detected"
    log_info "This may need to be loaded separately in LM Studio"
fi

# List all available models
section_header "All Available Models"
echo "$MODELS_JSON" | grep -oP '"id"\s*:\s*"\K[^"]+' | while read -r model; do
    log_info "  $model"
done

# ── Inference Test ──
section_header "Inference Test (Chat Completion)"

# Try with the first available model
FIRST_MODEL=$(echo "$MODELS_JSON" | grep -oP '"id"\s*:\s*"\K[^"]+' | head -1)

if [ -n "$FIRST_MODEL" ]; then
    log_info "Testing inference with model: $FIRST_MODEL"

    START_TIME=$(date +%s%N)
    RESPONSE=$(curl -sf --max-time 30 "$API_BASE/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$FIRST_MODEL\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Reply with only the word: OK\"}],
            \"max_tokens\": 5,
            \"temperature\": 0
        }" 2>/dev/null || echo "")
    END_TIME=$(date +%s%N)

    if [ -n "$RESPONSE" ] && echo "$RESPONSE" | grep -q '"choices"'; then
        ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
        REPLY=$(echo "$RESPONSE" | grep -oP '"content"\s*:\s*"\K[^"]+' | head -1)
        log_ok "Inference successful (${ELAPSED_MS}ms) — Response: ${REPLY:-[empty]}"
    else
        log_fail "Inference failed or timed out"
        [ -n "$RESPONSE" ] && log_info "Response: ${RESPONSE:0:200}"
    fi
else
    log_skip "No models loaded — skipping inference test"
fi

# ── Embedding Test ──
section_header "Embedding Test"

EMBED_MODEL=$(echo "$MODELS_JSON" | grep -oP '"id"\s*:\s*"\K[^"]*embed[^"]*' | head -1)

if [ -n "$EMBED_MODEL" ]; then
    log_info "Testing embeddings with model: $EMBED_MODEL"

    EMBED_RESPONSE=$(curl -sf --max-time 15 "$API_BASE/embeddings" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$EMBED_MODEL\",
            \"input\": \"SKI verification test\"
        }" 2>/dev/null || echo "")

    if [ -n "$EMBED_RESPONSE" ] && echo "$EMBED_RESPONSE" | grep -q '"embedding"'; then
        DIMENSIONS=$(echo "$EMBED_RESPONSE" | grep -oP '\[[-0-9.e,\s]+\]' | head -1 | tr ',' '\n' | wc -l)
        log_ok "Embedding successful (${DIMENSIONS} dimensions)"
    else
        log_fail "Embedding test failed"
        [ -n "$EMBED_RESPONSE" ] && log_info "Response: ${EMBED_RESPONSE:0:200}"
    fi
else
    log_warn "No embedding model found — skipping embedding test"
    log_info "Expected: nomic-embed-text"
fi

# ── Summary ──
print_summary "LM Studio"
