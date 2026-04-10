# SKI — Sephirotische Kernintelligenz

**Local self-learning AI system** with GPU inference, multi-agent orchestration, and knowledge management.

| | Status |
|---|---|
| LM Studio | Active (Bonsai Prism 8B x2 + nomic-embed-text) |
| DeerFlow UI | Active (:2026) |
| DeerFlow Gateway | Config issue (:8001) |
| Hermes v0.7.0 (9 profiles) | Active (:9377 Camofox) |
| OpenClaw | Active (:3000) |
| Agent Zero | Active (:8080) |
| Milvus VDB | Active (:19530) |
| Vault Mount | Active (SMB) |
| Auto Research | New (M12 — Karpathy experiment loop) |
| Telegram | Token ready, not connected |

## Architecture

Two-machine setup on LAN `192.168.178.0/24`:

```
┌──────────────────────────────┐     ┌──────────────────────────────┐
│  HOST — Windows Server 2025  │     │  VM — Ubuntu 24.04 (Hyper-V) │
│  192.168.178.90              │     │  192.168.178.124              │
│                              │     │                              │
│  LM Studio :1234             │◄────│  DeerFlow :2026              │
│    Bonsai Prism 8B (normal)  │     │  OpenClaw :3000              │
│    Bonsai Prism 8B (Symbolect)     │  Hermes v0.7 (9 profiles)    │
│    nomic-embed-text          │     │  Agent Zero :8080            │
│  Auto Research (GPU loop)    │     │  Milvus :19530               │
│  RTX 3060 · 12GB VRAM       │     │  AutoRes Monitor             │
│                              │     │                              │
│  Obsidian Vault ◄────SMB────►│  /mnt/28bots_core               │
│  NAS 12TB                    │     │  Docker v29.3.1              │
└──────────────────────────────┘     └──────────────────────────────┘
```

## Hardware

| | Host | VM |
|---|---|---|
| CPU | AMD Ryzen 9 5900X · 12-Core | 4 vCPUs |
| RAM | 64 GB | 9 GB (16GB recommended) |
| GPU | RTX 3060 · 12GB VRAM · CUDA | None |
| Storage | 1.5TB NVMe + 12TB NAS | 107GB (62GB free) |

## Port Map

| Port | Service | Machine | Status |
|------|---------|---------|--------|
| 1234 | LM Studio API | Host | Active |
| 2024 | LangGraph Engine | VM | Active |
| 2026 | DeerFlow (nginx) | VM | Active |
| 3000 | OpenClaw | VM | Active |
| 3100 | DeerFlow Frontend | VM | Active |
| 8001 | DeerFlow Gateway | VM | Config Issue |
| 8080 | Agent Zero | VM | Active |
| 9377 | Hermes Camofox Browser | VM | New (v0.7) |
| 19530 | Milvus VDB | VM | Active |

## Quick Verification

```bash
# Run all checks from the VM
./scripts/verify_all.sh

# Run individual checks
./scripts/verify_network.sh        # Ping, ports, connectivity
./scripts/verify_docker.sh         # Containers, memory, disk
./scripts/verify_lm_studio.sh      # Models, inference, embeddings
./scripts/verify_vault.sh          # SMB mount, read/write, fstab
./scripts/verify_autoresearch.sh   # Auto Research status, experiment logs
```

## Models (Bonsai Prism 8B)

Instead of multiple large models, SKI uses **Bonsai Prism 8B** (<2GB VRAM per instance), loaded twice:

| Instance | Purpose | VRAM |
|----------|---------|------|
| Bonsai Prism 8B (normal) | General-purpose inference | <2 GB |
| Bonsai Prism 8B (Symbolect) | Trained on Symbolect/Runes | <2 GB |
| nomic-embed-text | Vector embeddings | ~0.5 GB |
| **Total** | | **~4.5 GB** (of 12GB available) |

## Hermes 3×3 Matrix

| | α Generation | β Orchestration | γ Execution |
|---|---|---|---|
| **Kether** | kether-alpha | kether-beta | kether-gamma |
| **Tiferet** | tiferet-alpha | **tiferet-beta** ★ | tiferet-gamma |
| **Malkuth** | malkuth-alpha | malkuth-beta | malkuth-gamma |

★ = Default profile. Switch: `hermes -p [profile] chat`

## Auto Research (Karpathy-style)

Autonomous ML experiment loop running on the host GPU. Based on [karpathy/autoresearch](https://github.com/karpathy/autoresearch).

```
program.md → Agent (Bonsai Prism 8B) → Modify train.py → Train (5 min) → Evaluate val_bpb
                                                                              │
                                                                   Improved? Keep : Revert
                                                                              │
                                                                         Repeat ×100
```

- **Agent:** Bonsai Prism 8B via LM Studio (proposes code changes)
- **Training:** RTX 3060 · CUDA · 5-minute wall-clock budget per experiment
- **Steering:** Edit `program.md` in Obsidian to guide research direction
- **Results:** Logged to vault (`SKI_Cookbook/M12_AutoResearch/`)

```powershell
# On the Windows host
.\run_autoresearch.ps1                    # 100 experiments
.\run_overnight.ps1                       # 200 experiments overnight
```

## Known Issues

See [docs/DESIGN_ISSUES.md](docs/DESIGN_ISSUES.md) for full details.

1. **VM RAM too low** — 9GB for 8 containers. Increase to 16GB recommended.
2. **DeerFlow Gateway** — Config-path fix pending (port 8001)
3. **Telegram** — Bot token exists but webhook not connected
4. **SMB mount** — Needs `x-systemd.automount` in fstab for boot reliability

## Documentation

| Doc | Description |
|-----|-------------|
| [Architecture](docs/ARCHITECTURE.md) | System topology, data flows, Hermes matrix |
| [Components](docs/COMPONENTS.md) | Detailed description of each container |
| [Network](docs/NETWORK.md) | Port allocation, network diagram |
| [Setup](docs/SETUP.md) | Step-by-step installation guide |
| [Design Issues](docs/DESIGN_ISSUES.md) | Known problems with solutions |
| [Roadmap](docs/ROADMAP.md) | Milestones M00-M11, next actions |

## Repository Structure

```
28BotsTST/
├── README.md                  # This file
├── docker-compose.yml         # Container definitions
├── .env.example               # Environment template
├── docs/
│   ├── ARCHITECTURE.md
│   ├── COMPONENTS.md
│   ├── DESIGN_ISSUES.md
│   ├── NETWORK.md
│   ├── ROADMAP.md
│   └── SETUP.md
├── scripts/
│   ├── lib/common.sh          # Shared functions
│   ├── verify_all.sh          # Run all checks
│   ├── verify_autoresearch.sh # Auto Research status
│   ├── verify_docker.sh
│   ├── verify_lm_studio.sh
│   ├── verify_network.sh
│   └── verify_vault.sh
└── src/
    ├── autoresearch/
    │   ├── config.py          # Configuration
    │   ├── prepare.py         # Data preparation (never modified by agent)
    │   ├── program.md         # Research directions (edit to steer)
    │   ├── ski_runner.py      # Experiment loop (main entry point)
    │   └── train.py           # Training code (modified by agent)
    └── components/
        └── SKIArchitecture.jsx # React visualization
```

## Getting Started

### Automatische Installation (Empfohlen)

Um die Ubuntu-VM vollständig zu provisionieren (inkl. Docker, SMB-Mounts, Container und Hermes), nutze das mitgelieferte Master-Skript.

1. Navigiere in den VM-Bootstrap-Ordner:
   ```bash
   cd vault/SKI_Bootstrap_Opus/vm/
   ```
2. Mache das Master-Skript ausführbar:
   ```bash
   chmod +x install_ski_vm.sh
   ```
3. Führe das Skript **als normaler User (nicht als root/sudo)** aus:
   ```bash
   ./install_ski_vm.sh
   ```

Das Skript führt dich interaktiv durch alle nötigen Schritte und fragt Root-Rechte nur dann an, wenn sie explizit benötigt werden.

### Schnellstart für Windows (Ohne Git)

1. Lade die Datei `SKI_Deployment_Pack.zip` direkt hier aus dem Repository herunter.
2. Entpacke die ZIP-Datei auf deinem Windows-Host (z.B. nach `C:\SKI_Setup`).
3. Öffne PowerShell als Administrator und navigiere in den Ordner:
   ```powershell
   cd "C:\SKI_Setup\vault\SKI_Bootstrap_Opus\host\"
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
   ```
4. Führe das Setup-Skript aus:
   ```powershell
   .\06_ssh_vm_setup.ps1
   ```

### Manuelle Installation

```bash
# Clone
git clone https://github.com/IdomyownGPT/28BotsTST.git
cd 28BotsTST

# Configure
cp .env.example .env
nano .env  # Set your values

# Deploy (on the VM)
docker compose up -d

# Verify
./scripts/verify_all.sh
```

---

*SKI Architecture v2.0 — 28Bots — 2026-04-04*
