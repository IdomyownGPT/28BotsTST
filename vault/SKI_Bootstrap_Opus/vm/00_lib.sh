#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — 00_lib.sh — Shared library for interactive VM installer
# Source this file from all other scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/00_lib.sh"
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# ── Counters ──
_PASS=0
_FAIL=0
_WARN=0
_SKIP=0

# ── Output ──
header()  { echo -e "\n${CYAN}=== $* ===${NC}"; }
info()    { echo -e "  ${GRAY}[INFO]${NC}  $*"; }
ok()      { echo -e "  ${GREEN}[OK]${NC}    $*"; _PASS=$((_PASS + 1)); }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}  $*"; _WARN=$((_WARN + 1)); }
fail()    { echo -e "  ${RED}[FAIL]${NC}  $*"; _FAIL=$((_FAIL + 1)); }
skip()    { echo -e "  ${GRAY}[SKIP]${NC}  $*"; _SKIP=$((_SKIP + 1)); }
created() { echo -e "  ${YELLOW}[CREATED]${NC} $*"; }
found()   { echo -e "  ${BLUE}[FOUND]${NC}  $*"; }

# ── Interactive Prompts ──

# ask_yn "Do something?" "Y"  →  returns 0 for yes, 1 for no
ask_yn() {
    local prompt="$1"
    local default="${2:-Y}"
    local hint
    if [[ "$default" =~ ^[Yy] ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi
    echo -en "  ${BOLD}?${NC} ${prompt} ${hint} "
    read -r answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

# ask_input "Host IP" "192.168.178.90"  →  prints chosen value
ask_input() {
    local prompt="$1"
    local default="$2"
    echo -en "  ${BOLD}?${NC} ${prompt} [${CYAN}${default}${NC}]: " >&2
    read -r answer
    echo "${answer:-$default}"
}

# ask_choice "Pick one" "option1" "option2" "option3"  →  prints chosen value
ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    echo -e "  ${BOLD}?${NC} ${prompt}" >&2
    local i=1
    for opt in "${options[@]}"; do
        echo -e "    ${CYAN}${i})${NC} ${opt}" >&2
        ((i++))
    done
    echo -en "  Choice [1]: " >&2
    read -r choice
    choice="${choice:-1}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        echo "${options[$((choice - 1))]}"
    else
        echo "${options[0]}"
    fi
}

# ask_password "SMB password"  →  prints password (no echo)
ask_password() {
    local prompt="$1"
    echo -en "  ${BOLD}?${NC} ${prompt}: " >&2
    read -rs answer
    echo "" >&2
    echo "$answer"
}

# ── State Checks ──

# check_pkg_installed "curl"  →  returns 0 if installed
check_pkg_installed() {
    dpkg -s "$1" &>/dev/null
}

# check_dir_exists "/mnt/28bots_core"  →  returns 0 if exists, shows contents
check_dir_exists() {
    local path="$1"
    if [[ -d "$path" ]]; then
        local count
        count=$(ls -1A "$path" 2>/dev/null | wc -l)
        found "$path exists ($count items)"
        return 0
    else
        info "$path does not exist"
        return 1
    fi
}

# check_mount_active "/mnt/28bots_core"  →  returns 0 if mounted
check_mount_active() {
    mountpoint -q "$1" 2>/dev/null
}

# check_service_running "ssh"  →  returns 0 if active
check_service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# check_port_open "192.168.178.90" 1234  →  returns 0 if open
check_port_open() {
    local host="$1"
    local port="$2"
    nc -z -w3 "$host" "$port" 2>/dev/null
}

# check_user_exists "archat"  →  returns 0 if exists
check_user_exists() {
    id "$1" &>/dev/null
}

# check_fstab_entry "SKI-Vault-Root"  →  returns 0 if found
check_fstab_entry() {
    grep -q "$1" /etc/fstab 2>/dev/null
}

# ── System Info ──

get_current_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

get_current_hostname() {
    hostname 2>/dev/null
}

get_current_timezone() {
    timedatectl show -p Timezone --value 2>/dev/null || echo "unknown"
}

get_current_kernel() {
    uname -r 2>/dev/null
}

get_ram_gb() {
    awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null
}

get_disk_free_gb() {
    df -BG / 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}'
}

# ── Require root ──

require_root() {
    if [[ $EUID -ne 0 ]]; then
        fail "This script must be run as root (use sudo)"
        exit 1
    fi
}

# ── Summary ──

print_summary() {
    echo ""
    echo -e "${CYAN}--- Summary ---${NC}"
    echo -e "  ${GREEN}PASS: $_PASS${NC}"
    [[ $_FAIL -gt 0 ]] && echo -e "  ${RED}FAIL: $_FAIL${NC}"
    [[ $_WARN -gt 0 ]] && echo -e "  ${YELLOW}WARN: $_WARN${NC}"
    [[ $_SKIP -gt 0 ]] && echo -e "  ${GRAY}SKIP: $_SKIP${NC}"
    local total=$((_PASS + _FAIL + _WARN + _SKIP))
    echo -e "  Total: $total checks"
    if [[ $_FAIL -gt 0 ]]; then
        echo -e "\n  ${RED}Result: FAILURES DETECTED${NC}"
        return 1
    elif [[ $_WARN -gt 0 ]]; then
        echo -e "\n  ${YELLOW}Result: WARNINGS (review recommended)${NC}"
        return 0
    else
        echo -e "\n  ${GREEN}Result: ALL PASSED${NC}"
        return 0
    fi
}

# ── Script banner ──

show_banner() {
    local title="$1"
    local desc="${2:-}"
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}SKI${NC} — $title"
    [[ -n "$desc" ]] && echo -e "${CYAN}║${NC}  ${GRAY}$desc${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}
