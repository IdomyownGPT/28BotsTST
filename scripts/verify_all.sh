#!/usr/bin/env bash
# verify_all.sh — Run all SKI verification scripts and produce a grand summary

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse args before sourcing common.sh (pass-through to sub-scripts)
ARGS=("$@")
QUIET="false"
LOG_FILE=""

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "SKI — System Verification Suite"
            echo ""
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --quiet, -q    Only output failures and warnings"
            echo "  --log FILE     Write output to FILE"
            echo "  --help, -h     Show this help"
            echo ""
            echo "Scripts executed:"
            echo "  1. verify_network.sh    — Network connectivity & ports"
            echo "  2. verify_docker.sh     — Docker containers & resources"
            echo "  3. verify_lm_studio.sh  — LM Studio API & models"
            echo "  4. verify_vault.sh      — Obsidian Vault SMB mount"
            echo ""
            echo "Exit codes:"
            echo "  0  All checks passed (or warnings only)"
            echo "  1  One or more checks failed"
            echo ""
            echo "Environment variables:"
            echo "  SKI_HOST_IP          Host IP (default: 192.168.178.90)"
            echo "  SKI_VM_IP            VM IP (default: 192.168.178.124)"
            echo "  SKI_LM_STUDIO_PORT   LM Studio port (default: 1234)"
            echo "  SKI_VAULT_MOUNT      Vault mount path (default: /mnt/28bots_core)"
            exit 0
            ;;
        --quiet|-q)
            QUIET="true"
            ;;
        --log)
            # Next arg is the file path — handled below
            ;;
        --log=*)
            LOG_FILE="${arg#--log=}"
            ;;
    esac
done

# Handle --log FILE (two-arg form)
for ((i=0; i<${#ARGS[@]}; i++)); do
    if [ "${ARGS[$i]}" = "--log" ] && [ $((i+1)) -lt ${#ARGS[@]} ]; then
        LOG_FILE="${ARGS[$((i+1))]}"
    fi
done

# ── Header ──
print_header() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   SKI — Sephirotische Kernintelligenz                   ║"
    echo "║   System Verification Suite                             ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Date:     $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Host:     $(hostname 2>/dev/null || echo 'unknown')"
    echo "  User:     $(whoami 2>/dev/null || echo 'unknown')"
    echo "  Kernel:   $(uname -r 2>/dev/null || echo 'unknown')"
    echo ""
}

# ── Run a sub-script and capture exit code ──
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_WARN=0
SCRIPT_RESULTS=()

run_script() {
    local name="$1"
    local script="$SCRIPT_DIR/$name"

    if [ ! -x "$script" ]; then
        echo "  [SKIP] $name — not found or not executable"
        SCRIPT_RESULTS+=("SKIP:$name")
        return
    fi

    echo ""
    echo "┌──────────────────────────────────────────────────────────┐"
    echo "│  Running: $name"
    echo "└──────────────────────────────────────────────────────────┘"

    set +e
    bash "$script" "${ARGS[@]}"
    EXIT_CODE=$?
    set -e

    case $EXIT_CODE in
        0) SCRIPT_RESULTS+=("PASS:$name") ;;
        1) SCRIPT_RESULTS+=("FAIL:$name"); TOTAL_FAIL=$((TOTAL_FAIL + 1)) ;;
        *) SCRIPT_RESULTS+=("WARN:$name"); TOTAL_WARN=$((TOTAL_WARN + 1)) ;;
    esac
}

# ── Main ──
main() {
    print_header

    run_script "verify_network.sh"
    run_script "verify_docker.sh"
    run_script "verify_lm_studio.sh"
    run_script "verify_vault.sh"

    # ── Grand Summary ──
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                   GRAND SUMMARY                         ║"
    echo "╠══════════════════════════════════════════════════════════╣"

    for result in "${SCRIPT_RESULTS[@]}"; do
        status="${result%%:*}"
        script="${result##*:}"
        case "$status" in
            PASS) printf "║  ✅ %-50s  ║\n" "$script" ;;
            FAIL) printf "║  ❌ %-50s  ║\n" "$script" ;;
            WARN) printf "║  ⚠️  %-50s  ║\n" "$script" ;;
            SKIP) printf "║  ⏭️  %-50s  ║\n" "$script" ;;
        esac
    done

    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    if [ "$TOTAL_FAIL" -gt 0 ]; then
        echo "  Result: ❌ FAILURES DETECTED"
        return 1
    elif [ "$TOTAL_WARN" -gt 0 ]; then
        echo "  Result: ⚠️  WARNINGS (review recommended)"
        return 0
    else
        echo "  Result: ✅ ALL SYSTEMS OPERATIONAL"
        return 0
    fi
}

# ── Execute ──
if [ -n "$LOG_FILE" ]; then
    main 2>&1 | tee "$LOG_FILE"
else
    main
fi
