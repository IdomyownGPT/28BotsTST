#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# SKI — Master Installer
# Führt alle Provisionierungs-Skripte in der richtigen Reihenfolge
# und mit den korrekten Berechtigungen (sudo vs. user) aus.
# ═══════════════════════════════════════════════════════════════

set -e

echo -e "\n========================================================"
echo -e "🚀 Starte SKI (Sephirotische Kernintelligenz) Provisionierung"
echo -e "========================================================\n"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Schritt 1: System-Basis konfigurieren..."
sudo bash ./01_setup_base.sh

if [[ -f "./02_setup_smb_mount.sh" ]]; then
    echo -e "\nSchritt 2: SMB Vault Mount konfigurieren..."
    sudo bash ./02_setup_smb_mount.sh
fi

if [[ -f "./03_setup_docker.sh" ]]; then
    echo -e "\nSchritt 3: Docker Engine installieren..."
    sudo bash ./03_setup_docker.sh
fi

echo -e "\nSchritt 4: Container deployen (als normaler User)..."
sg docker -c "bash ./04_deploy_containers.sh"

echo -e "\nSchritt 5: Hermes konfigurieren..."
sg docker -c "bash ./05_setup_hermes.sh"

if [[ -f "./06_verify_vm.sh" ]]; then
    echo -e "\nSchritt 6: Systemüberprüfung..."
    bash ./06_verify_vm.sh
fi

echo -e "\n========================================================"
echo -e "✅ Provisionierung abgeschlossen! Dein SKI-System ist bereit."
echo -e "========================================================\n"
