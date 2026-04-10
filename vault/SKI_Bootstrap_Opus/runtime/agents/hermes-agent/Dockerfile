# Hermes Agent — SKI Reasoning Engine
# NousResearch Hermes für Multi-Profil-Inferenz
FROM python:3.11-slim

WORKDIR /app

# System-Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Python-Dependencies
COPY requirements.txt* ./
RUN pip install --no-cache-dir -r requirements.txt 2>/dev/null || \
    pip install --no-cache-dir openai requests

COPY . .

EXPOSE 9377

CMD ["python", "-m", "hermes"]
