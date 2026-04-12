#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════
# Hermes Agent — SKI Reasoning Engine
#
# HTTP API auf Port 9377 — Proxy zu LM Studio mit:
#   - 3x3 Sephirotische Profil-Matrix (System-Prompts)
#   - Pinned Hermes 4.x Modell (ENV: SKI_HERMES_MODEL)
#   - Tool-Calling (vault_read/search/write, profile_switch)
#   - Session-basiertes Memory via Obsidian Vault (JSON-L)
#   - Streaming (SSE)
#
# Endpoints:
#   GET  /health               — Health Check
#   GET  /profiles             — Alle Profile
#   GET  /tools                — Aktives Toolset
#   GET  /sessions             — Session Liste
#   GET  /sessions/<id>        — Session History
#   DEL  /sessions/<id>        — Session loeschen
#   GET  /memory/search?q=     — Vault grep
#   POST /chat                 — Einfacher Chat (+session_id)
#   POST /v1/chat/completions  — OpenAI-kompatibel (+tools, +stream)
# ═══════════════════════════════════════════════════════════════

import json
import logging
import os
import time

import httpx
from flask import Flask, Response, request, jsonify, stream_with_context
from openai import OpenAI

from hermes.memory import (
    append_message,
    delete_session,
    ensure_vault,
    list_sessions,
    load_history,
    read_session_raw,
)
from hermes.profiles import PROFILES, get_profile, list_profiles
from hermes.tools import (
    TOOL_SCHEMAS,
    execute_tool,
    list_tool_names,
    vault_search,
)

logging.basicConfig(level=logging.INFO, format="[Hermes] %(message)s")
log = logging.getLogger("hermes")

app = Flask(__name__)

# ── Configuration ──────────────────────────────────────────────
LM_STUDIO_URL = os.environ.get("SKI_LM_STUDIO_BASE_URL", "http://192.168.178.90:1234/v1")
DEFAULT_PROFILE = os.environ.get("SKI_HERMES_DEFAULT_PROFILE", "tiferet-beta")
PINNED_MODEL = os.environ.get("SKI_HERMES_MODEL", "hermes-4.3-36b")
FALLBACK_MODEL = os.environ.get("SKI_HERMES_MODEL_FALLBACK", "hermes-3-llama-3.1-8b")
TOOL_CALLING = os.environ.get("SKI_HERMES_TOOL_CALLING", "true").lower() == "true"
MAX_TOOL_ROUNDS = int(os.environ.get("SKI_HERMES_MAX_TOOL_ROUNDS", "3"))

client = OpenAI(
    base_url=LM_STUDIO_URL,
    api_key="not-needed",
    timeout=httpx.Timeout(60.0, connect=5.0),
)

# ── Model-Cache (5 min TTL) ────────────────────────────────────
_MODEL_CACHE = {"ts": 0.0, "ids": [], "bound": None}
_MODEL_TTL = 300.0


def _fetch_models() -> list:
    """Query LM Studio for loaded models (cached 5 min)."""
    now = time.time()
    if now - _MODEL_CACHE["ts"] < _MODEL_TTL and _MODEL_CACHE["ids"]:
        return _MODEL_CACHE["ids"]
    try:
        resp = client.models.list()
        ids = [m.id for m in resp.data] if resp.data else []
    except Exception as e:
        log.warning("LM Studio models unreachable: %s", e)
        ids = []
    _MODEL_CACHE["ts"] = now
    _MODEL_CACHE["ids"] = ids
    return ids


def _match_model(needle: str, ids: list) -> str | None:
    """Substring match over LM Studio ids (handles quant suffixes)."""
    needle = (needle or "").lower()
    if not needle:
        return None
    for mid in ids:
        if needle in mid.lower():
            return mid
    return None


def resolve_model() -> str:
    """Return the best-matching model id for the pinned config."""
    ids = _fetch_models()
    if not ids:
        return PINNED_MODEL  # LM Studio accepts this; will fail gracefully on /chat
    for candidate in (PINNED_MODEL, FALLBACK_MODEL):
        m = _match_model(candidate, ids)
        if m:
            return m
    log.warning(
        "Neither %r nor %r found in LM Studio (%d models). Using first loaded.",
        PINNED_MODEL, FALLBACK_MODEL, len(ids),
    )
    return ids[0]


def startup_init() -> None:
    """Called on import from wsgi.py — logs config, warms caches."""
    log.info("=" * 60)
    log.info("SKI Hermes Agent starting")
    log.info("LM Studio: %s", LM_STUDIO_URL)
    log.info("Pinned model: %s (fallback: %s)", PINNED_MODEL, FALLBACK_MODEL)
    log.info("Default profile: %s (%d total)", DEFAULT_PROFILE, len(PROFILES))
    log.info("Tool-calling: %s", "enabled" if TOOL_CALLING else "disabled")
    if TOOL_CALLING:
        log.info("Tools: %s", ", ".join(list_tool_names()))
    vstatus = ensure_vault()
    log.info(
        "Vault: %s (%s)",
        vstatus.get("vault"),
        "writable" if vstatus.get("writable") else "READ-ONLY/unavailable",
    )
    bound = resolve_model()
    _MODEL_CACHE["bound"] = bound
    log.info("Model bound: %s", bound)
    log.info("=" * 60)


# ── Helper: tool-call loop ─────────────────────────────────────
def _run_with_tools(messages: list, model: str, tools: list,
                    temperature: float, max_tokens: int) -> dict:
    """Run chat.completions with tool-call loop. Returns final OpenAI response dict."""
    rounds = 0
    while True:
        resp = client.chat.completions.create(
            model=model,
            messages=messages,
            tools=tools,
            temperature=temperature,
            max_tokens=max_tokens,
        )
        msg = resp.choices[0].message
        tool_calls = getattr(msg, "tool_calls", None) or []
        if not tool_calls or rounds >= MAX_TOOL_ROUNDS:
            return resp.model_dump()

        # Append assistant message as-is, then each tool result
        messages.append(msg.model_dump(exclude_none=True))
        for tc in tool_calls:
            fn = tc.function
            result = execute_tool(fn.name, fn.arguments)
            log.info("tool %s -> %d chars", fn.name, len(result))
            messages.append({
                "role": "tool",
                "tool_call_id": tc.id,
                "name": fn.name,
                "content": result,
            })
        rounds += 1


# ══════════════════════════════════════════════════════════════
# Endpoints
# ══════════════════════════════════════════════════════════════

@app.route("/health", methods=["GET"])
def health():
    ids = _fetch_models()
    bound = _MODEL_CACHE.get("bound") or (resolve_model() if ids else None)
    return jsonify({
        "status": "ok",
        "service": "hermes-agent",
        "lm_studio": "connected" if ids else "unreachable",
        "models_loaded": len(ids),
        "model_bound": bound,
        "default_profile": DEFAULT_PROFILE,
        "tool_calling": TOOL_CALLING,
    })


@app.route("/profiles", methods=["GET"])
def profiles():
    return jsonify({
        "profiles": list_profiles(),
        "default": DEFAULT_PROFILE,
        "details": {
            name: {
                "name": p["name"],
                "temperature": p["temperature"],
                "max_tokens": p["max_tokens"],
            }
            for name, p in PROFILES.items()
        },
    })


@app.route("/tools", methods=["GET"])
def tools_route():
    return jsonify({
        "enabled": TOOL_CALLING,
        "max_rounds": MAX_TOOL_ROUNDS,
        "tools": TOOL_SCHEMAS,
    })


@app.route("/sessions", methods=["GET"])
def sessions_list():
    return jsonify({"sessions": list_sessions()})


@app.route("/sessions/<session_id>", methods=["GET"])
def sessions_get(session_id):
    return jsonify({
        "session_id": session_id,
        "messages": read_session_raw(session_id),
    })


@app.route("/sessions/<session_id>", methods=["DELETE"])
def sessions_delete(session_id):
    result = delete_session(session_id)
    status = 200 if "error" not in result else 400
    return jsonify(result), status


@app.route("/memory/search", methods=["GET"])
def memory_search():
    q = request.args.get("q", "").strip()
    if not q:
        return jsonify({"error": "query parameter 'q' required"}), 400
    return jsonify(vault_search(q))


@app.route("/chat", methods=["POST"])
def chat():
    """Simple chat endpoint with optional session memory.

    Body: {"message": "...", "profile": "tiferet-beta", "session_id": "default"}
    """
    data = request.get_json(force=True) or {}
    message = (data.get("message") or "").strip()
    profile_name = data.get("profile") or DEFAULT_PROFILE
    session_id = data.get("session_id") or "default"
    use_tools = data.get("tools", TOOL_CALLING)

    if not message:
        return jsonify({"error": "message is required"}), 400

    profile = get_profile(profile_name)
    model = resolve_model()

    # Build messages: system + history + new user
    messages = [{"role": "system", "content": profile["system"]}]
    history = load_history(session_id) if session_id else []
    messages.extend(history)
    messages.append({"role": "user", "content": message})

    # Persist user message before call so crashes don't lose it
    append_message(session_id, "user", message, profile=profile_name, model=model)

    try:
        if use_tools:
            result = _run_with_tools(
                messages, model, TOOL_SCHEMAS,
                profile["temperature"], profile["max_tokens"],
            )
            reply = result["choices"][0]["message"].get("content") or ""
            tool_calls = result["choices"][0]["message"].get("tool_calls")
        else:
            resp = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=profile["temperature"],
                max_tokens=profile["max_tokens"],
            )
            reply = resp.choices[0].message.content or ""
            tool_calls = None

        append_message(
            session_id, "assistant", reply,
            profile=profile_name, model=model, tool_calls=tool_calls,
        )
        return jsonify({
            "reply": reply,
            "profile": profile_name,
            "model": model,
            "session_id": session_id,
        })
    except Exception as e:
        log.error("LM Studio error: %s", e)
        return jsonify({"error": str(e)}), 502


@app.route("/v1/chat/completions", methods=["POST"])
def chat_completions():
    """OpenAI-compatible chat completions with tool-calling + streaming.

    Reads optional X-Hermes-Profile header to inject profile system prompt.
    Accepts standard OpenAI body: messages, temperature, max_tokens, tools, stream.
    """
    data = request.get_json(force=True) or {}
    profile_name = request.headers.get("X-Hermes-Profile", DEFAULT_PROFILE)
    profile = get_profile(profile_name)
    model = data.get("model") or resolve_model()
    messages = data.get("messages", [])
    stream = bool(data.get("stream"))

    # Inject system prompt if none present
    if not messages or messages[0].get("role") != "system":
        messages.insert(0, {"role": "system", "content": profile["system"]})

    # Inject default tools if caller didn't supply any
    tools = data.get("tools")
    if tools is None and TOOL_CALLING:
        tools = TOOL_SCHEMAS

    temperature = data.get("temperature", profile["temperature"])
    max_tokens = data.get("max_tokens", profile["max_tokens"])

    # Streaming: pass-through SSE, no tool-loop (tool calls in streaming are
    # unreliable upstream — caller can disable stream if tools are needed).
    if stream:
        def sse():
            try:
                gen = client.chat.completions.create(
                    model=model,
                    messages=messages,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    stream=True,
                )
                for chunk in gen:
                    yield f"data: {chunk.model_dump_json()}\n\n"
                yield "data: [DONE]\n\n"
            except Exception as e:
                log.error("stream error: %s", e)
                err = json.dumps({"error": {"message": str(e), "type": "upstream_error"}})
                yield f"data: {err}\n\n"

        return Response(
            stream_with_context(sse()),
            mimetype="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    # Non-streaming: full tool-loop if tools are active
    try:
        if tools:
            result = _run_with_tools(
                messages, model, tools, temperature, max_tokens,
            )
            return jsonify(result)
        resp = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
        )
        return jsonify(resp.model_dump())
    except Exception as e:
        log.error("LM Studio error: %s", e)
        return jsonify({"error": {"message": str(e), "type": "upstream_error"}}), 502


# ══════════════════════════════════════════════════════════════
# Dev entrypoint (waitress is used in production via hermes.wsgi)
# ══════════════════════════════════════════════════════════════

def main():
    port = int(os.environ.get("HERMES_PORT", 9377))
    startup_init()
    log.info("Dev server on :%d (use waitress-serve in production)", port)
    app.run(host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
