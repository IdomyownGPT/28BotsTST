# ═══════════════════════════════════════════════════════════════
# Hermes — Memory & Session Persistence
#
# Gespraeche werden als append-only JSON-L unter
#   /app/vault/sessions/<YYYY-MM-DD>/<session_id>.jsonl
# abgelegt. Markdown-Notizen (fuer Obsidian) landen in
#   /app/vault/memory/<YYYY-MM>/<slug>.md
#
# Keine Vector-DB, kein Milvus — ripgrep reicht fuer den Scope.
# ═══════════════════════════════════════════════════════════════

import json
import logging
import os
import re
from datetime import datetime
from pathlib import Path

log = logging.getLogger("hermes.memory")

VAULT_ROOT = Path(os.environ.get("SKI_HERMES_VAULT", "/app/vault")).resolve()
SESSIONS_DIR = VAULT_ROOT / "sessions"
DEFAULT_HISTORY_LIMIT = int(os.environ.get("SKI_HERMES_HISTORY_LIMIT", "20"))

_SESSION_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{1,64}$")


def _validate_session_id(session_id: str) -> str:
    if not session_id or not _SESSION_ID_RE.match(session_id):
        raise ValueError(f"invalid session_id: {session_id!r}")
    return session_id


def _session_files(session_id: str) -> list[Path]:
    """Return all jsonl files for this session across all dates, sorted oldest-first."""
    if not SESSIONS_DIR.exists():
        return []
    hits = sorted(SESSIONS_DIR.glob(f"*/{session_id}.jsonl"))
    return hits


def _today_path(session_id: str) -> Path:
    day = datetime.utcnow().strftime("%Y-%m-%d")
    return SESSIONS_DIR / day / f"{session_id}.jsonl"


def ensure_vault() -> dict:
    """Called at startup; creates basic layout if missing and reports status."""
    status = {"vault": str(VAULT_ROOT), "writable": False, "created": []}
    try:
        for sub in (SESSIONS_DIR, VAULT_ROOT / "memory"):
            if not sub.exists():
                sub.mkdir(parents=True, exist_ok=True)
                status["created"].append(str(sub.relative_to(VAULT_ROOT)))
        # Write test
        probe = VAULT_ROOT / ".hermes-writable"
        probe.write_text(datetime.utcnow().isoformat() + "Z", encoding="utf-8")
        probe.unlink()
        status["writable"] = True
    except Exception as e:
        log.warning("vault not writable: %s", e)
        status["error"] = str(e)
    return status


def append_message(session_id: str, role: str, content, profile: str = None,
                   model: str = None, tool_calls=None) -> None:
    """Append a single message to the session's JSON-L file."""
    try:
        _validate_session_id(session_id)
    except ValueError as e:
        log.warning("skip append: %s", e)
        return
    path = _today_path(session_id)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        log.warning("cannot create session dir %s: %s", path.parent, e)
        return

    entry = {
        "ts": datetime.utcnow().isoformat() + "Z",
        "role": role,
        "content": content,
    }
    if profile:
        entry["profile"] = profile
    if model:
        entry["model"] = model
    if tool_calls:
        entry["tool_calls"] = tool_calls

    try:
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception as e:
        log.warning("cannot append to %s: %s", path, e)


def load_history(session_id: str, max_msgs: int = None) -> list[dict]:
    """Load the last max_msgs messages across all day-files for this session."""
    try:
        _validate_session_id(session_id)
    except ValueError:
        return []
    limit = max_msgs if max_msgs is not None else DEFAULT_HISTORY_LIMIT
    messages: list[dict] = []
    for p in _session_files(session_id):
        try:
            for line in p.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                # Nur role+content fuer OpenAI-Format durchreichen
                if "role" not in entry or "content" not in entry:
                    continue
                messages.append({"role": entry["role"], "content": entry["content"]})
        except Exception as e:
            log.warning("cannot read %s: %s", p, e)
    return messages[-limit:] if limit else messages


def read_session_raw(session_id: str) -> list[dict]:
    """Return full raw session entries (for GET /sessions/<id>)."""
    try:
        _validate_session_id(session_id)
    except ValueError:
        return []
    raw = []
    for p in _session_files(session_id):
        try:
            for line in p.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    raw.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        except Exception:
            continue
    return raw


def delete_session(session_id: str) -> dict:
    """Delete all files for a session. Refuses to delete 'default'."""
    try:
        _validate_session_id(session_id)
    except ValueError as e:
        return {"error": str(e)}
    if session_id == "default":
        return {"error": "cannot delete default session"}
    removed = []
    for p in _session_files(session_id):
        try:
            p.unlink()
            removed.append(str(p.relative_to(VAULT_ROOT)))
        except Exception as e:
            log.warning("cannot delete %s: %s", p, e)
    return {"deleted": removed, "count": len(removed)}


def list_sessions() -> list[str]:
    """Return distinct session ids found in the vault."""
    if not SESSIONS_DIR.exists():
        return []
    ids = set()
    for p in SESSIONS_DIR.glob("*/*.jsonl"):
        ids.add(p.stem)
    return sorted(ids)
