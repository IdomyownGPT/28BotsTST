#!/usr/bin/env bash
# common.sh — Shared functions for SKI verification scripts
# Source this file: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Counters ──
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

# ── Configuration ──
HOST_IP="${SKI_HOST_IP:-192.168.178.90}"
VM_IP="${SKI_VM_IP:-192.168.178.124}"
LM_STUDIO_PORT="${SKI_LM_STUDIO_PORT:-1234}"
LM_STUDIO_URL="http://${HOST_IP}:${LM_STUDIO_PORT}"
VAULT_MOUNT="${SKI_VAULT_MOUNT:-/mnt/28bots_core}"
QUIET="${QUIET:-false}"

# ── Logging ──
log_ok() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "${GREEN}  [PASS]${NC} %s\n" "$*"
}

log_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "${RED}  [FAIL]${NC} %s\n" "$*"
}

log_warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    printf "${YELLOW}  [WARN]${NC} %s\n" "$*"
}

log_skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    printf "${BLUE}  [SKIP]${NC} %s\n" "$*"
}

log_info() {
    printf "${CYAN}  [INFO]${NC} %s\n" "$*"
}

section_header() {
    printf "\n${BOLD}━━━ %s ━━━${NC}\n" "$*"
}

# ── Summary ──
print_summary() {
    local label="${1:-Verification}"
    printf "\n${BOLD}═══ %s Summary ═══${NC}\n" "$label"
    printf "${GREEN}  PASS: %d${NC}\n" "$PASS_COUNT"
    [ "$FAIL_COUNT" -gt 0 ] && printf "${RED}  FAIL: %d${NC}\n" "$FAIL_COUNT"
    [ "$WARN_COUNT" -gt 0 ] && printf "${YELLOW}  WARN: %d${NC}\n" "$WARN_COUNT"
    [ "$SKIP_COUNT" -gt 0 ] && printf "${BLUE}  SKIP: %d${NC}\n" "$SKIP_COUNT"
    printf "  Total: %d checks\n" "$((PASS_COUNT + FAIL_COUNT + WARN_COUNT + SKIP_COUNT))"

    if [ "$FAIL_COUNT" -gt 0 ]; then
        printf "${RED}  Result: FAILED${NC}\n"
        return 1
    elif [ "$WARN_COUNT" -gt 0 ]; then
        printf "${YELLOW}  Result: WARNINGS${NC}\n"
        return 0
    else
        printf "${GREEN}  Result: ALL PASSED${NC}\n"
        return 0
    fi
}

# ── Utilities ──
check_command() {
    if command -v "$1" &>/dev/null; then
        return 0
    else
        log_fail "Required command not found: $1"
        return 1
    fi
}

# Test TCP connectivity (returns 0 if port is open)
test_port() {
    local host="$1" port="$2" timeout="${3:-3}"
    if command -v nc &>/dev/null; then
        nc -z -w "$timeout" "$host" "$port" 2>/dev/null
    elif command -v timeout &>/dev/null; then
        timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
    else
        bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
    fi
}

# Parse --help and --quiet flags
parse_common_args() {
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                echo "Usage: $(basename "$0") [--quiet] [--help]"
                echo ""
                echo "Options:"
                echo "  --quiet   Only output failures and warnings (for cron)"
                echo "  --help    Show this help message"
                exit 0
                ;;
            --quiet|-q)
                QUIET="true"
                ;;
        esac
    done
}
