#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════
# Hermes Agent — SKI Reasoning Engine
#
# HTTP API auf Port 9377
# Leitet Anfragen an LM Studio weiter mit Profil-System-Prompts.
#
# Endpoints:
#   POST /v1/chat/completions  — OpenAI-kompatibel
#   POST /chat                 — Einfacher Chat
#   GET  /profiles             — Alle Profile
#   GET  /health               — Health Check
# ═══════════════════════════════════════════════════════════════

import os
import json
import logging

from flask import Flask, request, jsonify
from openai import OpenAI

from hermes.profiles import get_profile, list_profiles, PROFILES

logging.basicConfig(level=logging.INFO, format="[Hermes] %(message)s")
log = logging.getLogger("hermes")

app = Flask(__name__)

# ── LM Studio Connection ──
LM_STUDIO_URL = os.environ.get("SKI_LM_STUDIO_BASE_URL", "http://192.168.178.90:1234/v1")
DEFAULT_PROFILE = os.environ.get("SKI_HERMES_DEFAULT_PROFILE", "tiferet-beta")

client = OpenAI(
    base_url=LM_STUDIO_URL,
    api_key="not-needed",
)


def get_available_model():
    """Get the first available model from LM Studio."""
    try:
        models = client.models.list()
        if models.data:
            return models.data[0].id
    except Exception as e:
        log.warning(f"Could not fetch models: {e}")
    return "local-model"


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    try:
        models = client.models.list()
        model_count = len(models.data) if models.data else 0
        lm_status = "connected"
    except Exception:
        model_count = 0
        lm_status = "unreachable"

    return jsonify({
        "status": "ok",
        "service": "hermes-agent",
        "lm_studio": lm_status,
        "models_loaded": model_count,
        "default_profile": DEFAULT_PROFILE,
    })


@app.route("/profiles", methods=["GET"])
def profiles():
    """List all available profiles."""
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


@app.route("/chat", methods=["POST"])
def chat():
    """Simple chat endpoint.

    Body: {"message": "...", "profile": "tiferet-beta"}
    """
    data = request.get_json(force=True)
    message = data.get("message", "")
    profile_name = data.get("profile", DEFAULT_PROFILE)
    history = data.get("history", [])

    if not message:
        return jsonify({"error": "message is required"}), 400

    profile = get_profile(profile_name)
    model = get_available_model()

    messages = [{"role": "system", "content": profile["system"]}]
    messages.extend(history)
    messages.append({"role": "user", "content": message})

    try:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=profile["temperature"],
            max_tokens=profile["max_tokens"],
        )
        reply = response.choices[0].message.content
        return jsonify({
            "reply": reply,
            "profile": profile_name,
            "model": model,
        })
    except Exception as e:
        log.error(f"LM Studio error: {e}")
        return jsonify({"error": str(e)}), 502


@app.route("/v1/chat/completions", methods=["POST"])
def chat_completions():
    """OpenAI-compatible chat completions endpoint.

    Accepts standard OpenAI format. Injects profile system prompt
    if X-Hermes-Profile header is set.
    """
    data = request.get_json(force=True)
    profile_name = request.headers.get("X-Hermes-Profile", DEFAULT_PROFILE)
    profile = get_profile(profile_name)
    model = data.get("model") or get_available_model()

    messages = data.get("messages", [])

    # Inject system prompt if none present
    if not messages or messages[0].get("role") != "system":
        messages.insert(0, {"role": "system", "content": profile["system"]})

    try:
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=data.get("temperature", profile["temperature"]),
            max_tokens=data.get("max_tokens", profile["max_tokens"]),
        )
        # Return raw OpenAI-format response
        return jsonify(response.model_dump())
    except Exception as e:
        log.error(f"LM Studio error: {e}")
        return jsonify({"error": {"message": str(e), "type": "upstream_error"}}), 502


def main():
    port = int(os.environ.get("HERMES_PORT", 9377))
    log.info(f"Starting Hermes Agent on :{port}")
    log.info(f"LM Studio: {LM_STUDIO_URL}")
    log.info(f"Default profile: {DEFAULT_PROFILE}")
    log.info(f"Profiles loaded: {len(PROFILES)}")
    app.run(host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
