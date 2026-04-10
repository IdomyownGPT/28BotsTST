#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — 02_setup_smb_mount.sh — Interactive SMB vault mount
#
# Configures: SMB credentials, fstab entry, vault mount
#
# Philosophy: CHECK → REPORT → ASK → ACT → VERIFY
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_lib.sh"

require_root

show_banner "SMB Vault Mount" "Connect Obsidian Vault from Windows host via SMB/CIFS"

# ── Defaults ──
DEF_HOST_IP="192.168.178.90"
DEF_SHARE_NAME="SKI-Vault-Root"
DEF_MOUNT_POINT="/mnt/28bots_core"
DEF_SMB_USER="skiuser"
CRED_FILE="/etc/smbcredentials"

# ═══════════════════════════════════════════════════════════════
# 1. Check cifs-utils
# ═══════════════════════════════════════════════════════════════

header "Prerequisites"
if check_pkg_installed cifs-utils; then
    ok "cifs-utils is installed"
else
    warn "cifs-utils is not installed (required for SMB mounts)"
    if ask_yn "Install cifs-utils?"; then
        apt-get update -qq && apt-get install -y cifs-utils
        ok "cifs-utils installed"
    else
        fail "Cannot continue without cifs-utils"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 2. Host connectivity
# ═══════════════════════════════════════════════════════════════

header "Host Connectivity"
HOST_IP=$(ask_input "Windows host IP" "$DEF_HOST_IP")

info "Pinging $HOST_IP..."
if ping -c1 -W3 "$HOST_IP" &>/dev/null; then
    ok "Host $HOST_IP is reachable"
else
    warn "Host $HOST_IP is NOT reachable"
    if ! ask_yn "Continue anyway? (host may come online later)"; then
        fail "Host unreachable, aborting"
        exit 1
    fi
fi

# Check SMB port
if check_port_open "$HOST_IP" 445; then
    ok "SMB port 445 is open on $HOST_IP"
else
    warn "SMB port 445 is NOT open on $HOST_IP"
    info "Ensure Windows Firewall allows SMB from this VM"
fi

# ═══════════════════════════════════════════════════════════════
# 3. Mount point
# ═══════════════════════════════════════════════════════════════

header "Mount Point"

# Show what's under /mnt/
info "Existing directories under /mnt/:"
ls -1d /mnt/*/ 2>/dev/null | sed 's/^/    /' || info "  (empty)"

MOUNT_POINT="$DEF_MOUNT_POINT"
if check_dir_exists "$DEF_MOUNT_POINT"; then
    # Directory exists — check if it's already a mount
    if check_mount_active "$DEF_MOUNT_POINT"; then
        MOUNT_SRC=$(findmnt -n -o SOURCE "$DEF_MOUNT_POINT" 2>/dev/null || echo "unknown")
        ok "Already mounted: $MOUNT_SRC → $DEF_MOUNT_POINT"
        FILE_COUNT=$(find "$DEF_MOUNT_POINT" -maxdepth 2 -type f 2>/dev/null | wc -l)
        info "Files (depth 2): $FILE_COUNT"

        if ! ask_yn "Reconfigure mount?" "N"; then
            skip "Mount reconfiguration — keeping existing mount"
            print_summary
            exit 0
        fi
    fi
    MOUNT_POINT=$(ask_input "Use mount point" "$DEF_MOUNT_POINT")
else
    MOUNT_POINT=$(ask_input "Create mount point at" "$DEF_MOUNT_POINT")
    if ask_yn "Create directory '$MOUNT_POINT'?"; then
        mkdir -p "$MOUNT_POINT"
        created "$MOUNT_POINT"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 4. SMB Credentials
# ═══════════════════════════════════════════════════════════════

header "SMB Credentials"
WRITE_CREDS=false
if [[ -f "$CRED_FILE" ]]; then
    EXISTING_USER=$(grep -oP 'username=\K.*' "$CRED_FILE" 2>/dev/null || echo "unknown")
    found "Credentials file exists at $CRED_FILE (user: $EXISTING_USER)"

    if ask_yn "Keep existing credentials?" "Y"; then
        SMB_USER="$EXISTING_USER"
        skip "Credential update"
    else
        info "Replacing credentials..."
        WRITE_CREDS=true
    fi
else
    info "No credentials file found at $CRED_FILE"
    WRITE_CREDS=true
fi

if [[ "$WRITE_CREDS" == "true" ]]; then
    SMB_USER=$(ask_input "SMB username" "$DEF_SMB_USER")
    SMB_PASS=$(ask_password "SMB password for '$SMB_USER'")

    if [[ -n "$SMB_PASS" ]]; then
        cat > "$CRED_FILE" << EOF
username=$SMB_USER
password=$SMB_PASS
EOF
        chmod 600 "$CRED_FILE"
        ok "Credentials written to $CRED_FILE (chmod 600)"
    else
        fail "Empty password — credentials not written"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 5. Share configuration
# ═══════════════════════════════════════════════════════════════

header "SMB Share"
SHARE_NAME=$(ask_input "Share name" "$DEF_SHARE_NAME")
SHARE_PATH="//${HOST_IP}/${SHARE_NAME}"

# Detect UID/GID of the target user
TARGET_USER="${SUDO_USER:-archat}"
if check_user_exists "$TARGET_USER"; then
    TARGET_UID=$(id -u "$TARGET_USER")
    TARGET_GID=$(id -g "$TARGET_USER")
    info "Mount will use UID=$TARGET_UID, GID=$TARGET_GID ($TARGET_USER)"
else
    TARGET_UID=1000
    TARGET_GID=1000
    warn "User '$TARGET_USER' not found — defaulting to UID=1000, GID=1000"
fi

# ═══════════════════════════════════════════════════════════════
# 6. fstab entry
# ═══════════════════════════════════════════════════════════════

header "fstab Configuration"
FSTAB_LINE="${SHARE_PATH}  ${MOUNT_POINT}  cifs  credentials=${CRED_FILE},_netdev,x-systemd.automount,x-systemd.mount-timeout=30,vers=3.0,uid=${TARGET_UID},gid=${TARGET_GID}  0  0"

if check_fstab_entry "$SHARE_NAME"; then
    EXISTING_ENTRY=$(grep "$SHARE_NAME" /etc/fstab)
    found "Existing fstab entry:"
    echo -e "    ${GRAY}${EXISTING_ENTRY}${NC}"

    if [[ "$EXISTING_ENTRY" == "$FSTAB_LINE" ]]; then
        ok "fstab entry matches desired config"
    else
        warn "fstab entry differs from desired config"
        echo -e "\n  ${CYAN}Proposed:${NC}"
        echo -e "    ${GRAY}${FSTAB_LINE}${NC}"

        if ask_yn "Replace existing fstab entry?"; then
            grep -v "$SHARE_NAME" /etc/fstab > /etc/fstab.tmp
            mv /etc/fstab.tmp /etc/fstab
            echo "$FSTAB_LINE" >> /etc/fstab
            ok "fstab entry replaced"
        else
            skip "fstab update"
        fi
    fi
else
    info "No fstab entry for '$SHARE_NAME'"
    echo -e "\n  ${CYAN}Proposed fstab entry:${NC}"
    echo -e "    ${GRAY}${FSTAB_LINE}${NC}"

    if ask_yn "Add this entry to /etc/fstab?"; then
        cp /etc/fstab "/etc/fstab.bak.$(date +%s)"
        info "Backed up /etc/fstab"
        echo "$FSTAB_LINE" >> /etc/fstab
        ok "fstab entry added"
    else
        skip "fstab entry"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 7. Mount and verify
# ═══════════════════════════════════════════════════════════════

header "Mount Verification"
systemctl daemon-reload 2>/dev/null

if ask_yn "Mount the share now?"; then
    info "Running mount -a..."
    if mount -a 2>&1; then
        if check_mount_active "$MOUNT_POINT"; then
            FILE_COUNT=$(find "$MOUNT_POINT" -maxdepth 2 -type f 2>/dev/null | wc -l)
            ok "Mount successful! ($FILE_COUNT files at depth 2)"

            # Write test
            TEST_FILE="$MOUNT_POINT/.ski_mount_test_$$"
            if touch "$TEST_FILE" 2>/dev/null && rm -f "$TEST_FILE" 2>/dev/null; then
                ok "Read/Write access confirmed"
            else
                warn "Read-only access (write test failed)"
            fi
        else
            fail "Mount command succeeded but mountpoint check failed"
        fi
    else
        fail "mount -a failed — check credentials and host availability"
    fi
else
    skip "Mount (run 'sudo mount -a' manually)"
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

header "SMB Mount Setup Complete"
info "Share:       $SHARE_PATH"
info "Mount point: $MOUNT_POINT"
info "Credentials: $CRED_FILE"
info "Automount:   x-systemd.automount (mounts on first access)"
echo ""
print_summary
