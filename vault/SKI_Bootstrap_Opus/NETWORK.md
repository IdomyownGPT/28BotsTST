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
| Hermes Tools | `http://192.168.178.122:9377/tools` |
| Hermes Sessions | `http://192.168.178.122:9377/sessions` |
| Hermes Memory Search | `http://192.168.178.122:9377/memory/search?q=...` |
| OpenClaw Health | `http://192.168.178.122:3000/health` |
| OpenClaw-2 Health | `http://192.168.178.122:3001/health` |

## Hermes Agent — Endpoints (Port 9377)

| Method | Route | Zweck |
|---|---|---|
| GET | `/health` | LM Studio Status, gebundenes Modell, Tool-Calling an/aus |
| GET | `/profiles` | 3x3 Sephirotische Profil-Matrix |
| GET | `/tools` | Aktives Toolset (OpenAI Tool-Schema) |
| GET | `/sessions` | Alle bekannten Session-IDs |
| GET | `/sessions/<id>` | Session-History (JSON-L aus Vault) |
| DELETE | `/sessions/<id>` | Session loeschen (nicht `default`) |
| GET | `/memory/search?q=...` | ripgrep ueber den Vault |
| POST | `/chat` | Einfacher Chat mit optionaler `session_id` |
| POST | `/v1/chat/completions` | OpenAI-kompatibel, Tool-Calling + Streaming |

### Hermes Memory Layout (im Obsidian Vault)

```
D:\28Bots_Core\hermes\           (Host)
/mnt/28bots_core/hermes/         (VM)
/app/vault/                       (Container-Mount)
    sessions/
        2026-04-12/
            default.jsonl
            <session_id>.jsonl
    memory/
        2026-04/
            <slug>.md             (YAML-frontmatter + Markdown)
```

### Standard-Tools im Proxy

| Tool | Signatur | Zweck |
|---|---|---|
| `vault_read` | `(path)` | Liest Datei aus `/app/vault`, max. 64 KB |
| `vault_search` | `(query)` | ripgrep ueber den Vault (20 Treffer max) |
| `vault_write` | `(title, content, tags?)` | Schreibt Markdown-Notiz in `memory/<YYYY-MM>/` |
| `profile_switch` | `(name)` | Wechselt Hermes-Profil fuer aktuelle Anfrage |

### Model Pinning (runtime/.env)

```
SKI_HERMES_MODEL=hermes-4.3-36b
SKI_HERMES_MODEL_FALLBACK=hermes-3-llama-3.1-8b
SKI_HERMES_TOOL_CALLING=true
SKI_HERMES_MAX_TOOL_ROUNDS=3
SKI_HERMES_HISTORY_LIMIT=20
```

Siehe `docs/HERMES_MODEL_SETUP.md` fuer das Laden des Modells in LM Studio.

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
