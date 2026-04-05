#!/usr/bin/env bash
# SKI Bootstrap — VM Step 5: Configure Hermes profiles
# Run as the regular user (archat)

set -euo pipefail

echo ""
echo "=== SKI Bootstrap: Hermes Profile Setup ==="
echo ""

# Check if Hermes is installed
if command -v hermes &>/dev/null; then
    HERMES_VER=$(hermes --version 2>/dev/null || echo "unknown")
    echo "[OK] Hermes is installed: $HERMES_VER"
else
    echo "[INFO] Hermes CLI not found in PATH."
    echo "  If Hermes runs inside a Docker container, this is expected."
    echo "  Otherwise, install Hermes v0.7.0 following the Hermes documentation."
    echo ""
fi

# Define the 3x3 profile matrix
PROFILES=(
    "kether-alpha"
    "kether-beta"
    "kether-gamma"
    "tiferet-alpha"
    "tiferet-beta"
    "tiferet-gamma"
    "malkuth-alpha"
    "malkuth-beta"
    "malkuth-gamma"
)

DEFAULT_PROFILE="tiferet-beta"

echo "--- Profile Matrix ---"
echo ""
echo "  Sephirah       | alpha (Gen) | beta (Orch) | gamma (Exec)"
echo "  ────────────────┼─────────────┼─────────────┼─────────────"
echo "  Kether (Crown)  | kether-a    | kether-b    | kether-g"
echo "  Tiferet (Beauty)| tiferet-a   | tiferet-b * | tiferet-g"
echo "  Malkuth (Kingdom)| malkuth-a  | malkuth-b   | malkuth-g"
echo ""
echo "  * = Default profile: $DEFAULT_PROFILE"
echo ""

# If Hermes is available, list/create profiles
if command -v hermes &>/dev/null; then
    echo "--- Existing Profiles ---"
    hermes profiles list 2>/dev/null || echo "  (No profiles or command not supported)"

    echo ""
    echo "--- Creating/Verifying Profiles ---"
    for profile in "${PROFILES[@]}"; do
        if hermes profiles list 2>/dev/null | grep -q "$profile"; then
            echo "[OK] Profile '$profile' exists"
        else
            echo "[INFO] Profile '$profile' needs to be created"
            echo "  Create with: hermes profiles create $profile"
        fi
    done

    echo ""
    echo "--- Testing Default Profile ---"
    echo "  Running: hermes -p $DEFAULT_PROFILE chat (with test prompt)"
    echo 'Reply with OK' | timeout 30 hermes -p "$DEFAULT_PROFILE" chat 2>/dev/null && \
        echo "[OK] Default profile responds" || \
        echo "[WARN] Default profile test failed or timed out"
else
    echo "--- Docker-based Hermes ---"
    HERMES_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i hermes | head -1)
    if [ -n "$HERMES_CONTAINER" ]; then
        echo "[OK] Hermes container running: $HERMES_CONTAINER"
        echo "  Access: docker exec -it $HERMES_CONTAINER hermes -p $DEFAULT_PROFILE chat"
    else
        echo "[WARN] No Hermes container found running"
    fi
fi

echo ""
echo "[DONE] Hermes profile setup complete."
echo "Next: Run 06_verify_vm.sh"
