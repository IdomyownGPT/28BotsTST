#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — 05_setup_hermes.sh — Interactive Hermes profile setup
#
# Configures: Hermes Agent container, profile matrix
#
# Memory: Obsidian vault on host (no Milvus)
#
# Run as regular user (archat).
#
# Philosophy: CHECK → REPORT → ASK → ACT → VERIFY
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_lib.sh"

show_banner "Hermes Agent Setup" "v0.8.0 — 3x3 Profile Matrix"

# ── Defaults ──
DEF_RUNTIME_DIR="$HOME/28Bots_Runtime"
DEF_RUNTIME_SMB="/mnt/28bots_core/runtime"
DEF_DEFAULT_PROFILE="tiferet-beta"
HERMES_CONTAINER="ski-hermes-agent"

# Find runtime directory
RUNTIME_DIR=""
if [[ -d "$DEF_RUNTIME_DIR" && -f "$DEF_RUNTIME_DIR/docker-compose.yml" ]]; then
    RUNTIME_DIR="$DEF_RUNTIME_DIR"
elif [[ -d "$DEF_RUNTIME_SMB" && -f "$DEF_RUNTIME_SMB/docker-compose.yml" ]]; then
    RUNTIME_DIR="$DEF_RUNTIME_SMB"
else
    warn "Runtime directory not found at $DEF_RUNTIME_DIR or $DEF_RUNTIME_SMB"
    RUNTIME_DIR=$(ask_input "Runtime directory path" "$DEF_RUNTIME_DIR")
fi

# ═══════════════════════════════════════════════════════════════
# 1. Hermes container status
# ═══════════════════════════════════════════════════════════════

header "Hermes Agent Container"

HERMES_RUNNING=false
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$HERMES_CONTAINER"; then
    HERMES_STATUS=$(docker inspect "$HERMES_CONTAINER" --format '{{.State.Status}}' 2>/dev/null)
    ok "Hermes Agent container is $HERMES_STATUS"
    HERMES_RUNNING=true
elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "$HERMES_CONTAINER"; then
    HERMES_STATUS=$(docker inspect "$HERMES_CONTAINER" --format '{{.State.Status}}' 2>/dev/null)
    warn "Hermes Agent container exists but is $HERMES_STATUS"
    if ask_yn "Start Hermes Agent container?"; then
        cd "$RUNTIME_DIR" 2>/dev/null && docker compose up -d hermes-agent
        ok "Hermes Agent container started"
        HERMES_RUNNING=true
    fi
else
    warn "Hermes Agent container not found"
    info "Deploy containers first (04_deploy_containers.sh)"
    if [[ -d "$RUNTIME_DIR" ]] && ask_yn "Deploy Hermes Agent container now?"; then
        cd "$RUNTIME_DIR" && docker compose up -d hermes-agent
        ok "Hermes Agent container deployed"
        HERMES_RUNNING=true
    else
        skip "Hermes Agent container"
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
ENV_FILE="$RUNTIME_DIR/.env"
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
# 4. Memory — Obsidian Vault on Host
# ═══════════════════════════════════════════════════════════════

header "Memory Provider — Obsidian Vault"

VAULT_MOUNT="${SKI_VAULT_MOUNT:-/mnt/28bots_core}"
if check_mount_active "$VAULT_MOUNT"; then
    ok "Vault mounted at $VAULT_MOUNT"
    info "Memory is managed via Obsidian vault on the Windows host"
    info "Hermes reads/writes memory through the shared mount"
else
    warn "Vault NOT mounted at $VAULT_MOUNT"
    info "Hermes can still run, but won't have access to shared memory"
fi

# ═══════════════════════════════════════════════════════════════
# 5. Test profile (optional)
# ═══════════════════════════════════════════════════════════════

header "Profile Test"
if [[ "$HERMES_RUNNING" == "true" ]]; then
    if ask_yn "Run a quick Hermes profile test?" "N"; then
        TEST_PROFILE=$(ask_input "Test profile" "$CURRENT_PROFILE")
        info "Testing profile '$TEST_PROFILE'..."
        RESULT=$(docker exec "$HERMES_CONTAINER" hermes -p "$TEST_PROFILE" --max-turns 1 chat "Reply with only: OK" 2>&1 || echo "FAILED")
        if echo "$RESULT" | grep -qi "ok\|success"; then
            ok "Profile '$TEST_PROFILE' responded"
        else
            warn "Profile test result: $RESULT"
        fi
    else
        skip "Profile test"
    fi
else
    info "Hermes Agent not running — skipping profile test"
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

header "Hermes Setup Complete"
info "Default profile: $(grep -oP 'SKI_HERMES_DEFAULT_PROFILE=\K.*' "$ENV_FILE" 2>/dev/null || echo "$DEF_DEFAULT_PROFILE")"
info "Memory provider: Obsidian vault ($VAULT_MOUNT)"
info "Container:       $HERMES_CONTAINER"
echo ""
echo -e "  ${GRAY}Profile switching: hermes -p [profile] chat${NC}"
echo -e "  ${GRAY}Example: hermes -p kether-alpha --max-turns 5 chat${NC}"
echo ""
print_summary
