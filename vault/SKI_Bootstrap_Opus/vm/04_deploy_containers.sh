#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — 04_deploy_containers.sh — Interactive container deployment
#
# Configures: Git repo clone, .env setup, docker compose up
#
# Run as regular user (archat), NOT as root.
# If docker group not active yet, run via: sg docker -c "bash 04_deploy_containers.sh"
#
# Philosophy: CHECK → REPORT → ASK → ACT → VERIFY
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_lib.sh"

show_banner "Container Deployment" "Git repo, .env config, Docker Compose"

# ── Defaults ──
DEF_REPO_URL="https://github.com/IdomyownGPT/28BotsTST.git"
DEF_REPO_DIR="$HOME/28BotsTST"
DEF_HOST_IP="192.168.178.90"
DEF_LM_PORT="1234"
DEF_VAULT_MOUNT="/mnt/28bots_core"

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
# 4. Git repository
# ═══════════════════════════════════════════════════════════════

header "Git Repository"

REPO_DIR="$DEF_REPO_DIR"
if [[ -d "$REPO_DIR/.git" ]]; then
    BRANCH=$(git -C "$REPO_DIR" branch --show-current 2>/dev/null || echo "unknown")
    LAST_COMMIT=$(git -C "$REPO_DIR" log -1 --format="%h %s" 2>/dev/null || echo "unknown")
    found "Repo exists at $REPO_DIR"
    info "Branch: $BRANCH"
    info "Latest: $LAST_COMMIT"

    REPO_ACTION=$(ask_choice "What to do with the repo?" \
        "Keep as-is" \
        "Pull latest changes" \
        "Re-clone (fresh)")

    case "$REPO_ACTION" in
        "Pull latest changes")
            info "Pulling latest..."
            git -C "$REPO_DIR" pull && ok "Repo updated" || warn "Pull failed"
            ;;
        "Re-clone (fresh)")
            if ask_yn "Delete $REPO_DIR and re-clone? (DESTRUCTIVE)"; then
                rm -rf "$REPO_DIR"
                git clone "$DEF_REPO_URL" "$REPO_DIR"
                ok "Repo re-cloned"
            else
                skip "Re-clone"
            fi
            ;;
        *)
            ok "Keeping repo as-is"
            ;;
    esac
else
    warn "No repo found at $REPO_DIR"
    REPO_DIR=$(ask_input "Clone repo to" "$DEF_REPO_DIR")
    REPO_URL=$(ask_input "Repository URL" "$DEF_REPO_URL")

    if ask_yn "Clone $REPO_URL to $REPO_DIR?"; then
        git clone "$REPO_URL" "$REPO_DIR"
        ok "Repository cloned"
    else
        fail "Cannot deploy containers without the repo"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 5. Environment file (.env)
# ═══════════════════════════════════════════════════════════════

header "Environment Configuration"
cd "$REPO_DIR"

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
cd "$REPO_DIR"

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
    EXPECTED=9  # Total containers in docker-compose.yml

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
info "Repo:       $REPO_DIR"
info "Vault:      $DEF_VAULT_MOUNT"
info "LM Studio:  http://$HOST_IP:$LM_PORT/v1"
echo ""
print_summary
