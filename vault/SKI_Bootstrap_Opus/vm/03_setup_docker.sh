#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — 03_setup_docker.sh — Interactive Docker installation
#
# Configures: Docker Engine, Docker Compose, user group
#
# Philosophy: CHECK → REPORT → ASK → ACT → VERIFY
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_lib.sh"

require_root

show_banner "Docker Installation" "Docker Engine, Compose plugin, user group membership"

# ── Detect target user ──
TARGET_USER="${SUDO_USER:-archat}"
if ! check_user_exists "$TARGET_USER"; then
    TARGET_USER=$(ask_input "Docker user (will be added to docker group)" "archat")
fi
info "Target user: $TARGET_USER"

# ═══════════════════════════════════════════════════════════════
# 1. Docker Engine
# ═══════════════════════════════════════════════════════════════

header "Docker Engine"

DOCKER_INSTALLED=false
if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null)
    ok "Docker installed: $DOCKER_VER"
    DOCKER_INSTALLED=true
else
    warn "Docker is not installed"
fi

if [[ "$DOCKER_INSTALLED" == "false" ]]; then
    if ask_yn "Install Docker Engine?"; then

        # Check for old versions
        OLD_PKGS=(docker docker-engine docker.io containerd runc)
        OLD_FOUND=()
        for pkg in "${OLD_PKGS[@]}"; do
            if check_pkg_installed "$pkg"; then
                OLD_FOUND+=("$pkg")
            fi
        done

        if [[ ${#OLD_FOUND[@]} -gt 0 ]]; then
            warn "Old Docker packages found: ${OLD_FOUND[*]}"
            if ask_yn "Remove old packages first?"; then
                apt-get remove -y "${OLD_FOUND[@]}" 2>/dev/null || true
                ok "Old packages removed"
            fi
        fi

        info "Installing Docker prerequisites..."
        apt-get update -qq
        apt-get install -y ca-certificates curl gnupg lsb-release

        # Docker GPG key
        info "Adding Docker GPG key..."
        install -m 0755 -d /etc/apt/keyrings
        if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            ok "Docker GPG key added"
        else
            ok "Docker GPG key already present"
        fi

        # Docker repository
        DISTRO_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
        info "Detected distro: Ubuntu $DISTRO_CODENAME"

        DOCKER_REPO="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${DISTRO_CODENAME} stable"

        if grep -q "download.docker.com" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
            ok "Docker repository already configured"
        else
            echo "$DOCKER_REPO" > /etc/apt/sources.list.d/docker.list
            ok "Docker repository added"
        fi

        info "Installing Docker Engine..."
        apt-get update -qq
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        DOCKER_VER=$(docker --version 2>/dev/null)
        ok "Docker installed: $DOCKER_VER"
        DOCKER_INSTALLED=true
    else
        skip "Docker installation"
    fi
else
    # Docker exists — check for updates
    if ask_yn "Docker is already installed. Check for updates?" "N"; then
        apt-get update -qq
        if apt list --upgradable 2>/dev/null | grep -q docker; then
            warn "Docker update available"
            if ask_yn "Upgrade Docker?"; then
                apt-get install -y --only-upgrade docker-ce docker-ce-cli containerd.io
                ok "Docker upgraded"
            else
                skip "Docker upgrade"
            fi
        else
            ok "Docker is up to date"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 2. Docker Service
# ═══════════════════════════════════════════════════════════════

header "Docker Service"
if [[ "$DOCKER_INSTALLED" == "true" ]]; then
    if check_service_running docker; then
        ok "Docker daemon is running"
    else
        warn "Docker daemon is not running"
        if ask_yn "Start and enable Docker?"; then
            systemctl enable --now docker
            ok "Docker started and enabled"
        else
            skip "Docker service start"
        fi
    fi

    # Auto-start on boot
    if systemctl is-enabled docker &>/dev/null; then
        ok "Docker enabled on boot"
    else
        if ask_yn "Enable Docker to start on boot?"; then
            systemctl enable docker
            ok "Docker enabled on boot"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 3. Docker Compose
# ═══════════════════════════════════════════════════════════════

header "Docker Compose"
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    COMPOSE_VER=$(docker compose version --short 2>/dev/null)
    ok "Docker Compose installed: v$COMPOSE_VER"
else
    warn "Docker Compose plugin not found"
    if ask_yn "Install Docker Compose plugin?"; then
        apt-get install -y docker-compose-plugin
        COMPOSE_VER=$(docker compose version --short 2>/dev/null)
        ok "Docker Compose installed: v$COMPOSE_VER"
    else
        skip "Docker Compose installation"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 4. Docker Group Membership
# ═══════════════════════════════════════════════════════════════

header "Docker Group — $TARGET_USER"

if id -nG "$TARGET_USER" 2>/dev/null | grep -qw docker; then
    ok "$TARGET_USER is in the docker group"
else
    warn "$TARGET_USER is NOT in the docker group"
    info "Without docker group membership, $TARGET_USER must use 'sudo docker'"

    if ask_yn "Add '$TARGET_USER' to docker group?"; then
        usermod -aG docker "$TARGET_USER"
        ok "$TARGET_USER added to docker group"
        echo ""
        warn "Group change takes effect on NEXT login."
        info "Options:"
        info "  1. Log out and back in"
        info "  2. Run: newgrp docker"
        info "  3. The SKI installer uses 'sg docker' to work around this"
        echo ""
    else
        skip "Docker group membership"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 5. Docker Disk Space
# ═══════════════════════════════════════════════════════════════

header "Disk Space"
DISK_FREE=$(get_disk_free_gb)
info "Free disk space: ${DISK_FREE} GB"

if [[ "$DISK_FREE" -lt 10 ]]; then
    fail "Less than 10GB free — Docker images may not fit"
elif [[ "$DISK_FREE" -lt 20 ]]; then
    warn "Less than 20GB free — consider cleaning up"
else
    ok "Sufficient disk space (${DISK_FREE} GB free)"
fi

# Show Docker disk usage if available
if command -v docker &>/dev/null && check_service_running docker; then
    info "Docker disk usage:"
    docker system df 2>/dev/null | sed 's/^/    /' || true
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

header "Docker Setup Complete"
if command -v docker &>/dev/null; then
    info "Docker:  $(docker --version 2>/dev/null)"
fi
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    info "Compose: v$(docker compose version --short 2>/dev/null)"
fi
info "User:    $TARGET_USER"
info "Group:   $(id -nG "$TARGET_USER" 2>/dev/null | tr ' ' ', ')"
echo ""
print_summary
