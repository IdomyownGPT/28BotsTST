# Design Issues & Solutions

This document lists all identified design problems in the SKI architecture, ranked by severity, with concrete solutions.

---

## CRITICAL

### 1. Port 3000 Conflict

**Problem:** OpenClaw (Telegram Bot + Tool Gateway) and DeerFlow Frontend (Next.js) both bind to port 3000 on the VM. Only one service can listen on a given port.

**Impact:** One of the two services will fail to start. Docker may silently fail or produce hard-to-debug connection errors.

**Solution:** Move DeerFlow Frontend to port **3100**.
- Update `docker-compose.yml`: change port mapping from `3000:3000` to `3100:3000`
- Update nginx config in DeerFlow to proxy to the new port
- OpenClaw keeps port 3000

**Status:** Fixed in `docker-compose.yml`

---

### 2. VM RAM Too Low

**Problem:** The Hyper-V VM has 9GB RAM for 8 Docker containers + Ubuntu OS. Estimated usage:

| Component | Estimated RAM |
|-----------|--------------|
| Ubuntu OS + system | ~1 GB |
| DeerFlow (LangGraph, 10 workers) | 2-3 GB |
| DeerFlow (nginx, gateway, frontend) | ~1 GB |
| Milvus VDB | 1-2 GB |
| OpenClaw | ~512 MB |
| Hermes | ~512 MB |
| Agent Zero | ~1 GB |
| **Total** | **~7-9 GB** |

**Impact:** With 9GB total, there's virtually no headroom. OOM kills, swap thrashing, and container restarts are likely under load.

**Solution:**
1. **Recommended:** Increase VM RAM to 16GB in Hyper-V settings (host has 64GB — plenty of headroom)
2. **Mitigation:** Set `mem_limit` per container in docker-compose.yml to prevent any single container from consuming all RAM
3. **Consider:** Moving Milvus to the host if RAM cannot be increased (Milvus is the most memory-hungry component)

**Status:** Memory limits set in `docker-compose.yml`. RAM upgrade recommended.

---

### 3. Model Strategy — Bonsai Prism 8B

**Problem:** The original setup used multiple large models (qwen3.5-9b at ~6-8GB VRAM, qwen2.5-0.5b-instruct, nomic-embed-text) consuming most of the RTX 3060's 12GB VRAM.

**Solution:** Switch to **Bonsai Prism 8B** (<2GB VRAM per instance), loaded **twice**:
- Instance 1: **Normal** (general-purpose inference)
- Instance 2: **Symbolect/Runes-trained** (project-specific symbolic language)
- Keep **nomic-embed-text** for embeddings

**Benefits:**
- Total VRAM: ~4GB (2× Prism) + ~0.5GB (nomic) = ~4.5GB vs. previous ~10GB+
- Remaining ~7.5GB VRAM free for training, fine-tuning, or loading additional models
- Both instances can run simultaneously — no model swapping needed

**Status:** Documented. Requires model loading in LM Studio.

---

## HIGH

### 4. DeerFlow Gateway Config Issue

**Problem:** The DeerFlow Gateway on port 8001 has a known configuration path problem (marked ⚠️ in the architecture).

**Impact:** Gateway is non-functional, which may break routing between DeerFlow components.

**Solution:**
1. Check DeerFlow Gateway logs: `docker logs <gateway-container>`
2. Verify the config path mount in docker-compose
3. Typical fix: ensure the `.env` or config file is correctly bind-mounted into the container

**Status:** Pending investigation.

---

### 5. SMB Mount Unreliable After Reboot

**Problem:** The vault SMB mount at `/mnt/28bots_core` is lost after VM reboot. The current fstab uses `_netdev` which is insufficient — it only delays the mount until network is available, but doesn't handle the case where the host isn't ready yet.

**Solution:** Update fstab entry with robust options:

```
//192.168.178.90/SKI-Vault-Root  /mnt/28bots_core  cifs  credentials=/etc/smbcredentials,_netdev,x-systemd.automount,x-systemd.mount-timeout=30,vers=3.0,uid=1000,gid=1000  0  0
```

Key additions:
- `x-systemd.automount` — mounts on first access, not at boot (avoids race conditions)
- `x-systemd.mount-timeout=30` — gives the host time to come up
- `credentials=/etc/smbcredentials` — secure credential storage (chmod 600)

Create `/etc/smbcredentials`:
```
username=skiuser
password=<your-password>
```
Then: `sudo chmod 600 /etc/smbcredentials`

**Status:** Documented. Requires manual fstab update on VM.

---

### 6. No Monitoring / Health Checks

**Problem:** No automated way to detect when services go down. System can fail silently.

**Solution:**
1. **Immediate:** Use `scripts/verify_all.sh` on cron:
   ```
   */5 * * * * /path/to/scripts/verify_all.sh --quiet --log /var/log/ski-verify.log
   ```
2. **Future:** Consider lightweight uptime-kuma container (~50MB RAM) for a web dashboard

**Status:** Verification scripts created. Cron setup pending.

---

## MEDIUM

### 7. Single Point of Failure — LM Studio

**Problem:** LM Studio on the Windows host is the sole inference provider. If it crashes or the host goes down, all containers lose their AI capabilities.

**Solution:**
- With Bonsai Prism 8B's small footprint (<2GB), running a CPU-based **Ollama** fallback on the VM becomes practical
- Add LM Studio health check to `verify_all.sh` (done)
- Document LM Studio restart procedure
- Long-term: auto-failover via OpenClaw routing

**Status:** Partially addressed (health checks). Ollama fallback is a future task.

---

### 8. No Backup Strategy

**Problem:** No backups for the Obsidian Vault, Docker volumes, or system configs.

**Solution:**
- **Vault:** Robocopy/rsync script to NAS (12TB available)
- **Docker volumes:** `docker run --rm -v <volume>:/data -v /backup:/backup alpine tar czf /backup/<name>.tar.gz /data`
- **Model files:** No backup needed (re-downloadable), but maintain a model inventory list
- **Configs:** Tracked in this git repository

**Status:** Planned for future milestone.

---

### 9. Telegram Not Connected

**Problem:** @MegamarphBot token exists but the Telegram → DeerFlow pipeline is not wired up.

**Solution:**
1. Configure OpenClaw to receive Telegram webhooks
2. Route commands from OpenClaw to DeerFlow via LangGraph API
3. Set up Telegram webhook: `https://api.telegram.org/bot<TOKEN>/setWebhook?url=<OPENCLAW_URL>`

**Note:** This requires a public URL or tunnel (ngrok/Cloudflare Tunnel) since Telegram needs to reach OpenClaw.

**Status:** Pending.

---

### 10. No TLS Encryption

**Problem:** All traffic between Host and VM is unencrypted HTTP/SMB on the LAN.

**Assessment:** This is **acceptable** for a local-only deployment on `192.168.178.x/24` behind a router. The risk is low unless:
- Other untrusted devices are on the same network
- The system is ever exposed to the internet

**If TLS is needed later:**
- Use a reverse proxy (nginx/traefik) with self-signed certs
- SMBv3 already supports encryption: add `seal` to mount options

**Status:** Documented as acceptable risk.
