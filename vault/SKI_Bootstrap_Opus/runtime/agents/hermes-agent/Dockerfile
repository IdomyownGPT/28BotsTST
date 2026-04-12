# ═══════════════════════════════════════════════════════════════
# Hermes Agent — SKI Reasoning Engine
# Proxy zu LM Studio mit 3x3 Sephirotischer Profil-Matrix,
# Tool-Calling und Obsidian-Vault Memory.
#
# Multi-Stage Build fuer kleineres Image (~180 MB).
# ═══════════════════════════════════════════════════════════════

# ---------- Stage 1: Builder ----------
FROM python:3.11-slim AS builder

WORKDIR /build

COPY requirements.txt ./
RUN pip install --no-cache-dir --target=/install -r requirements.txt

# ---------- Stage 2: Runtime ----------
FROM python:3.11-slim AS runtime

# Nur das Minimum: curl fuer Healthcheck, ripgrep fuer vault_search
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN groupadd --system --gid 1000 hermes \
 && useradd  --system --uid 1000 --gid 1000 --home /app --shell /bin/false hermes

WORKDIR /app

# Installierte Pakete aus dem Builder uebernehmen
COPY --from=builder /install /usr/local/lib/python3.11/site-packages

# App-Code
COPY --chown=hermes:hermes hermes/ ./hermes/

# Vault-Mount-Punkt vorbereiten
RUN mkdir -p /app/vault && chown -R hermes:hermes /app

USER hermes

EXPOSE 9377

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    SKI_HERMES_VAULT=/app/vault

# Waitress-WSGI statt Flask-Dev-Server: multi-threaded, production-grade.
CMD ["waitress-serve", "--listen=*:9377", "--threads=8", "hermes.wsgi:app"]
