#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — 01_setup_base.sh — Interactive base system setup
#
# Configures: user, hostname, timezone, static IP, packages,
#             SSH server, Hyper-V integration (linux-azure)
#
# Philosophy: CHECK → REPORT → ASK → ACT → VERIFY
# Nothing happens without the user's explicit consent.
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_lib.sh"

require_root

show_banner "Base System Setup" "User, hostname, timezone, network, packages, Hyper-V"

# ── Defaults (user can override every one) ──
DEF_USER="archat"
DEF_HOSTNAME="28bots-orchestrator"
DEF_TIMEZONE="Europe/Berlin"
DEF_IP="192.168.178.124"
DEF_GATEWAY="192.168.178.1"
DEF_DNS="192.168.178.1"

# ═══════════════════════════════════════════════════════════════
# 1. System Info
# ═══════════════════════════════════════════════════════════════

header "Current System State"
info "Hostname:  $(get_current_hostname)"
info "Kernel:    $(get_current_kernel)"
info "Timezone:  $(get_current_timezone)"
info "IP:        $(get_current_ip)"
info "RAM:       $(get_ram_gb) GB"
info "Disk free: $(get_disk_free_gb) GB"
info "User:      $(whoami) (UID $EUID)"

# ═══════════════════════════════════════════════════════════════
# 2. User Provisioning
# ═══════════════════════════════════════════════════════════════

header "User Provisioning"

TARGET_USER="$DEF_USER"
if check_user_exists "$DEF_USER"; then
    local_uid=$(id -u "$DEF_USER")
    local_groups=$(id -Gn "$DEF_USER" | tr ' ' ', ')
    ok "User '$DEF_USER' exists (UID $local_uid, groups: $local_groups)"
    TARGET_USER="$DEF_USER"
else
    warn "User '$DEF_USER' does not exist"
    TARGET_USER=$(ask_input "Create user with name" "$DEF_USER")

    if check_user_exists "$TARGET_USER"; then
        ok "User '$TARGET_USER' already exists"
    elif ask_yn "Create user '$TARGET_USER' with sudo privileges?"; then
        useradd -m -s /bin/bash -G sudo "$TARGET_USER"
        echo "  Set password for $TARGET_USER:"
        passwd "$TARGET_USER"
        ok "User '$TARGET_USER' created with sudo"
    else
        skip "User creation skipped"
    fi
fi

# SSH key setup
header "SSH Key Setup"
USER_HOME=$(eval echo "~$TARGET_USER")
SSH_DIR="$USER_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

if [[ -f "$AUTH_KEYS" ]]; then
    KEY_COUNT=$(wc -l < "$AUTH_KEYS")
    ok "$KEY_COUNT authorized SSH key(s) found in $AUTH_KEYS"
else
    warn "No authorized_keys file found for $TARGET_USER"
fi

if ask_yn "Add an SSH public key for $TARGET_USER?" "N"; then
    echo -e "  ${GRAY}Paste the public key (one line), then press Enter:${NC}"
    echo -n "  > "
    read -r pubkey
    if [[ -n "$pubkey" ]]; then
        mkdir -p "$SSH_DIR"
        echo "$pubkey" >> "$AUTH_KEYS"
        chown -R "$TARGET_USER:$TARGET_USER" "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        chmod 600 "$AUTH_KEYS"
        ok "Key added to $AUTH_KEYS"
    else
        skip "Empty key, nothing added"
    fi
else
    skip "SSH key setup"
fi

# ═══════════════════════════════════════════════════════════════
# 3. Hostname
# ═══════════════════════════════════════════════════════════════

header "Hostname"
CURRENT_HOSTNAME=$(get_current_hostname)
info "Current hostname: $CURRENT_HOSTNAME"

if [[ "$CURRENT_HOSTNAME" == "$DEF_HOSTNAME" ]]; then
    ok "Hostname already set to '$DEF_HOSTNAME'"
else
    NEW_HOSTNAME=$(ask_input "Set hostname to" "$DEF_HOSTNAME")
    if [[ "$NEW_HOSTNAME" != "$CURRENT_HOSTNAME" ]]; then
        if ask_yn "Change hostname from '$CURRENT_HOSTNAME' to '$NEW_HOSTNAME'?"; then
            hostnamectl set-hostname "$NEW_HOSTNAME"
            # Update /etc/hosts
            if grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
                sed -i "s/$CURRENT_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
            fi
            ok "Hostname set to '$NEW_HOSTNAME'"
        else
            skip "Hostname change"
        fi
    else
        ok "Hostname unchanged"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 4. Timezone
# ═══════════════════════════════════════════════════════════════

header "Timezone"
CURRENT_TZ=$(get_current_timezone)
info "Current timezone: $CURRENT_TZ"

if [[ "$CURRENT_TZ" == "$DEF_TIMEZONE" ]]; then
    ok "Timezone already set to '$DEF_TIMEZONE'"
else
    NEW_TZ=$(ask_input "Set timezone to" "$DEF_TIMEZONE")
    if [[ "$NEW_TZ" != "$CURRENT_TZ" ]]; then
        if ask_yn "Change timezone from '$CURRENT_TZ' to '$NEW_TZ'?"; then
            timedatectl set-timezone "$NEW_TZ"
            ok "Timezone set to '$NEW_TZ'"
        else
            skip "Timezone change"
        fi
    else
        ok "Timezone unchanged"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 5. Static IP (Netplan)
# ═══════════════════════════════════════════════════════════════

header "Network — Static IP"
CURRENT_IP=$(get_current_ip)
info "Current IP: $CURRENT_IP"

# Detect netplan config
NETPLAN_FILE=""
for ext in yaml yml; do
    if ls /etc/netplan/*."$ext" &>/dev/null; then
        NETPLAN_FILE=$(ls /etc/netplan/*."$ext" | head -1)
        break
    fi
done

if [[ -n "$NETPLAN_FILE" ]]; then
    info "Netplan config: $NETPLAN_FILE"
    echo -e "  ${GRAY}--- Current netplan ---${NC}"
    sed 's/^/  /' "$NETPLAN_FILE"
    echo -e "  ${GRAY}----------------------${NC}"
fi

CONFIGURE_NET=false
if [[ "$CURRENT_IP" == "$DEF_IP" ]]; then
    ok "IP already matches default ($DEF_IP)"
    if ask_yn "Reconfigure network anyway?" "N"; then
        CONFIGURE_NET=true
    else
        skip "Network reconfiguration"
    fi
else
    if ask_yn "Configure static IP? (currently $CURRENT_IP)"; then
        CONFIGURE_NET=true
    else
        skip "Static IP setup"
    fi
fi

if [[ "$CONFIGURE_NET" == "true" ]]; then
    NEW_IP=$(ask_input "Static IP address" "$DEF_IP")
    NEW_PREFIX=$(ask_input "Subnet prefix length" "24")
    NEW_GW=$(ask_input "Gateway" "$DEF_GATEWAY")
    NEW_DNS=$(ask_input "DNS server" "$DEF_DNS")

    # Detect the primary network interface
    PRIMARY_IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1)
    if [[ -z "$PRIMARY_IF" ]]; then
        PRIMARY_IF=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v lo | head -1)
    fi
    info "Primary interface: $PRIMARY_IF"

    NETPLAN_CONTENT="network:
  version: 2
  ethernets:
    ${PRIMARY_IF}:
      dhcp4: false
      addresses:
        - ${NEW_IP}/${NEW_PREFIX}
      routes:
        - to: default
          via: ${NEW_GW}
      nameservers:
        addresses:
          - ${NEW_DNS}
          - 8.8.8.8"

    echo -e "\n  ${GRAY}--- Proposed netplan config ---${NC}"
    echo "$NETPLAN_CONTENT" | sed 's/^/  /'
    echo -e "  ${GRAY}-------------------------------${NC}"

    if ask_yn "Write this netplan config?"; then
        NETPLAN_TARGET="${NETPLAN_FILE:-/etc/netplan/01-ski-static.yaml}"
        # Backup existing
        if [[ -f "$NETPLAN_TARGET" ]]; then
            cp "$NETPLAN_TARGET" "${NETPLAN_TARGET}.bak.$(date +%s)"
            info "Backed up existing config"
        fi
        echo "$NETPLAN_CONTENT" > "$NETPLAN_TARGET"
        chmod 600 "$NETPLAN_TARGET"
        ok "Netplan config written to $NETPLAN_TARGET"

        if ask_yn "Apply netplan now? (WARNING: may disconnect SSH)"; then
            netplan apply
            ok "Netplan applied"
        else
            warn "Config written but NOT applied. Run 'sudo netplan apply' manually."
        fi
    else
        skip "Netplan config"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 6. SSH Server
# ═══════════════════════════════════════════════════════════════

header "SSH Server"
if check_service_running ssh; then
    ok "SSH server is running"
else
    if check_pkg_installed openssh-server; then
        warn "openssh-server installed but not running"
        if ask_yn "Start and enable SSH server?"; then
            systemctl enable --now ssh
            ok "SSH server started and enabled"
        else
            skip "SSH server start"
        fi
    else
        warn "openssh-server not installed"
        if ask_yn "Install and enable SSH server?"; then
            apt-get install -y openssh-server
            systemctl enable --now ssh
            ok "SSH server installed and enabled"
        else
            skip "SSH server installation"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 7. System Packages
# ═══════════════════════════════════════════════════════════════

header "System Packages"

REQUIRED_PKGS=(
    curl wget jq git htop net-tools netcat-openbsd
    cifs-utils ca-certificates gnupg lsb-release
    unzip vim tmux
)

INSTALLED=()
MISSING=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if check_pkg_installed "$pkg"; then
        INSTALLED+=("$pkg")
    else
        MISSING+=("$pkg")
    fi
done

ok "Installed (${#INSTALLED[@]}): ${INSTALLED[*]}"
if [[ ${#MISSING[@]} -gt 0 ]]; then
    warn "Missing (${#MISSING[@]}): ${MISSING[*]}"
    if ask_yn "Install missing packages?"; then
        apt-get update -qq
        apt-get install -y "${MISSING[@]}"
        ok "Packages installed"
    else
        skip "Package installation"
    fi
else
    ok "All required packages present"
fi

# ═══════════════════════════════════════════════════════════════
# 8. System Update
# ═══════════════════════════════════════════════════════════════

header "System Updates"
apt-get update -qq 2>/dev/null
UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
info "$UPGRADABLE package(s) can be upgraded"

if [[ "$UPGRADABLE" -gt 0 ]]; then
    if ask_yn "Run apt upgrade ($UPGRADABLE packages)?"; then
        apt-get upgrade -y
        ok "System upgraded"
    else
        skip "System upgrade"
    fi
else
    ok "System is up to date"
fi

# ═══════════════════════════════════════════════════════════════
# 9. Hyper-V Integration (linux-azure)
# ═══════════════════════════════════════════════════════════════

header "Hyper-V Integration"
KERNEL=$(get_current_kernel)
info "Running kernel: $KERNEL"

AZURE_INSTALLED=()
AZURE_MISSING=()

for pkg in linux-azure linux-tools-azure linux-cloud-tools-azure; do
    if check_pkg_installed "$pkg"; then
        AZURE_INSTALLED+=("$pkg")
    else
        AZURE_MISSING+=("$pkg")
    fi
done

if [[ ${#AZURE_MISSING[@]} -eq 0 ]]; then
    ok "All Hyper-V packages installed: ${AZURE_INSTALLED[*]}"
elif [[ "$KERNEL" == *azure* ]]; then
    ok "Azure kernel detected ($KERNEL)"
    if [[ ${#AZURE_MISSING[@]} -gt 0 ]]; then
        info "Additional tools available: ${AZURE_MISSING[*]}"
        if ask_yn "Install Hyper-V tools (${AZURE_MISSING[*]})?"; then
            apt-get install -y "${AZURE_MISSING[@]}"
            ok "Hyper-V tools installed"
        else
            skip "Hyper-V tools"
        fi
    fi
else
    warn "Not running Azure kernel — Hyper-V guest features may be limited"
    info "Available packages: linux-azure linux-tools-azure linux-cloud-tools-azure"
    if ask_yn "Install linux-azure packages? (may require reboot)"; then
        apt-get install -y linux-azure linux-tools-azure linux-cloud-tools-azure
        ok "Hyper-V packages installed"
        warn "Reboot recommended to use the Azure kernel"
    else
        skip "Hyper-V packages"
    fi
fi

# ── Create vault mount point ──
header "Vault Mount Point"
DEF_VAULT_MOUNT="/mnt/28bots_core"
if check_dir_exists "$DEF_VAULT_MOUNT"; then
    ok "Mount point exists"
else
    VAULT_MOUNT=$(ask_input "Create mount point at" "$DEF_VAULT_MOUNT")
    if ask_yn "Create directory '$VAULT_MOUNT'?"; then
        mkdir -p "$VAULT_MOUNT"
        created "$VAULT_MOUNT"
    else
        skip "Mount point creation"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

header "Base Setup Complete"
info "Hostname:  $(get_current_hostname)"
info "Timezone:  $(get_current_timezone)"
info "IP:        $(get_current_ip)"
info "Kernel:    $(get_current_kernel)"
info "User:      $TARGET_USER"
echo ""
print_summary
