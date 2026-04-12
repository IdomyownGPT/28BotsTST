#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — ski_diagnose.sh — Service Diagnostik
#
# Zeigt: Container-Status, Listening Ports, Service-Erreichbarkeit,
#        Logs, Netzwerk, Ressourcen
#
# Read-only — aendert nichts am System.
# ═══════════════════════════════════════════════════════════════

# ── Farben ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC}    $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC}  $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
info() { echo -e "  ${GRAY}[INFO]${NC}  $*"; }
hdr()  { echo -e "\n${CYAN}=== $* ===${NC}"; }

RUNTIME_DIR="/mnt/28bots_core/runtime"
HOST_IP="${SKI_HOST_IP:-192.168.178.90}"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}SKI Diagnostik${NC} — $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${CYAN}║${NC}  ${GRAY}VM: $(hostname) | IP: $(hostname -I 2>/dev/null | awk '{print $1}')${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"

# ═══════════════════════════════════════════════════════════════
# 1. System
# ═══════════════════════════════════════════════════════════════
hdr "System"
info "Uptime:    $(uptime -p 2>/dev/null || uptime)"
info "RAM:       $(free -h 2>/dev/null | awk '/^Mem:/ {printf "%s / %s (%s frei)", $3, $2, $4}')"
info "Disk:      $(df -h / 2>/dev/null | awk 'NR==2 {printf "%s / %s (%s frei)", $3, $2, $4}')"

# ═══════════════════════════════════════════════════════════════
# 2. Docker
# ═══════════════════════════════════════════════════════════════
hdr "Docker"
if docker info &>/dev/null; then
    ok "Docker daemon laeuft"
else
    fail "Docker daemon nicht erreichbar"
    info "Versuche: sudo systemctl start docker"
fi

# ═══════════════════════════════════════════════════════════════
# 3. Vault Mount
# ═══════════════════════════════════════════════════════════════
hdr "Vault Mount"
if mountpoint -q /mnt/28bots_core 2>/dev/null; then
    FILES=$(find /mnt/28bots_core -maxdepth 2 -type f 2>/dev/null | wc -l)
    ok "/mnt/28bots_core gemountet ($FILES Dateien)"
else
    fail "/mnt/28bots_core NICHT gemountet"
    info "Versuche: sudo mount -a"
fi

if [ -f "$RUNTIME_DIR/docker-compose.yml" ]; then
    ok "docker-compose.yml vorhanden"
else
    fail "docker-compose.yml FEHLT in $RUNTIME_DIR"
fi

# Hermes-spezifischer Vault-Pfad fuer Sessions/Memory
HERMES_VAULT="/mnt/28bots_core/hermes"
if [ -d "$HERMES_VAULT" ]; then
    SESS=$(find "$HERMES_VAULT/sessions" -name '*.jsonl' 2>/dev/null | wc -l)
    MEMS=$(find "$HERMES_VAULT/memory" -name '*.md' 2>/dev/null | wc -l)
    ok "Hermes Vault vorhanden ($SESS Sessions, $MEMS Memos)"
else
    warn "Hermes Vault fehlt: $HERMES_VAULT (wird beim Container-Start erzeugt)"
fi

# ═══════════════════════════════════════════════════════════════
# 4. Container Status
# ═══════════════════════════════════════════════════════════════
hdr "Container Status"
if [ -f "$RUNTIME_DIR/docker-compose.yml" ]; then
    cd "$RUNTIME_DIR" 2>/dev/null
    echo ""
    docker compose ps 2>/dev/null | while IFS= read -r line; do
        if echo "$line" | grep -q "Up\|running"; then
            echo -e "  ${GREEN}$line${NC}"
        elif echo "$line" | grep -q "Restarting\|Exit\|exited"; then
            echo -e "  ${RED}$line${NC}"
        else
            echo -e "  $line"
        fi
    done
    echo ""

    # Container-Anzahl
    TOTAL=$(docker compose ps -a --format '{{.Name}}' 2>/dev/null | wc -l || echo 0)
    RUNNING=$(docker compose ps --format '{{.Name}}' --filter "status=running" 2>/dev/null | wc -l || echo 0)
    if [ "$RUNNING" -ge 4 ]; then
        ok "Alle Container laufen ($RUNNING/$TOTAL)"
    else
        warn "Nur $RUNNING/$TOTAL Container laufen"
    fi
else
    fail "Kann Container-Status nicht pruefen (kein docker-compose.yml)"
fi

# ═══════════════════════════════════════════════════════════════
# 5. Listening Ports (auf der VM)
# ═══════════════════════════════════════════════════════════════
hdr "Listening Ports"
echo ""
printf "  ${BOLD}%-8s %-25s %-12s${NC}\n" "PORT" "PROZESS" "STATUS"
printf "  ${GRAY}%-8s %-25s %-12s${NC}\n" "--------" "-------------------------" "------------"

for entry in "8080:Agent-Zero" "9377:Hermes-Agent" "3000:OpenClaw" "3001:OpenClaw-2" "1234:LM-Studio($HOST_IP)"; do
    port="${entry%%:*}"
    name="${entry##*:}"

    # Check if port is listening locally
    if echo "$name" | grep -q "$HOST_IP"; then
        # Remote port (LM Studio)
        LISTENING="(remote)"
        if nc -z -w2 "$HOST_IP" "$port" 2>/dev/null; then
            printf "  ${GREEN}%-8s %-25s %-12s${NC}\n" ":$port" "$name" "ERREICHBAR"
        else
            printf "  ${RED}%-8s %-25s %-12s${NC}\n" ":$port" "$name" "NICHT ERREICHBAR"
        fi
    else
        # Local port
        PROC=$(ss -tlnp 2>/dev/null | grep ":$port " | awk '{print $NF}' | head -1)
        if [ -n "$PROC" ]; then
            printf "  ${GREEN}%-8s %-25s %-12s${NC}\n" ":$port" "$name" "LISTENING"
        else
            printf "  ${RED}%-8s %-25s %-12s${NC}\n" ":$port" "$name" "NICHT LISTENING"
        fi
    fi
done
echo ""

# ═══════════════════════════════════════════════════════════════
# 6. Service Erreichbarkeit (HTTP)
# ═══════════════════════════════════════════════════════════════
hdr "Service Erreichbarkeit (HTTP)"
echo ""
printf "  ${BOLD}%-25s %-10s %-30s${NC}\n" "SERVICE" "STATUS" "ANTWORT"
printf "  ${GRAY}%-25s %-10s %-30s${NC}\n" "-------------------------" "----------" "------------------------------"

for entry in "http://localhost:8080:Agent-Zero-UI" "http://localhost:9377/health:Hermes-Health" "http://localhost:9377/profiles:Hermes-Profiles" "http://localhost:9377/tools:Hermes-Tools" "http://localhost:9377/sessions:Hermes-Sessions" "http://localhost:3000/health:OpenClaw-Health" "http://localhost:3001/health:OpenClaw-2-Health" "http://$HOST_IP:1234/v1/models:LM-Studio-API"; do
    url="${entry%:*:*}"
    # Handle URLs with multiple colons properly
    name="${entry##*:}"
    url="${entry%:$name}"

    RESP=$(curl -sf --max-time 3 "$url" 2>/dev/null)
    CODE=$?

    if [ $CODE -eq 0 ]; then
        # Truncate response
        SHORT=$(echo "$RESP" | head -c 50 | tr '\n' ' ')
        printf "  ${GREEN}%-25s %-10s %-30s${NC}\n" "$name" "OK" "$SHORT"
    else
        printf "  ${RED}%-25s %-10s %-30s${NC}\n" "$name" "FAIL" "(keine Antwort)"
    fi
done
echo ""

# ═══════════════════════════════════════════════════════════════
# 7. Container Logs (letzte Fehler)
# ═══════════════════════════════════════════════════════════════
hdr "Letzte Container-Fehler (stderr)"

for cname in ski-agent-zero ski-hermes-agent ski-openclaw ski-openclaw-2; do
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
        ERRORS=$(docker logs "$cname" --tail 5 2>&1 | grep -iE "error|fail|exception|traceback|crash|refused" | tail -3)
        if [ -n "$ERRORS" ]; then
            warn "$cname:"
            echo "$ERRORS" | while IFS= read -r line; do
                echo -e "    ${RED}$line${NC}"
            done
        else
            ok "$cname — keine Fehler in letzten 5 Zeilen"
        fi
    else
        info "$cname — Container nicht vorhanden"
    fi
done

# ═══════════════════════════════════════════════════════════════
# 8. Docker Netzwerk
# ═══════════════════════════════════════════════════════════════
hdr "Docker Netzwerk (ski-net)"
NET_ID=$(docker network ls --filter name=ski-net --format '{{.ID}}' 2>/dev/null)
if [ -n "$NET_ID" ]; then
    ok "ski-net existiert ($NET_ID)"
    info "Verbundene Container:"
    docker network inspect ski-net --format '{{range .Containers}}  - {{.Name}} ({{.IPv4Address}}){{"\n"}}{{end}}' 2>/dev/null | while IFS= read -r line; do
        [ -n "$line" ] && echo -e "    ${GRAY}$line${NC}"
    done
else
    fail "ski-net Netzwerk nicht gefunden"
fi

# ═══════════════════════════════════════════════════════════════
# 9. Firewall (ufw)
# ═══════════════════════════════════════════════════════════════
hdr "Firewall"
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1)
    if echo "$UFW_STATUS" | grep -q "inactive"; then
        ok "ufw ist INAKTIV (alle Ports offen)"
    elif echo "$UFW_STATUS" | grep -q "active"; then
        warn "ufw ist AKTIV — kann Ports blockieren!"
        info "Regeln:"
        sudo ufw status numbered 2>/dev/null | head -15 | while IFS= read -r line; do
            echo -e "    $line"
        done
        echo ""
        info "Falls Ports blockiert: sudo ufw allow 8080/tcp && sudo ufw allow 9377/tcp"
    fi
else
    info "ufw nicht installiert (kein Firewall-Problem)"
fi

# ═══════════════════════════════════════════════════════════════
# 10. iptables Docker-Regeln
# ═══════════════════════════════════════════════════════════════
hdr "Docker Port-Forwarding (iptables)"
info "NAT DOCKER-Regeln:"
sudo iptables -t nat -L DOCKER -n 2>/dev/null | grep -E "tcp dpt:(8080|9377|3000|3001)" | while IFS= read -r line; do
    echo -e "    ${GRAY}$line${NC}"
done
RULE_COUNT=$(sudo iptables -t nat -L DOCKER -n 2>/dev/null | grep -cE "tcp dpt:(8080|9377|3000|3001)" || echo 0)
if [ "$RULE_COUNT" -ge 4 ]; then
    ok "Alle 4 Port-Forwarding-Regeln vorhanden"
elif [ "$RULE_COUNT" -gt 0 ]; then
    warn "Nur $RULE_COUNT/4 Port-Forwarding-Regeln gefunden"
else
    fail "Keine Docker Port-Forwarding-Regeln — Container-Ports nicht erreichbar!"
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Quick-Fix Cheatsheet:${NC}"
echo -e "  ${GRAY}Mount fehlt:      ${NC}sudo mount -a"
echo -e "  ${GRAY}Docker tot:       ${NC}sudo systemctl start docker"
echo -e "  ${GRAY}Container unten:  ${NC}cd $RUNTIME_DIR && docker compose up -d"
echo -e "  ${GRAY}Container rebuild:${NC}cd $RUNTIME_DIR && docker compose up -d --build"
echo -e "  ${GRAY}Einzelner Log:    ${NC}docker logs ski-hermes-agent --tail 50"
echo -e "  ${GRAY}Alle Logs:        ${NC}cd $RUNTIME_DIR && docker compose logs -f"
echo -e "  ${GRAY}Port blockiert:   ${NC}sudo ufw allow 8080/tcp"
echo -e "  ${GRAY}Alles neu:        ${NC}bash /usr/local/bin/ski_startup.sh"
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
