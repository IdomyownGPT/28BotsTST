#!/usr/bin/env bash
# SKI Bootstrap — VM Step 2: Configure SMB mount for Obsidian Vault
# Run as root or with sudo

set -euo pipefail

echo ""
echo "=== SKI Bootstrap: SMB Mount Setup ==="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "[WARN] Not running as root. Retrying with sudo..."
    exec sudo bash "$0" "$@"
fi

HOST_IP="192.168.178.90"
SHARE_NAME="SKI-Vault-Root"
MOUNT_POINT="/mnt/28bots_core"
CRED_FILE="/etc/smbcredentials"
FSTAB_ENTRY="//${HOST_IP}/${SHARE_NAME}  ${MOUNT_POINT}  cifs  credentials=${CRED_FILE},_netdev,x-systemd.automount,x-systemd.mount-timeout=30,vers=3.0,uid=1000,gid=1000  0  0"

# Install cifs-utils if missing
if ! command -v mount.cifs &>/dev/null; then
    echo "Installing cifs-utils..."
    apt install -y cifs-utils
fi

# Create credentials file
echo "--- SMB Credentials ---"
if [ -f "$CRED_FILE" ]; then
    echo "[OK] Credentials file exists: $CRED_FILE"
    echo "  (To update: sudo nano $CRED_FILE)"
else
    echo "Creating credentials file..."
    read -rp "  SMB username [skiuser]: " SMB_USER
    SMB_USER="${SMB_USER:-skiuser}"
    read -rsp "  SMB password: " SMB_PASS
    echo ""

    cat > "$CRED_FILE" << EOF
username=${SMB_USER}
password=${SMB_PASS}
EOF
    chmod 600 "$CRED_FILE"
    echo "[CREATED] $CRED_FILE (chmod 600)"
fi

# Create mount point
mkdir -p "$MOUNT_POINT"

# Add fstab entry
echo ""
echo "--- fstab Configuration ---"
if grep -q "$SHARE_NAME" /etc/fstab 2>/dev/null; then
    echo "[OK] fstab entry already exists"
    grep "$SHARE_NAME" /etc/fstab
else
    echo "Adding fstab entry..."
    cp /etc/fstab /etc/fstab.bak.$(date +%s)
    echo "" >> /etc/fstab
    echo "# SKI Obsidian Vault SMB Mount" >> /etc/fstab
    echo "$FSTAB_ENTRY" >> /etc/fstab
    echo "[CREATED] fstab entry added"
fi

# Reload systemd and mount
echo ""
echo "--- Mounting ---"
systemctl daemon-reload
mount -a

# Verify
echo ""
echo "--- Verification ---"
if mountpoint -q "$MOUNT_POINT"; then
    echo "[PASS] $MOUNT_POINT is mounted"
    FILE_COUNT=$(find "$MOUNT_POINT" -maxdepth 2 -type f 2>/dev/null | wc -l)
    echo "[INFO] Files found (depth 2): $FILE_COUNT"
else
    echo "[FAIL] $MOUNT_POINT is NOT mounted"
    echo "  Check: Host is reachable, SMB share exists, credentials are correct"
    echo "  Debug: mount -t cifs //${HOST_IP}/${SHARE_NAME} ${MOUNT_POINT} -o credentials=${CRED_FILE},vers=3.0"
fi

echo ""
echo "[DONE] SMB mount setup complete."
echo "Next: Run 03_setup_docker.sh"
