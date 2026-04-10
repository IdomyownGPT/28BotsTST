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

3. Post-install:
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y cifs-utils curl jq netcat-openbsd
   ```

## Step 4: VM — SMB Mount

1. Create credentials file:
   ```bash
   sudo bash -c 'cat > /etc/smbcredentials << EOF
   username=skiuser
   password=YOUR_PASSWORD_HERE
   EOF'
   sudo chmod 600 /etc/smbcredentials
   ```

2. Create mount point:
   ```bash
   sudo mkdir -p /mnt/28bots_core
   ```

3. Add to `/etc/fstab`:
   ```
   //192.168.178.90/SKI-Vault-Root  /mnt/28bots_core  cifs  credentials=/etc/smbcredentials,_netdev,x-systemd.automount,x-systemd.mount-timeout=30,vers=3.0,uid=1000,gid=1000  0  0
   ```

4. Mount and verify:
   ```bash
   sudo mount -a
   ls /mnt/28bots_core/Obsidian_Vault/
   ```

## Step 5: VM — Docker Installation

```bash
# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker archat

# Install Docker Compose plugin
sudo apt install -y docker-compose-plugin

# Verify
docker --version
docker compose version
```

Log out and back in for group changes to take effect.

## Step 6: VM — Deploy Containers

1. Clone this repository:
   ```bash
   git clone https://github.com/IdomyownGPT/28BotsTST.git
   cd 28BotsTST
   ```

2. Configure environment:
   ```bash
   cp .env.example .env
   # Edit .env with your values (especially Telegram bot token)
   nano .env
   ```

3. Start all containers:
   ```bash
   docker compose up -d
   ```

4. Verify:
   ```bash
   docker compose ps
   ./scripts/verify_all.sh
   ```

## Step 7: VM — Hermes Setup

1. Install Hermes v0.7.0 (follow Hermes documentation)
2. Configure 9 profiles:
   ```bash
   # The profiles are: kether-{alpha,beta,gamma}, tiferet-{alpha,beta,gamma}, malkuth-{alpha,beta,gamma}
   hermes profiles list
   hermes -p tiferet-beta chat   # Test default profile
   ```
3. New in v0.7.0 — optional advanced setup:
   ```bash
   # Configure Milvus as pluggable memory provider
   hermes config set memory.provider milvus
   hermes config set memory.milvus_host localhost
   hermes config set memory.milvus_port 19530

   # Configure credential pool for LM Studio
   hermes config set providers.lm_studio.credentials '[{"api_key":"sk-1"},{"api_key":"sk-2"}]'

   # Install Camofox browser (port 9377)
   hermes tools install camofox
   ```

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
