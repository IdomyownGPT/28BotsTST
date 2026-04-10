# SKI Netzwerk-Topologie

## Maschinen

| Maschine | IP | OS | Rolle |
|---|---|---|---|
| **Windows Host** | `192.168.178.90` | Windows Server 2025 | LM Studio, Obsidian Vault, SMB Share |
| **Ubuntu VM** | `192.168.178.122` (DHCP) | Ubuntu 24.04 (Hyper-V) | Docker Runtime, alle Container |

## SMB Share

| Share | Host-Pfad | VM-Mount | Zweck |
|---|---|---|---|
| `SKI-Vault-Root` | `D:\28Bots_Core\` | `/mnt/28bots_core/` | Vault, Runtime, Obsidian |

## Container (Docker ski-net Bridge)

| Container | Image | Port (VM) | Interner DNS | Funktion |
|---|---|---|---|---|
| `ski-agent-zero` | `frdel/agent-zero` | `:8080` | `agent-zero:8080` | Orchestrator, Web-UI |
| `ski-hermes-agent` | `python:3.11-slim` | `:9377` | `hermes-agent:9377` | 3x3 Profil-Proxy zu LM Studio |
| `ski-openclaw` | `node:22-slim` | `:3000` | `openclaw:3000` | Telegram Bot 1 |
| `ski-openclaw-2` | `node:22-slim` | `:3001` | `openclaw-2:3001` | Telegram Bot 2 |

## Host-Services (Windows)

| Service | Port | URL vom VM aus |
|---|---|---|
| **LM Studio** | `:1234` | `http://192.168.178.90:1234/v1` |
| **SMB** | `:445` | `//192.168.178.90/SKI-Vault-Root` |

## Zugriff vom Host-Browser

| Service | URL |
|---|---|
| Agent Zero Web-UI | `http://192.168.178.122:8080` |
| Hermes Health | `http://192.168.178.122:9377/health` |
| Hermes Profile | `http://192.168.178.122:9377/profiles` |
| OpenClaw Health | `http://192.168.178.122:3000/health` |
| OpenClaw-2 Health | `http://192.168.178.122:3001/health` |

## Container-zu-Container (ski-net intern)

Container sprechen sich ueber Docker-DNS an (Servicename aus docker-compose.yml):

```
agent-zero    -> hermes-agent:9377  (Reasoning-Anfragen)
openclaw      -> hermes-agent:9377  (Chat-Weiterleitung)
openclaw-2    -> hermes-agent:9377  (Chat-Weiterleitung)
hermes-agent  -> 192.168.178.90:1234 (LM Studio Inference)
```

## Architektur-Diagramm

```
┌──────────────────────────────────────┐
│  Windows Host (192.168.178.90)       │
│  ┌──────────────┐  ┌─────────────┐  │
│  │  LM Studio   │  │  Obsidian   │  │
│  │  :1234       │  │  Vault      │  │
│  └──────┬───────┘  └──────┬──────┘  │
│         │    SMB: D:\28Bots_Core\    │
└─────────┼──────────────────┼────────┘
          │                  │
┌─────────┼──────────────────┼────────┐
│  Ubuntu VM (192.168.178.122)        │
│         │   /mnt/28bots_core/       │
│         │                           │
│  ┌──────┴───────────────────────┐   │
│  │  ski-net (Docker Bridge)     │   │
│  │                              │   │
│  │  ┌────────────────────────┐  │   │
│  │  │ ski-agent-zero  :8080  │  │   │
│  │  │ Orchestrator + Web-UI  │  │   │
│  │  └────────────────────────┘  │   │
│  │  ┌────────────────────────┐  │   │
│  │  │ ski-hermes-agent :9377 │  │   │
│  │  │ 3x3 Profil-Matrix     │──┼───┼──> LM Studio
│  │  └────────────────────────┘  │   │
│  │  ┌────────────┐ ┌─────────┐  │   │
│  │  │ openclaw   │ │openclaw │  │   │
│  │  │ :3000      │ │-2 :3001 │  │   │
│  │  │ Telegram 1 │ │Telegram2│  │   │
│  │  └────────────┘ └─────────┘  │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

## Recovery nach Reboot

```bash
# Automatisch (systemd):
sudo systemctl status ski_startup.service

# Manuell:
bash /usr/local/bin/ski_startup.sh

# Oder direkt:
sudo mount -a
cd /mnt/28bots_core/runtime && docker compose up -d
```

## Troubleshooting

```bash
# Container-Status:
cd /mnt/28bots_core/runtime && docker compose ps

# Logs eines Containers:
docker logs ski-hermes-agent --tail 50

# Alle Logs:
docker compose logs -f

# Diagnostik-Script:
bash ~/ski_setup/ski_diagnose.sh
```
