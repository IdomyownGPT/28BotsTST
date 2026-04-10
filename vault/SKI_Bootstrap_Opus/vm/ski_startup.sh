#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — ski_startup.sh — Post-Reboot Recovery
#
# Faehrt alle SKI-Services nach einem Reboot/Crash hoch:
#   1. Vault Mount pruefen/aktivieren
#   2. Docker pruefen
#   3. Container starten
#
# Einrichtung als systemd-Service:
#   sudo cp ski_startup.sh /usr/local/bin/
#   sudo chmod +x /usr/local/bin/ski_startup.sh
#   sudo cp ski_startup.service /etc/systemd/system/
#   sudo systemctl enable ski_startup.service
#
# Oder manuell: bash ~/ski_setup/ski_startup.sh
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

LOG_TAG="[SKI-Startup]"
RUNTIME_DIR="/mnt/28bots_core/runtime"
RUNTIME_LOCAL="$HOME/28Bots_Runtime"
VAULT_MOUNT="/mnt/28bots_core"
EXPECTED_CONTAINERS=4

log()  { echo "$LOG_TAG $(date '+%H:%M:%S') $*"; }
ok()   { log "OK    $*"; }
fail() { log "FAIL  $*"; }
wait_for() {
    local desc="$1" cmd="$2" tries="${3:-10}" delay="${4:-3}"
    local i=0
    while [ $i -lt "$tries" ]; do
        if eval "$cmd" 2>/dev/null; then
            ok "$desc"
            return 0
        fi
        i=$((i + 1))
        log "Waiting for $desc... ($i/$tries)"
        sleep "$delay"
    done
    fail "$desc (gave up after $tries attempts)"
    return 1
}

log "=========================================="
log "SKI Post-Reboot Recovery gestartet"
log "=========================================="

# ── 1. Docker ──
log "--- Docker ---"
if ! systemctl is-active --quiet docker; then
    log "Docker nicht aktiv, starte..."
    sudo systemctl start docker
fi
wait_for "Docker daemon" "docker info" 10 3

# ── 2. Vault Mount ──
log "--- Vault Mount ---"
if mountpoint -q "$VAULT_MOUNT" 2>/dev/null; then
    ok "Vault bereits gemountet: $VAULT_MOUNT"
else
    log "Vault nicht gemountet, versuche mount..."
    sudo systemctl daemon-reload
    sudo mount -a 2>/dev/null || true
    wait_for "Vault mount ($VAULT_MOUNT)" "mountpoint -q $VAULT_MOUNT" 5 5 || {
        # Manueller Mount-Versuch
        log "Versuche direkten Mount..."
        sudo mount -t cifs //192.168.178.90/SKI-Vault-Root "$VAULT_MOUNT" -o credentials=/etc/smbcredentials,vers=3.0,uid=1000,gid=1000 2>/dev/null || true
        wait_for "Vault mount (direkt)" "mountpoint -q $VAULT_MOUNT" 3 5 || {
            fail "Vault Mount fehlgeschlagen — Host evtl. noch nicht bereit"
            fail "Container starten trotzdem (ohne Vault)"
        }
    }
fi

# ── 3. Runtime Directory finden ──
log "--- Runtime ---"
COMPOSE_DIR=""
if [ -f "$RUNTIME_DIR/docker-compose.yml" ]; then
    COMPOSE_DIR="$RUNTIME_DIR"
    ok "Runtime: $COMPOSE_DIR (SMB)"
elif [ -f "$RUNTIME_LOCAL/docker-compose.yml" ]; then
    COMPOSE_DIR="$RUNTIME_LOCAL"
    ok "Runtime: $COMPOSE_DIR (lokal)"
else
    fail "Kein docker-compose.yml gefunden!"
    fail "Erwartet: $RUNTIME_DIR oder $RUNTIME_LOCAL"
    exit 1
fi

# ── 4. Container starten ──
log "--- Container ---"
cd "$COMPOSE_DIR"
docker compose up -d 2>&1 | while IFS= read -r line; do log "  $line"; done

# ── 5. Health Check ──
log "--- Health Check ---"
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    RUNNING=$(docker compose ps --format json 2>/dev/null | grep -c '"running"' || echo "0")
    if [ "$RUNNING" -ge "$EXPECTED_CONTAINERS" ]; then
        ok "Alle $EXPECTED_CONTAINERS Container laufen!"
        break
    fi
    log "Warte... $RUNNING/$EXPECTED_CONTAINERS running (${ELAPSED}s)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    fail "Timeout — nur $RUNNING/$EXPECTED_CONTAINERS Container laufen"
    docker compose ps 2>/dev/null | while IFS= read -r line; do log "  $line"; done
fi

# ── Status ──
log "=========================================="
log "Container Status:"
docker compose ps 2>/dev/null | while IFS= read -r line; do log "  $line"; done
log "=========================================="
log "SKI Startup abgeschlossen."
