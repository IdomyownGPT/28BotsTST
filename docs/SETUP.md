# Setup Guide

Step-by-step instructions for setting up the SKI system from scratch.

## Prerequisites

### Host Machine
- Windows Server 2025
- AMD 12-Core CPU, 64GB RAM
- NVIDIA RTX 3060 (12GB VRAM) with CUDA drivers
- 1.5TB NVMe storage
- Static IP: 192.168.178.90

### VM
- Hyper-V enabled on host
- Ubuntu 24.04 LTS ISO

---

## Step 1: Host — LM Studio Setup

1. Download and install [LM Studio](https://lmstudio.ai/)
2. Download models:
   - **Bonsai Prism 8B** (normal instance)
   - **Bonsai Prism 8B** (Symbolect-trained, if available — otherwise fine-tune later)
   - **nomic-embed-text** (for embeddings)
3. Configure LM Studio:
   - Enable API server on port **1234**
   - Set GPU acceleration to CUDA
   - Load both Bonsai Prism 8B instances
4. Verify:
   ```bash
   curl http://192.168.178.90:1234/v1/models
   ```

## Step 2: Host — Obsidian Vault & SMB Share

1. Create directory structure:
   ```
   D:\28Bots_Core\Obsidian_Vault\root\
   D:\28Bots_Core\Obsidian_Vault\root\SKI_Cookbook\
   D:\28Bots_Core\Obsidian_Vault\root\SKI_Bootstrap\
   D:\28Bots_Core\Obsidian_Vault\root\SKI_Pilot\
   ```

2. Create SMB share:
   - Share name: `SKI-Vault-Root`
   - Path: `D:\28Bots_Core\Obsidian_Vault\root`
   - Permissions: `skiuser` with Read/Write

3. Configure Windows Firewall:
   - Allow TCP 1234 inbound from 192.168.178.124
   - Allow TCP 445 inbound from 192.168.178.124

4. Install Obsidian and open the vault at `D:\28Bots_Core\Obsidian_Vault\root\`

## Step 3: VM — Ubuntu 24.04 on Hyper-V

1. Create Hyper-V VM:
   - Name: `28Bots-Orchestrator-GUI`
   - RAM: **16GB** (minimum 9GB, but 16GB recommended)
   - CPU: 4 vCPUs
   - Disk: 107GB+
   - Network: External switch (same subnet as host)

2. Install Ubuntu 24.04 LTS:
   - User: `archat`
   - Set static IP: 192.168.178.124

## Step 4: VM — Automatische Provisionierung (Empfohlen)

Das Master-Skript `install_ski_vm.sh` führt die komplette VM-Einrichtung interaktiv durch:
Basis-System, SMB-Mount, Docker, Container-Deployment, Hermes-Konfiguration und Verifikation.

```bash
cd vault/SKI_Bootstrap_Opus/vm/
chmod +x install_ski_vm.sh
./install_ski_vm.sh
```

Das Skript ruft nacheinander die Einzelskripte auf:

| Skript | Beschreibung | Berechtigung |
|--------|-------------|-------------|
| `01_setup_base.sh` | Pakete, User, Hostname, Timezone, Static IP, SSH, linux-azure | sudo |
| `02_setup_smb_mount.sh` | SMB-Credentials, fstab, Mount-Verifikation | sudo |
| `03_setup_docker.sh` | Docker Engine, Compose, docker-Gruppe | sudo |
| `04_deploy_containers.sh` | Git-Repo, .env, `docker compose up -d` | User (sg docker) |
| `05_setup_hermes.sh` | 3x3 Profile, Milvus-Memory, Camofox | User (sg docker) |
| `06_verify_vm.sh` | Read-only Systemcheck aller Komponenten | User |

Jeder Schritt folgt dem Muster: **CHECK → REPORT → ASK → ACT → VERIFY**.
Es wird nichts verändert ohne vorherige Prüfung und Benutzerbestätigung.

> **Hinweis:** Das `sg docker`-Kommando umgeht die Logout/Login-Anforderung nach dem Hinzufügen zur Docker-Gruppe.

## Step 8: Auto Research (Host)

Setup the autonomous experiment loop on the Windows host:

1. **Prerequisites** (on host):
   - Python 3.10+ installed
   - CUDA drivers for RTX 3060
   - LM Studio running with Bonsai Prism 8B loaded

2. Run setup script:
   ```powershell
   # From the vault or repo
   .\vault\SKI_Bootstrap_Opus\host\07_setup_autoresearch.ps1
   ```

3. Prepare training data:
   ```powershell
   cd D:\28Bots_Core\AutoResearch
   .\.venv\Scripts\python.exe src\prepare.py
   ```

4. Quick test (10 experiments):
   ```powershell
   .\run_autoresearch.ps1 -MaxExperiments 10
   ```

5. Steer research direction by editing `program.md`:
   - Open in Obsidian: `SKI_Cookbook/M12_AutoResearch/`
   - Or directly: `D:\28Bots_Core\AutoResearch\src\program.md`

6. Overnight run:
   ```powershell
   .\run_overnight.ps1  # 200 experiments, logs to logs\
   ```

7. Check results in Obsidian:
   - `SKI_Cookbook/M12_AutoResearch/AutoResearch_Log.md`

## Step 9: Telegram Bot

1. Create bot via [@BotFather](https://t.me/BotFather):
   - Name: `MegamarphBot`
   - Save the token

2. Add token to `.env`:
   ```
   SKI_TELEGRAM_BOT_TOKEN=your-token-here
   ```

3. Restart OpenClaw:
   ```bash
   docker compose restart openclaw
   ```

4. Test: Send a message to @MegamarphBot on Telegram

---

## Verification

Run the full verification suite:

```bash
./scripts/verify_all.sh
```

This checks:
- Network connectivity (host, VM, all ports)
- Docker containers (running, memory, disk)
- LM Studio (API, models, inference, embeddings)
- Vault (mount, read/write, fstab)

For cron-based monitoring:
```bash
# Check every 5 minutes, log failures
(crontab -l; echo "*/5 * * * * /path/to/scripts/verify_all.sh --quiet --log /var/log/ski-verify.log") | crontab -
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| SMB mount lost after reboot | `sudo mount -a` — check fstab for `x-systemd.automount` |
| LM Studio not responding | Check if LM Studio is running on the host, verify firewall rule for port 1234 |
| Container keeps restarting | `docker logs <container>` — check for OOM or config errors |
| Port already in use | `sudo ss -tlnp \| grep <port>` — find conflicting process |
| Gateway config issue | Check DeerFlow gateway logs and config mount paths |
