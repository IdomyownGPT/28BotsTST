#!/usr/bin/env bash
# verify_vault.sh — Check Obsidian Vault SMB mount, permissions, and fstab

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
parse_common_args "$@"

section_header "Vault Mount Verification"

VAULT_PATH="$VAULT_MOUNT"
OBSIDIAN_PATH="$VAULT_MOUNT/Obsidian_Vault"

# ── Mount Check ──
section_header "Mount Status"

if mountpoint -q "$VAULT_PATH" 2>/dev/null; then
    log_ok "$VAULT_PATH is a mountpoint"
else
    log_fail "$VAULT_PATH is NOT a mountpoint"
    log_info "Try: sudo mount -a  (or check fstab)"
fi

# Check CIFS/SMB mount details
MOUNT_INFO=$(mount 2>/dev/null | grep -i "$VAULT_PATH" || true)
if [ -n "$MOUNT_INFO" ]; then
    log_ok "CIFS mount found: $MOUNT_INFO"

    # Check mount options
    if echo "$MOUNT_INFO" | grep -q "_netdev"; then
        log_ok "Mount option _netdev is set"
    else
        log_warn "Mount option _netdev is missing (needed for boot reliability)"
    fi
else
    log_fail "No CIFS mount found for $VAULT_PATH"
fi

# ── fstab Entry ──
section_header "fstab Configuration"

if [ -f /etc/fstab ]; then
    FSTAB_ENTRY=$(grep -i "ski-vault\|28bots" /etc/fstab 2>/dev/null | grep -v "^#" || true)
    if [ -n "$FSTAB_ENTRY" ]; then
        log_ok "fstab entry found"
        log_info "$FSTAB_ENTRY"

        # Check recommended options
        if echo "$FSTAB_ENTRY" | grep -q "_netdev"; then
            log_ok "fstab has _netdev option"
        else
            log_warn "fstab missing _netdev (mount may fail before network is up)"
        fi

        if echo "$FSTAB_ENTRY" | grep -q "x-systemd.automount"; then
            log_ok "fstab has x-systemd.automount (recommended)"
        else
            log_warn "fstab missing x-systemd.automount (recommended for reliability)"
            log_info "Recommended fstab options: _netdev,x-systemd.automount,x-systemd.mount-timeout=30"
        fi

        if echo "$FSTAB_ENTRY" | grep -q "credentials="; then
            log_ok "Credentials file referenced in fstab (secure)"
        elif echo "$FSTAB_ENTRY" | grep -q "password="; then
            log_warn "Password inline in fstab — use credentials file instead"
            log_info "Create /etc/smbcredentials with chmod 600"
        fi
    else
        log_fail "No fstab entry found for SKI Vault"
        log_info "Expected: //<host>/SKI-Vault-Root  $VAULT_PATH  cifs  credentials=/etc/smbcredentials,_netdev,x-systemd.automount,vers=3.0  0  0"
    fi
else
    log_warn "/etc/fstab not found"
fi

# ── Read Access ──
section_header "Read Access"

if [ -d "$OBSIDIAN_PATH" ]; then
    log_ok "Obsidian Vault directory exists: $OBSIDIAN_PATH"

    FILE_COUNT=$(find "$OBSIDIAN_PATH" -maxdepth 2 -type f 2>/dev/null | wc -l)
    log_info "Files found (depth 2): $FILE_COUNT"

    # Check for expected directories
    for dir in "SKI_Cookbook" "SKI_Bootstrap" "SKI_Pilot"; do
        if [ -d "$OBSIDIAN_PATH/root/$dir" ] || [ -d "$OBSIDIAN_PATH/$dir" ]; then
            log_ok "Directory '$dir' found"
        else
            log_warn "Directory '$dir' not found in vault"
        fi
    done
else
    log_fail "Obsidian Vault directory not accessible: $OBSIDIAN_PATH"
fi

# ── Write Access ──
section_header "Write Access"

TESTFILE="$OBSIDIAN_PATH/.ski_verify_test_$(date +%s)"
if touch "$TESTFILE" 2>/dev/null; then
    log_ok "Write access confirmed"
    rm -f "$TESTFILE" 2>/dev/null
    log_ok "Delete access confirmed"
else
    log_fail "Cannot write to $OBSIDIAN_PATH"
    log_info "Check SMB user permissions (skiuser / archat)"
fi

# ── Read Latency ──
section_header "Read Latency"

if [ -d "$OBSIDIAN_PATH" ]; then
    FIRST_FILE=$(find "$OBSIDIAN_PATH" -maxdepth 3 -name "*.md" -type f 2>/dev/null | head -1)
    if [ -n "$FIRST_FILE" ]; then
        START_TIME=$(date +%s%N)
        cat "$FIRST_FILE" > /dev/null 2>&1
        END_TIME=$(date +%s%N)
        LATENCY_MS=$(( (END_TIME - START_TIME) / 1000000 ))
        if [ "$LATENCY_MS" -lt 100 ]; then
            log_ok "Read latency: ${LATENCY_MS}ms (excellent)"
        elif [ "$LATENCY_MS" -lt 500 ]; then
            log_ok "Read latency: ${LATENCY_MS}ms (good)"
        else
            log_warn "Read latency: ${LATENCY_MS}ms (slow — check network)"
        fi
    else
        log_skip "No .md files found for latency test"
    fi
fi

# ── Summary ──
print_summary "Vault"
