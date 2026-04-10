#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — 04_deploy_containers.sh — Interactive container deployment
#
# Configures: Runtime directory, .env setup, docker compose up
#
# Architecture: 3 containers (Agent Zero, Hermes Agent, OpenClaw)
# Runtime dir:  ~/28Bots_Runtime  (mounted from host via SMB)
#
# Run as regular user (archat), NOT as root.
# If docker group not active yet, run via: sg docker -c "bash 04_deploy_containers.sh"
#
# Philosophy: CHECK → REPORT → ASK → ACT → VERIFY
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_lib.sh"

show_banner "Container Deployment" "3 Containers: Agent Zero, Hermes, OpenClaw"

# ── Defaults ──
DEF_HOST_IP="192.168.178.90"
DEF_LM_PORT="1234"
DEF_VAULT_MOUNT="/mnt/28bots_core"
DEF_RUNTIME_DIR="$HOME/28Bots_Runtime"
DEF_RUNTIME_SMB="$DEF_VAULT_MOUNT/runtime"

# ═══════════════════════════════════════════════════════════════
# 1. Docker access check
# ═══════════════════════════════════════════════════════════════

header "Docker Access"
if docker ps &>/dev/null; then
    RUNNING=$(docker ps -q 2>/dev/null | wc -l)
    ok "Docker accessible without sudo ($RUNNING containers running)"
else
    fail "Cannot access Docker"
    info "Options:"
    info "  1. Log out and back in (if just added to docker group)"
    info "  2. Run this script with: sg docker -c 'bash $0'"
    info "  3. Use: sudo docker ps  (temporary workaround)"
    if ! ask_yn "Try continuing anyway? (some commands may fail)"; then
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 2. Vault mount check
# ═══════════════════════════════════════════════════════════════

header "Vault Mount"
if check_mount_active "$DEF_VAULT_MOUNT"; then
    FILE_COUNT=$(find "$DEF_VAULT_MOUNT" -maxdepth 2 -type f 2>/dev/null | wc -l)
    ok "Vault mounted at $DEF_VAULT_MOUNT ($FILE_COUNT files)"
else
    warn "Vault NOT mounted at $DEF_VAULT_MOUNT"
    info "Containers that bind-mount the vault will have empty mounts"
    if ask_yn "Try mounting now? (sudo mount -a)"; then
        sudo mount -a 2>/dev/null && ok "Mount succeeded" || warn "Mount failed"
    else
        skip "Vault mount"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 3. LM Studio connectivity
# ═══════════════════════════════════════════════════════════════

header "LM Studio (Inference Backend)"
HOST_IP=$(ask_input "Host IP (LM Studio)" "$DEF_HOST_IP")
LM_PORT=$(ask_input "LM Studio port" "$DEF_LM_PORT")

if check_port_open "$HOST_IP" "$LM_PORT"; then
    ok "LM Studio reachable at $HOST_IP:$LM_PORT"
    MODEL_COUNT=$(curl -sf "http://$HOST_IP:$LM_PORT/v1/models" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null || echo "?")
    info "Models loaded: $MODEL_COUNT"
else
    warn "LM Studio NOT reachable at $HOST_IP:$LM_PORT"
    info "Containers will start but AI inference won't work until LM Studio is running"
fi

# ═══════════════════════════════════════════════════════════════
# 4. Runtime directory
# ═══════════════════════════════════════════════════════════════

header "Runtime Directory"

# Check for runtime dir — prefer local symlink/copy, fall back to SMB mount
RUNTIME_DIR=""
if [[ -d "$DEF_RUNTIME_DIR" && -f "$DEF_RUNTIME_DIR/docker-compose.yml" ]]; then
    ok "Runtime directory found at $DEF_RUNTIME_DIR"
    RUNTIME_DIR="$DEF_RUNTIME_DIR"
elif [[ -d "$DEF_RUNTIME_SMB" && -f "$DEF_RUNTIME_SMB/docker-compose.yml" ]]; then
    ok "Runtime directory found at $DEF_RUNTIME_SMB (SMB mount)"
    RUNTIME_DIR="$DEF_RUNTIME_SMB"
else
    warn "Runtime directory not found"
    info "Expected locations:"
    info "  $DEF_RUNTIME_DIR"
    info "  $DEF_RUNTIME_SMB"
    echo ""

    # Offer to create from SMB if vault is mounted
    if [[ -d "$DEF_VAULT_MOUNT" ]] && check_mount_active "$DEF_VAULT_MOUNT"; then
        if [[ -d "$DEF_RUNTIME_SMB" ]]; then
            if ask_yn "Symlink $DEF_RUNTIME_DIR -> $DEF_RUNTIME_SMB?"; then
                ln -sfn "$DEF_RUNTIME_SMB" "$DEF_RUNTIME_DIR"
                ok "Symlink created"
                RUNTIME_DIR="$DEF_RUNTIME_DIR"
            fi
        else
            fail "No runtime/ folder found on the vault mount"
            info "Copy the runtime template from the host:"
            info "  Host: D:\\28Bots_Core\\runtime\\"
            info "  VM:   $DEF_VAULT_MOUNT/runtime/"
            exit 1
        fi
    else
        RUNTIME_DIR=$(ask_input "Runtime directory path" "$DEF_RUNTIME_DIR")
        if [[ ! -d "$RUNTIME_DIR" ]]; then
            fail "Directory does not exist: $RUNTIME_DIR"
            exit 1
        fi
    fi
fi

if [[ -z "$RUNTIME_DIR" ]]; then
    fail "No runtime directory available. Cannot deploy containers."
    exit 1
fi

info "Using runtime: $RUNTIME_DIR"

# ═══════════════════════════════════════════════════════════════
# 5. Environment file (.env)
# ═══════════════════════════════════════════════════════════════

header "Environment Configuration"
cd "$RUNTIME_DIR"

if [[ -f ".env" ]]; then
    found ".env file exists"
    # Show key values (mask sensitive ones)
    info "Current settings:"
    while IFS='=' read -r key val; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        if [[ "$key" =~ TOKEN|PASS|SECRET ]]; then
            echo -e "    ${GRAY}${key}=${NC}${YELLOW}****${NC}"
        else
            echo -e "    ${GRAY}${key}=${val}${NC}"
        fi
    done < .env

    ENV_ACTION=$(ask_choice "What to do with .env?" \
        "Keep as-is" \
        "Edit interactively" \
        "Replace from .env.example")

    case "$ENV_ACTION" in
        "Edit interactively")
            EDITOR_CMD="${EDITOR:-nano}"
            info "Opening .env with $EDITOR_CMD..."
            "$EDITOR_CMD" .env
            ok ".env edited"
            ;;
        "Replace from .env.example")
            if [[ -f ".env.example" ]]; then
                cp .env ".env.bak.$(date +%s)"
                info "Backed up current .env"
                cp .env.example .env
                ok "Replaced .env from .env.example"
                info "Edit .env to set your values (especially Telegram token)"
                if ask_yn "Edit .env now?"; then
                    "${EDITOR:-nano}" .env
                fi
            else
                fail ".env.example not found"
            fi
            ;;
        *)
            ok "Keeping .env as-is"
            ;;
    esac
else
    warn "No .env file found"
    if [[ -f ".env.example" ]]; then
        info "Template available: .env.example"
        if ask_yn "Copy .env.example to .env?"; then
            cp .env.example .env
            ok ".env created from template"

            # Patch in the host IP
            sed -i "s|SKI_HOST_IP=.*|SKI_HOST_IP=$HOST_IP|" .env
            sed -i "s|SKI_LM_STUDIO_BASE_URL=.*|SKI_LM_STUDIO_BASE_URL=http://$HOST_IP:$LM_PORT/v1|" .env
            info "Updated SKI_HOST_IP and LM_STUDIO_BASE_URL in .env"

            if ask_yn "Edit .env now? (set Telegram token, etc.)"; then
                "${EDITOR:-nano}" .env
            fi
        fi
    else
        fail "No .env.example found — create .env manually"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 6. Container deployment
# ═══════════════════════════════════════════════════════════════

header "Container Deployment"
cd "$RUNTIME_DIR"

# Show current state
if docker compose ps &>/dev/null 2>&1; then
    info "Current container status:"
    docker compose ps 2>/dev/null | sed 's/^/    /'
    echo ""

    TOTAL=$(docker compose ps -a --format json 2>/dev/null | wc -l || echo "0")
    RUNNING=$(docker compose ps --format json 2>/dev/null | grep -c '"running"' || echo "0")
    info "Containers: $RUNNING running / $TOTAL total"
fi

DEPLOY_ACTION=$(ask_choice "Deploy action?" \
    "docker compose up -d (start/update all)" \
    "docker compose up -d --build (rebuild)" \
    "Skip deployment")

case "$DEPLOY_ACTION" in
    *"start/update all"*)
        info "Running docker compose up -d..."
        docker compose up -d
        ok "Containers deployed"
        ;;
    *"rebuild"*)
        info "Running docker compose up -d --build..."
        docker compose up -d --build
        ok "Containers rebuilt and deployed"
        ;;
    *)
        skip "Container deployment"
        ;;
esac

# ═══════════════════════════════════════════════════════════════
# 7. Health check
# ═══════════════════════════════════════════════════════════════

header "Container Health Check"
if ask_yn "Wait for containers to be ready? (30s timeout)"; then
    TIMEOUT=30
    ELAPSED=0
    EXPECTED=3  # Agent Zero, Hermes Agent, OpenClaw

    while [[ $ELAPSED -lt $TIMEOUT ]]; do
        RUNNING=$(docker compose ps --format json 2>/dev/null | grep -c '"running"' || echo "0")
        echo -ne "\r  Waiting... $RUNNING/$EXPECTED running (${ELAPSED}s)  "
        if [[ "$RUNNING" -ge "$EXPECTED" ]]; then
            echo ""
            ok "All $EXPECTED containers running!"
            break
        fi
        sleep 3
        ELAPSED=$((ELAPSED + 3))
    done

    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        echo ""
        warn "Timeout reached. Current status:"
        docker compose ps 2>/dev/null | sed 's/^/    /'
    fi
else
    skip "Health check wait"
fi

# Show final status
echo ""
info "Final container status:"
docker compose ps 2>/dev/null | sed 's/^/    /' || true

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

header "Deployment Complete"
info "Runtime:    $RUNTIME_DIR"
info "Vault:      $DEF_VAULT_MOUNT"
info "LM Studio:  http://$HOST_IP:$LM_PORT/v1"
info "Services:   Agent Zero (:8080), Hermes (:9377), OpenClaw (:3000)"
echo ""
print_summary
