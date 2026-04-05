# SKI Architecture

## System Overview

SKI (Sephirotische Kernintelligenz / Sephirotic Core Intelligence) is a local, self-learning AI system running on two machines:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SKI Architecture v2.0                             │
│                                                                     │
│  ┌───────────────────────────┐     ┌─────────────────────────────┐ │
│  │  WINDOWS SERVER 2025      │     │  UBUNTU 24.04 VM            │ │
│  │  Host: 192.168.178.90     │     │  VM: 192.168.178.124        │ │
│  │                           │     │                             │ │
│  │  ┌─────────────────────┐  │     │  ┌───────────────────────┐ │ │
│  │  │  LM Studio :1234    │◄─┼─────┼──│  DeerFlow :2026       │ │ │
│  │  │  Bonsai Prism 8B ×2 │  │     │  │  ├ LangGraph :2024    │ │ │
│  │  │  nomic-embed-text   │  │     │  │  ├ Frontend :3100     │ │ │
│  │  │  RTX 3060 · 12GB    │  │     │  │  ├ Gateway :8001 ⚠    │ │ │
│  │  └─────────────────────┘  │     │  │  └ nginx :2026        │ │ │
│  │                           │     │  └───────────────────────┘ │ │
│  │  ┌─────────────────────┐  │     │  ┌───────────────────────┐ │ │
│  │  │  Obsidian Vault     │  │     │  │  OpenClaw :3000       │ │ │
│  │  │  D:\28Bots_Core\    │◄─┼─SMB─┼──│  Telegram Bot         │ │ │
│  │  │  Obsidian_Vault\    │  │     │  └───────────────────────┘ │ │
│  │  └─────────────────────┘  │     │  ┌───────────────────────┐ │ │
│  │                           │     │  │  Hermes Orchestrator  │ │ │
│  │  ┌─────────────────────┐  │     │  │  9 Profiles · v0.7.0  │ │ │
│  │  │  NAS 12TB · 1Gbit   │  │     │  └───────────────────────┘ │ │
│  │  └─────────────────────┘  │     │  ┌───────────────────────┐ │ │
│  │                           │     │  │  Agent Zero :8080     │ │ │
│  └───────────────────────────┘     │  └───────────────────────┘ │ │
│                                     │  ┌───────────────────────┐ │ │
│  ┌───────────────────────────┐     │  │  Milvus VDB :19530    │ │ │
│  │  User: Marvin             │     │  └───────────────────────┘ │ │
│  │  ├ Telegram @MegamarphBot │     │                             │ │
│  │  ├ Obsidian GUI           │     └─────────────────────────────┘ │
│  │  ├ Browser :2026          │                                     │
│  │  ├ SSH → archat@VM        │                                     │
│  │  └ LM Studio GUI         │                                     │
│  └───────────────────────────┘                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Hardware

### Host — Windows Server 2025

| Spec | Value |
|------|-------|
| CPU | AMD Ryzen 9 5900X 12-Core |
| RAM | 64 GB |
| GPU | NVIDIA RTX 3060 · 12GB VRAM |
| Storage | 1.5TB NVMe (~30GB/s cache) |
| NAS | 12TB · 1Gbit |
| IP | 192.168.178.90 (static) |

### VM — Ubuntu 24.04 (Hyper-V)

| Spec | Value |
|------|-------|
| CPU | 4 vCPUs (Ryzen 9 5900X) |
| RAM | 9 GB (recommend 16GB) |
| GPU | None (software rendering) |
| Disk | 107 GB (62GB free) |
| Kernel | 6.17.0-1010-azure |
| IP | 192.168.178.124 |

## Data Flows

### 1. Inference Path

All AI inference goes through LM Studio on the host:

```
Container → HTTP → 192.168.178.90:1234/v1/ → LM Studio → Bonsai Prism 8B → Response
```

Two model instances are available simultaneously:
- **Bonsai Prism 8B (normal)** — general-purpose (<2GB VRAM)
- **Bonsai Prism 8B (Symbolect)** — trained on project's symbolic language (<2GB VRAM)
- **nomic-embed-text** — for vector embeddings

### 2. Storage Path (Vault)

```
Obsidian (Host) ←→ D:\28Bots_Core\Obsidian_Vault\root\
                        ↕ SMB/CIFS
VM Mount ←→ /mnt/28bots_core/Obsidian_Vault/
                        ↕ Docker Bind Mount
Containers ←→ /mnt/ski-vault/
```

### 3. User Interface Path

```
Marvin → Telegram → @MegamarphBot → OpenClaw :3000 → DeerFlow :2026
Marvin → Browser → DeerFlow Frontend :3100
Marvin → Obsidian → Vault (direct on host)
Marvin → SSH → archat@192.168.178.124
```

## Hermes 3×3 Harness Matrix

The Hermes orchestrator uses 9 profiles organized in a 3×3 matrix based on the Kabbalistic Tree of Life:

| | α Generation | β Orchestration ★ | γ Execution |
|---|---|---|---|
| **ᛉ Kether** (Crown) | kether-alpha | kether-beta | kether-gamma |
| **ᚷ Tiferet** (Beauty) | tiferet-alpha | **tiferet-beta ★** | tiferet-gamma |
| **ᚢ Malkuth** (Kingdom) | malkuth-alpha | malkuth-beta | malkuth-gamma |

- **Rows** = Sephiroth level (abstract → concrete)
  - Kether: highest-level reasoning, meta-cognition
  - Tiferet: balanced orchestration, coordination
  - Malkuth: ground-level execution, tool use
- **Columns** = Role (create → coordinate → execute)
- **★ Default** = `tiferet-beta` (balanced orchestration)
- **Switch:** `hermes -p [profile] chat`

## Host Directory Structure

```
D:\
├── 28Bots_Core\
│   ├── Obsidian_Vault\root\          → SMB share
│   │   ├── SKI_Cookbook\              M00-M11 modules
│   │   ├── SKI_Bootstrap\            Scripts
│   │   └── SKI_Pilot\                SOUL.md, setup, verify
│   └── VectorDB_Hindsight\           (planned)
├── 28Bots\Models\LLM_LIB\           200GB GGUFs
└── VMs\VM_HDDs\                      Hyper-V VHDs
```

## Related Documentation

- [Components](COMPONENTS.md) — Detailed description of each container
- [Network](NETWORK.md) — Port allocation and network topology
- [Design Issues](DESIGN_ISSUES.md) — Known problems and solutions
- [Setup](SETUP.md) — Installation and configuration guide
- [Roadmap](ROADMAP.md) — Planned features and milestones
