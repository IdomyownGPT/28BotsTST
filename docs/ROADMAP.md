# Roadmap

## Current Status (2026-04-04)

### Operational
- [x] LM Studio running on host with API access
- [x] Hyper-V VM (Ubuntu 24.04) configured
- [x] Docker v29.3.1 with 8 containers
- [x] Hermes v0.7.0 with 9 profiles (upgraded from v0.6.0)
- [x] DeerFlow UI accessible at :2026
- [x] OpenClaw container running
- [x] Agent Zero container running
- [x] Milvus VDB running
- [x] Vault SMB share configured
- [x] Verification scripts created

### Needs Attention
- [ ] **DeerFlow Gateway** — Config-path fix (port 8001)
- [ ] **Telegram Bot** — Token exists, webhook not connected
- [ ] **VM RAM** — Increase from 9GB to 16GB
- [ ] **SMB mount** — Add `x-systemd.automount` to fstab
- [ ] **Bonsai Prism 8B** — Load both instances in LM Studio (normal + Symbolect)
- [ ] **Hermes 0.7 integration** — Configure pluggable memory provider (Milvus), credential pools, Camofox port 9377

### Not Started
- [ ] Symbolect/Runes training (M03)
- [ ] GPU training pipeline via WSL2 (M05/M06)
- [ ] FAISS migration (replace Milvus for lower RAM)
- [ ] Hindsight VectorDB integration
- [ ] Backup automation
- [ ] Monitoring dashboard
- [ ] Hermes Milvus memory plugin configuration
- [ ] Hermes credential pool setup for LM Studio multi-key rotation
- [ ] Camofox browser integration (port 9377)
- [ ] **Auto Research** — Setup and first overnight run (M12)

---

## Milestones

### M00 — Foundation ✅
- Host setup, VM provisioning, basic networking
- LM Studio installation and model loading

### M01 — Containerization ✅
- Docker environment on VM
- DeerFlow, OpenClaw, Hermes, Agent Zero, Milvus deployed

### M02 — Integration (Current)
- [ ] Fix DeerFlow Gateway config
- [ ] Connect Telegram → OpenClaw → DeerFlow pipeline
- [ ] Load Bonsai Prism 8B (both instances)
- [ ] Stabilize SMB mount
- [ ] Run `verify_all.sh` with all checks passing

### M03 — Symbolect Training
- [ ] Define Symbolect/Runes vocabulary and grammar
- [ ] Prepare training dataset from vault content
- [ ] Fine-tune Bonsai Prism 8B on Symbolect
- [ ] Load Symbolect instance alongside normal instance
- [ ] Validate Symbolect inference via verify scripts

### M04 — Memory & Learning
- [ ] Configure Hermes memory persistence
- [ ] Integrate Milvus embeddings with Hermes profiles
- [ ] Implement conversation history storage
- [ ] Test profile switching under load

### M05 — GPU Training Pipeline
- [ ] Set up WSL2 on Windows host
- [ ] Configure CUDA toolkit in WSL2
- [ ] Create training scripts for fine-tuning
- [ ] Implement training data pipeline from vault

### M06 — Advanced Training
- [ ] LoRA/QLoRA fine-tuning workflow
- [ ] Automated evaluation benchmarks
- [ ] Model versioning and rollback

### M07 — Vault Intelligence
- [ ] Hindsight VectorDB integration
- [ ] Automatic vault indexing pipeline
- [ ] Semantic search across all vault content
- [ ] FAISS migration (if Milvus RAM is too high)

### M08 — Resilience
- [ ] Ollama fallback on VM (CPU-based)
- [ ] Automated backup scripts (vault, docker volumes)
- [ ] Health monitoring dashboard (uptime-kuma or similar)
- [ ] Auto-restart policies for all containers

### M09 — Telegram Full Integration
- [ ] Telegram → OpenClaw → DeerFlow full pipeline
- [ ] Command routing and response formatting
- [ ] Multi-user support (if needed)
- [ ] Webhook via Cloudflare Tunnel

### M10 — Optimization
- [ ] Tune container memory limits based on real usage
- [ ] Optimize LangGraph worker count
- [ ] Profile Hermes response times per profile
- [ ] Evaluate VRAM usage and model loading strategy

### M11 — Production Readiness
- [ ] All verify scripts pass consistently
- [ ] Cron monitoring active
- [ ] Documentation complete and up-to-date
- [ ] Backup and recovery tested
- [ ] All 9 Hermes profiles validated

### M12 — Auto Research (Karpathy-style experiment loop)
- [ ] Install Python 3.10+ and uv on host
- [ ] Run `07_setup_autoresearch.ps1` on host
- [ ] Prepare training data (run `prepare.py`)
- [ ] Run baseline experiment (verify GPU + training works)
- [ ] Edit `program.md` with SKI-specific research directions
- [ ] First overnight run (200 experiments)
- [ ] Review results in Obsidian (`M12_AutoResearch/AutoResearch_Log.md`)
- [ ] Integrate best findings into production model pipeline
- [ ] Connect Auto Research results to Milvus for experiment embedding search
- [ ] Hook into DeerFlow for triggering experiments via chat

---

## Next Actions (Priority Order)

1. **Fix DeerFlow Gateway** — Investigate logs, fix config path
2. **Load Bonsai Prism 8B** — Both instances in LM Studio
3. **Increase VM RAM** — 9GB → 16GB in Hyper-V settings
4. **Fix SMB fstab** — Add `x-systemd.automount`
5. **Connect Telegram** — Wire up @MegamarphBot → OpenClaw → DeerFlow
6. **Run verify_all.sh** — Fix any remaining failures
7. **Setup Auto Research** — Run `07_setup_autoresearch.ps1`, first overnight run
