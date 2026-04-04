# SKI — Sephirotische Kernintelligenz

**Local self-learning AI system** with GPU inference, multi-agent orchestration, and knowledge management.

| | Status |
|---|---|
| LM Studio | Active (Bonsai Prism 8B x2 + nomic-embed-text) |
| DeerFlow UI | Active (:2026) |
| DeerFlow Gateway | Config issue (:8001) |
| Hermes (9 profiles) | Active |
| OpenClaw | Active (:3000) |
| Agent Zero | Active (:8080) |
| Milvus VDB | Active (:19530) |
| Vault Mount | Active (SMB) |
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
│    Bonsai Prism 8B (Symbolect)     │  Hermes (9 profiles)         │
│    nomic-embed-text          │     │  Agent Zero :8080            │
│  RTX 3060 · 12GB VRAM       │     │  Milvus :19530               │
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
| 19530 | Milvus VDB | VM | Active |

## Quick Verification

```bash
# Run all checks from the VM
./scripts/verify_all.sh

# Run individual checks
./scripts/verify_network.sh     # Ping, ports, connectivity
./scripts/verify_docker.sh      # Containers, memory, disk
./scripts/verify_lm_studio.sh   # Models, inference, embeddings
./scripts/verify_vault.sh       # SMB mount, read/write, fstab
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
│   ├── verify_docker.sh
│   ├── verify_lm_studio.sh
│   ├── verify_network.sh
│   └── verify_vault.sh
└── src/
    └── components/
        └── SKIArchitecture.jsx # React visualization
```

## Getting Started

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
