#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — 05_setup_hermes.sh — Interactive Hermes profile setup
#
# Configures: Hermes container, profile matrix, memory provider
#
# Run as regular user (archat).
#
# Philosophy: CHECK → REPORT → ASK → ACT → VERIFY
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_lib.sh"

show_banner "Hermes Orchestrator" "v0.7.0 — 3x3 Profile Matrix, Camofox, Milvus Memory"

# ── Defaults ──
DEF_REPO_DIR="$HOME/28BotsTST"
DEF_DEFAULT_PROFILE="tiferet-beta"

# ═══════════════════════════════════════════════════════════════
# 1. Hermes container status
# ═══════════════════════════════════════════════════════════════

header "Hermes Container"

HERMES_RUNNING=false
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q ski-hermes; then
    HERMES_STATUS=$(docker inspect ski-hermes --format '{{.State.Status}}' 2>/dev/null)
    ok "Hermes container is $HERMES_STATUS"
    HERMES_RUNNING=true
elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q ski-hermes; then
    HERMES_STATUS=$(docker inspect ski-hermes --format '{{.State.Status}}' 2>/dev/null)
    warn "Hermes container exists but is $HERMES_STATUS"
    if ask_yn "Start Hermes container?"; then
        cd "$DEF_REPO_DIR" 2>/dev/null && docker compose up -d hermes
        ok "Hermes container started"
        HERMES_RUNNING=true
    fi
else
    warn "Hermes container not found"
    info "Deploy containers first (04_deploy_containers.sh)"
    if [[ -d "$DEF_REPO_DIR" ]] && ask_yn "Deploy Hermes container now?"; then
        cd "$DEF_REPO_DIR" && docker compose up -d hermes
        ok "Hermes container deployed"
        HERMES_RUNNING=true
    else
        skip "Hermes container"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 2. Profile Matrix
# ═══════════════════════════════════════════════════════════════

header "Hermes 3x3 Profile Matrix"

echo -e "  The Hermes orchestrator uses 9 profiles based on the"
echo -e "  Kabbalistic Tree of Life (Sephiroth x Role):"
echo ""
echo -e "  ${CYAN}              α Generation    β Orchestration   γ Execution${NC}"
echo -e "  ${BOLD}ᛉ Kether${NC}     kether-alpha   kether-beta      kether-gamma"
echo -e "  ${BOLD}ᚷ Tiferet${NC}   tiferet-alpha  ${GREEN}tiferet-beta ★${NC}   tiferet-gamma"
echo -e "  ${BOLD}ᚢ Malkuth${NC}   malkuth-alpha  malkuth-beta     malkuth-gamma"
echo ""
echo -e "  ${GRAY}★ = Default profile${NC}"
echo -e "  ${GRAY}Rows = abstraction level (crown → beauty → kingdom)${NC}"
echo -e "  ${GRAY}Cols = role (create → coordinate → execute)${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# 3. Default profile configuration
# ═══════════════════════════════════════════════════════════════

header "Default Profile"

# Read current from .env
ENV_FILE="$DEF_REPO_DIR/.env"
CURRENT_PROFILE="$DEF_DEFAULT_PROFILE"
if [[ -f "$ENV_FILE" ]]; then
    CURRENT_PROFILE=$(grep -oP 'SKI_HERMES_DEFAULT_PROFILE=\K.*' "$ENV_FILE" 2>/dev/null || echo "$DEF_DEFAULT_PROFILE")
fi
info "Current default: $CURRENT_PROFILE"

PROFILES=(
    "kether-alpha" "kether-beta" "kether-gamma"
    "tiferet-alpha" "tiferet-beta" "tiferet-gamma"
    "malkuth-alpha" "malkuth-beta" "malkuth-gamma"
)

if ask_yn "Change default profile? (current: $CURRENT_PROFILE)" "N"; then
    NEW_PROFILE=$(ask_choice "Select default profile:" \
        "tiferet-beta (balanced orchestration — recommended)" \
        "kether-beta (high-level reasoning)" \
        "malkuth-gamma (ground-level execution)" \
        "Other (enter manually)")

    case "$NEW_PROFILE" in
        *tiferet-beta*) NEW_PROFILE="tiferet-beta" ;;
        *kether-beta*)  NEW_PROFILE="kether-beta" ;;
        *malkuth-gamma*) NEW_PROFILE="malkuth-gamma" ;;
        *)
            NEW_PROFILE=$(ask_input "Profile name" "$CURRENT_PROFILE")
            ;;
    esac

    if [[ -f "$ENV_FILE" ]]; then
        sed -i "s|SKI_HERMES_DEFAULT_PROFILE=.*|SKI_HERMES_DEFAULT_PROFILE=$NEW_PROFILE|" "$ENV_FILE"
        ok "Default profile set to '$NEW_PROFILE' in .env"
    else
        warn ".env not found — set SKI_HERMES_DEFAULT_PROFILE=$NEW_PROFILE manually"
    fi
else
    ok "Keeping default: $CURRENT_PROFILE"
fi

# ═══════════════════════════════════════════════════════════════
# 4. Milvus Memory Provider
# ═══════════════════════════════════════════════════════════════

header "Memory Provider — Milvus Integration"

# Check Milvus container
MILVUS_RUNNING=false
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q ski-milvus; then
    ok "Milvus container is running"
    if check_port_open localhost 19530; then
        ok "Milvus port 19530 is open"
        MILVUS_RUNNING=true
    else
        warn "Milvus container running but port 19530 not responding"
    fi
else
    warn "Milvus container not running"
fi

# Read current memory provider from .env
CURRENT_MEM="built-in"
if [[ -f "$ENV_FILE" ]]; then
    CURRENT_MEM=$(grep -oP 'SKI_HERMES_MEMORY_PROVIDER=\K.*' "$ENV_FILE" 2>/dev/null || echo "built-in")
fi
info "Current memory provider: $CURRENT_MEM"

if [[ "$MILVUS_RUNNING" == "true" ]]; then
    if [[ "$CURRENT_MEM" == "milvus" ]]; then
        ok "Milvus already configured as memory provider"
    else
        if ask_yn "Enable Milvus as Hermes memory provider? (currently: $CURRENT_MEM)" "N"; then
            if [[ -f "$ENV_FILE" ]]; then
                sed -i "s|SKI_HERMES_MEMORY_PROVIDER=.*|SKI_HERMES_MEMORY_PROVIDER=milvus|" "$ENV_FILE"
                ok "Memory provider set to 'milvus' in .env"
                warn "Restart Hermes to apply: docker compose restart hermes"
            fi
        else
            ok "Keeping memory provider: $CURRENT_MEM"
        fi
    fi
else
    info "Milvus not running — memory provider stays as '$CURRENT_MEM'"
    info "Start Milvus first, then re-run this script to enable"
fi

# ═══════════════════════════════════════════════════════════════
# 5. Camofox Browser (port 9377)
# ═══════════════════════════════════════════════════════════════

header "Camofox Browser (Anti-Detection)"
if check_port_open localhost 9377; then
    ok "Camofox port 9377 is open"
else
    info "Camofox port 9377 not open (may be normal if Hermes hasn't started Camofox)"
    info "Camofox starts on-demand when Hermes needs browser automation"
fi

# ═══════════════════════════════════════════════════════════════
# 6. Test profile (optional)
# ═══════════════════════════════════════════════════════════════

header "Profile Test"
if [[ "$HERMES_RUNNING" == "true" ]]; then
    if ask_yn "Run a quick Hermes profile test?" "N"; then
        TEST_PROFILE=$(ask_input "Test profile" "$CURRENT_PROFILE")
        info "Testing profile '$TEST_PROFILE'..."
        RESULT=$(docker exec ski-hermes hermes -p "$TEST_PROFILE" --max-turns 1 chat "Reply with only: OK" 2>&1 || echo "FAILED")
        if echo "$RESULT" | grep -qi "ok\|success"; then
            ok "Profile '$TEST_PROFILE' responded"
        else
            warn "Profile test result: $RESULT"
        fi
    else
        skip "Profile test"
    fi
else
    info "Hermes not running — skipping profile test"
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

header "Hermes Setup Complete"
info "Default profile: $(grep -oP 'SKI_HERMES_DEFAULT_PROFILE=\K.*' "$ENV_FILE" 2>/dev/null || echo "$DEF_DEFAULT_PROFILE")"
info "Memory provider: $(grep -oP 'SKI_HERMES_MEMORY_PROVIDER=\K.*' "$ENV_FILE" 2>/dev/null || echo "built-in")"
info "Camofox port:    9377"
echo ""
echo -e "  ${GRAY}Profile switching: hermes -p [profile] chat${NC}"
echo -e "  ${GRAY}Example: hermes -p kether-alpha --max-turns 5 chat${NC}"
echo ""
print_summary
