# Network Topology & Port Allocation

## Overview

The SKI system spans two machines on the same LAN subnet `192.168.178.0/24`:

| Machine | IP | OS | Role |
|---------|----|----|------|
| **Host** | 192.168.178.90 | Windows Server 2025 | GPU inference (LM Studio), Obsidian Vault, NAS |
| **VM** | 192.168.178.124 | Ubuntu 24.04 (Hyper-V) | Docker containers, orchestration |

## Port Allocation

### Host (192.168.178.90)

| Port | Service | Protocol | Status |
|------|---------|----------|--------|
| 445 | SMB/CIFS (SKI-Vault-Root) | TCP | Active |
| 1234 | LM Studio API | HTTP | Active |
| — | Auto Research (local only) | — | New — no port exposed |

### VM (192.168.178.124)

| Port | Service | Container | Status | Notes |
|------|---------|-----------|--------|-------|
| 2024 | LangGraph Engine | deerflow-langgraph | Active | 10 workers |
| 2026 | DeerFlow (nginx reverse proxy) | deerflow-nginx | Active | Main entry point |
| 3000 | OpenClaw (Telegram Bot + Tool Gateway) | openclaw | Active | |
| 3100 | DeerFlow Frontend (Next.js) | deerflow-frontend | Active | **Moved from 3000 to resolve conflict** |
| 8001 | DeerFlow Gateway | deerflow-gateway | **Config Issue** | Needs config-path fix |
| 8080 | Agent Zero | agent-zero | Active | |
| 9377 | Hermes Camofox Browser | hermes | Active | **New in v0.7** — anti-detection browser with VNC |
| 19530 | Milvus Vector DB | milvus | Active | gRPC |

> **Port 3000 conflict resolved:** DeerFlow Frontend was originally on port 3000, conflicting with OpenClaw. DeerFlow Frontend has been moved to port 3100.

## Network Diagram

```
┌─────────────────────────────────────────────────┐
│  LAN: 192.168.178.0/24                          │
│                                                  │
│  ┌──────────────────────┐    ┌────────────────┐ │
│  │  HOST (.90)          │    │  VM (.124)     │ │
│  │                      │    │                │ │
│  │  :1234 LM Studio ◄──┼────┼── All containers│ │
│  │  :445  SMB Share  ◄──┼────┼── /mnt/28bots  │ │
│  │                      │    │                │ │
│  │  Obsidian (local)    │    │  Docker bridge │ │
│  │  NAS (12TB)          │    │  docker_deer-  │ │
│  │                      │    │  flow          │ │
│  └──────────────────────┘    └────────────────┘ │
│                                                  │
│  ┌──────────────────────┐                        │
│  │  Telegram Cloud      │                        │
│  │  @MegamarphBot ──────┼── OpenClaw :3000      │
│  └──────────────────────┘                        │
└─────────────────────────────────────────────────┘
```

## Docker Network

All containers on the VM share the `docker_deer-flow` bridge network for inter-container communication. External access is via published ports.

### Internal Container Communication

| From | To | Method |
|------|----|--------|
| DeerFlow nginx | DeerFlow Frontend | Internal network (container:3000 → host:3100) |
| DeerFlow nginx | LangGraph Engine | Internal network (container:2024) |
| DeerFlow nginx | DeerFlow Gateway | Internal network (container:8001) |
| Any container | LM Studio | External: `http://192.168.178.90:1234/v1/` |
| Any container | Vault | Bind mount: `/mnt/ski-vault/` |
| AutoRes Monitor | Vault logs | Bind mount: `/mnt/ski-vault/` (read-only) |
| Auto Research (Host) | LM Studio | Local: `http://localhost:1234/v1/` |
| Auto Research (Host) | Vault | Direct: `D:\28Bots_Core\Obsidian_Vault\root\` |

## Firewall

The Windows Server host has ~30 firewall rules configured. Critical rules:

- **Inbound TCP 1234**: Allow from 192.168.178.124 (VM → LM Studio)
- **Inbound TCP 445**: Allow from 192.168.178.124 (VM → SMB)

## Security Notes

- All traffic is **unencrypted HTTP** within the LAN — acceptable for local-only deployment
- If the system is ever exposed to the internet, **TLS is mandatory**
- SMB credentials should use `/etc/smbcredentials` (chmod 600), not inline in fstab
