# Hermes Model Setup — LM Studio auf dem Windows Host

Der `ski-hermes-agent` Container ist ein Proxy. Die eigentliche Inferenz
laeuft auf dem **Windows Host** (192.168.178.90) in **LM Studio**.
Damit der Proxy deterministisch arbeitet, muss das Ziel-Modell dort
geladen und "sticky" gemacht werden.

## Empfohlene Modelle (Stand April 2026)

| Modell | HuggingFace Repo | Quant | ~Size | VRAM | Einsatz |
|---|---|---|---|---|---|
| **Hermes 4.3-36B** (primaer) | `NousResearch/Hermes-4.3-36B-GGUF` | Q4_K_M | 22 GB | 24+ GB | SOTA non-abliterated, Psyche-trainiert |
| **Hermes 4-70B** (XL) | `NousResearch/Hermes-4-70B-GGUF` | Q4_K_M | 42 GB | 48+ GB | Hybrid reasoning, wenn du zwei 24er hast |
| **Hermes 3-Llama-3.1-8B** (fallback) | `NousResearch/Hermes-3-Llama-3.1-8B-GGUF` | Q4_K_M | 5 GB | 8 GB | Smoke-Test / Laptop |

Der Proxy pinnt auf `hermes-4.3-36b` via ENV-Var `SKI_HERMES_MODEL` in
`runtime/.env`. Match ist per Substring, d.h. LM-Studio-IDs mit Quant-Suffix
wie `hermes-4.3-36b-q4_k_m` werden automatisch getroffen.

## Schritt-fuer-Schritt

### 1. LM Studio oeffnen
Auf dem Windows Host `LM Studio.exe` starten. Linke Navigation:
`Discover` (das Lupen-Symbol).

### 2. Modell suchen und laden
Im Suchfeld eingeben: `NousResearch Hermes-4.3-36B GGUF`
- `Q4_K_M` Variante waehlen (~22 GB) — beste Balance Qualitaet/VRAM.
- Download starten. Je nach Bandbreite 10-30 min.

### 3. Modell konfigurieren
Wenn Download fertig, links auf `My Models` wechseln, Hermes 4.3-36B
auswaehlen und rechts in den Settings:

| Setting | Wert |
|---|---|
| **Context Length** | `16384` (16k) — reicht fuer lange Sessions |
| **GPU Offload** | Max. (alle Layer auf GPU wenn moeglich) |
| **CPU Threads** | Physische Kerne (nicht Logical) |
| **Batch Size** | `512` |
| **Keep in memory** | **aktivieren** — verhindert Auto-Unload |

### 4. Server starten
Links `Developer` (oder `Local Server` je nach LM-Studio-Version):
- `Start Server` klicken.
- Port: `1234` (Standard — entspricht `SKI_LM_STUDIO_BASE_URL`).
- `CORS` aktivieren.
- Das Hermes-Modell als `Loaded Model` markieren.

### 5. Verifikation vom Host aus
```powershell
curl http://localhost:1234/v1/models
```
Sollte eine JSON-Antwort mit `"id": "hermes-4.3-36b..."` liefern.

### 6. Verifikation von der VM aus
```bash
curl http://192.168.178.90:1234/v1/models
# und vom Hermes-Container:
curl http://192.168.178.122:9377/health
```
Die Health-Antwort sollte enthalten:
```json
{
  "lm_studio": "connected",
  "models_loaded": 1,
  "model_bound": "hermes-4.3-36b-q4_k_m",
  "tool_calling": true
}
```

### 7. Smoke-Test Chat
```bash
curl -X POST http://192.168.178.122:9377/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Wer bist du?","session_id":"smoke"}'
```

## Troubleshooting

- **`lm_studio: unreachable`**: LM Studio Server nicht gestartet oder
  Windows-Firewall blockiert Port 1234. Auf dem Host:
  ```powershell
  New-NetFirewallRule -DisplayName "LM Studio" -Direction Inbound `
      -LocalPort 1234 -Protocol TCP -Action Allow
  ```
- **`model_bound: null` obwohl Modell geladen**: `SKI_HERMES_MODEL` in
  `runtime/.env` pruefen. Substring-Match ist case-insensitive aber muss
  in der LM-Studio-ID enthalten sein (`docker logs ski-hermes-agent` zeigt
  bei Startup die geladenen IDs).
- **Modell wird nach Idle entladen**: In LM Studio `Keep in memory` aktivieren
  oder den `Always loaded` Toggle setzen.
- **OOM beim Laden**: Kleinere Quant-Variante (Q4_K_S oder Q3_K_M) oder
  Context auf 8k reduzieren.

## Wechsel auf Hermes-4-70B

Wenn die Maschine genug VRAM hat (48+ GB):
```bash
# runtime/.env
SKI_HERMES_MODEL=hermes-4-70b
```
Container neu starten:
```bash
cd /mnt/28bots_core/runtime && docker compose restart hermes-agent
```
