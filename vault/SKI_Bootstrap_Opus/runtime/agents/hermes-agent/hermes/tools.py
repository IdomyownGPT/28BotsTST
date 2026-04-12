# ═══════════════════════════════════════════════════════════════
# Hermes — Tool-Calling Implementation
#
# Standard-Toolset fuer SKI-Konversationen:
#   - vault_read   : Datei aus /app/vault lesen
#   - vault_search : ripgrep ueber den Vault
#   - vault_write  : Markdown-Notiz in memory/ ablegen
#   - profile_switch: Profil innerhalb einer Session wechseln
#
# Tools werden im OpenAI-Format spezifiziert und serverseitig
# im Proxy ausgefuehrt. Safety: Alle Pfade werden auf /app/vault
# eingeschraenkt (Path-Traversal wird blockiert).
# ═══════════════════════════════════════════════════════════════

import json
import logging
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

log = logging.getLogger("hermes.tools")

VAULT_ROOT = Path(os.environ.get("SKI_HERMES_VAULT", "/app/vault")).resolve()
MEMORY_DIR = VAULT_ROOT / "memory"
MAX_READ_BYTES = 64 * 1024  # 64 KB safety cap
MAX_SEARCH_HITS = 20


# ── OpenAI Tool-Schema Definitionen ─────────────────────────────
TOOL_SCHEMAS = [
    {
        "type": "function",
        "function": {
            "name": "vault_read",
            "description": (
                "Liest eine Datei aus dem SKI Obsidian Vault. "
                "Pfad ist relativ zu /app/vault. Liefert maximal 64 KB."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Relativer Pfad im Vault, z.B. 'memory/2026-04/plan.md'",
                    }
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "vault_search",
            "description": (
                "Durchsucht den SKI Vault per ripgrep nach einem Suchbegriff. "
                "Liefert bis zu 20 Treffer mit Datei, Zeile und Snippet."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Suchbegriff oder regex.",
                    }
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "vault_write",
            "description": (
                "Schreibt eine Markdown-Notiz in /app/vault/memory/<YYYY-MM>/<slug>.md. "
                "YAML-Frontmatter mit Title, Tags und Timestamp wird automatisch "
                "ergaenzt. Ueberschreibt existierende Notizen mit gleichem slug."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "Titel der Notiz"},
                    "content": {"type": "string", "description": "Markdown Body"},
                    "tags": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Liste von Tags (optional)",
                    },
                },
                "required": ["title", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "profile_switch",
            "description": (
                "Wechselt das Hermes-Profil fuer die aktuelle Anfrage. "
                "Profile der 3x3 Sephirotischen Matrix: kether-alpha/beta/gamma, "
                "tiferet-alpha/beta/gamma, malkuth-alpha/beta/gamma."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Profil-Name (z.B. 'kether-alpha')",
                    }
                },
                "required": ["name"],
            },
        },
    },
]


# ── Safety: Pfad in den Vault einsperren ────────────────────────
def _resolve_vault_path(rel_path: str) -> Path:
    """Resolve a vault-relative path, blocking traversal."""
    if not rel_path or ".." in rel_path.split("/"):
        raise ValueError(f"invalid path: {rel_path!r}")
    p = (VAULT_ROOT / rel_path).resolve()
    if not str(p).startswith(str(VAULT_ROOT)):
        raise ValueError(f"path escapes vault: {rel_path!r}")
    return p


# ── Tool-Implementationen ───────────────────────────────────────
def vault_read(path: str) -> dict:
    try:
        p = _resolve_vault_path(path)
    except ValueError as e:
        return {"error": str(e)}
    if not p.exists():
        return {"error": f"not found: {path}"}
    if not p.is_file():
        return {"error": f"not a file: {path}"}
    try:
        data = p.read_bytes()[:MAX_READ_BYTES]
        return {
            "path": path,
            "size": p.stat().st_size,
            "truncated": p.stat().st_size > MAX_READ_BYTES,
            "content": data.decode("utf-8", errors="replace"),
        }
    except Exception as e:
        return {"error": f"read error: {e}"}


def vault_search(query: str) -> dict:
    if not query or len(query) > 500:
        return {"error": "query missing or too long"}
    if not VAULT_ROOT.exists():
        return {"error": f"vault not mounted: {VAULT_ROOT}"}
    try:
        result = subprocess.run(
            [
                "rg",
                "--max-count", "3",
                "--max-columns", "200",
                "--no-heading",
                "--line-number",
                "--color", "never",
                "--",
                query,
                str(VAULT_ROOT),
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except FileNotFoundError:
        # Fallback auf grep wenn rg nicht verfuegbar
        result = subprocess.run(
            ["grep", "-rn", "--max-count=3", "--", query, str(VAULT_ROOT)],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        return {"error": "search timeout"}

    hits = []
    for line in result.stdout.splitlines()[:MAX_SEARCH_HITS]:
        m = re.match(r"^(.*?):(\d+):(.*)$", line)
        if not m:
            continue
        file_path, line_no, snippet = m.groups()
        try:
            rel = str(Path(file_path).relative_to(VAULT_ROOT))
        except ValueError:
            rel = file_path
        hits.append(
            {"path": rel, "line": int(line_no), "snippet": snippet.strip()[:200]}
        )
    return {"query": query, "count": len(hits), "hits": hits}


def vault_write(title: str, content: str, tags: list | None = None) -> dict:
    if not title or not content:
        return {"error": "title and content required"}
    slug = re.sub(r"[^a-z0-9-]+", "-", title.lower()).strip("-")[:80]
    if not slug:
        return {"error": "title produced empty slug"}

    ym = datetime.utcnow().strftime("%Y-%m")
    target_dir = MEMORY_DIR / ym
    try:
        target_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        return {"error": f"cannot create dir: {e}"}

    target = target_dir / f"{slug}.md"
    try:
        target.resolve().relative_to(VAULT_ROOT)
    except ValueError:
        return {"error": "path escapes vault"}

    ts = datetime.utcnow().isoformat() + "Z"
    tag_line = ", ".join(tags) if tags else ""
    frontmatter = (
        "---\n"
        f"title: {json.dumps(title)}\n"
        f"created: {ts}\n"
        f"tags: [{tag_line}]\n"
        "source: hermes-agent\n"
        "---\n\n"
    )
    try:
        target.write_text(frontmatter + content, encoding="utf-8")
    except Exception as e:
        return {"error": f"write error: {e}"}
    return {
        "path": str(target.relative_to(VAULT_ROOT)),
        "bytes": target.stat().st_size,
        "created": ts,
    }


def profile_switch(name: str) -> dict:
    # Actual switch happens in the request loop — this tool just reports intent.
    from hermes.profiles import PROFILES

    if name not in PROFILES:
        return {"error": f"unknown profile: {name}", "available": list(PROFILES.keys())}
    return {"switched_to": name, "name": PROFILES[name]["name"]}


# ── Dispatcher ──────────────────────────────────────────────────
DISPATCH = {
    "vault_read": vault_read,
    "vault_search": vault_search,
    "vault_write": vault_write,
    "profile_switch": profile_switch,
}


def execute_tool(name: str, arguments: str | dict) -> str:
    """Run a tool and return its JSON-serialized result."""
    if name not in DISPATCH:
        return json.dumps({"error": f"unknown tool: {name}"})
    try:
        args = arguments if isinstance(arguments, dict) else json.loads(arguments or "{}")
    except json.JSONDecodeError as e:
        return json.dumps({"error": f"invalid arguments JSON: {e}"})
    try:
        result = DISPATCH[name](**args)
    except TypeError as e:
        return json.dumps({"error": f"bad arguments: {e}"})
    except Exception as e:
        log.exception("tool %s failed", name)
        return json.dumps({"error": f"tool error: {e}"})
    return json.dumps(result, ensure_ascii=False)


def list_tool_names() -> list:
    return [t["function"]["name"] for t in TOOL_SCHEMAS]
