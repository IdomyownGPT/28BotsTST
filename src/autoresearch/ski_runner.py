"""
SKI Auto Research — Experiment Runner

Autonomous experiment loop adapted from Karpathy's autoresearch.
Uses LM Studio (OpenAI-compatible API) as the agent LLM.

Loop:
  1. Agent reads program.md + current train.py
  2. Agent proposes a single change to train.py
  3. Training runs with 5-minute wall-clock budget
  4. If val_bpb improves → keep; else → revert
  5. Repeat

Usage:
  python ski_runner.py                    # Run with defaults
  python ski_runner.py --max-experiments 50
  python ski_runner.py --budget 180       # 3-minute budget
"""

import argparse
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent))

import config

try:
    from openai import OpenAI
except ImportError:
    print("[ERROR] openai package not found. Install with: uv pip install openai")
    sys.exit(1)


# ══════════════════════════════════════════════════════
# LM Studio Client
# ══════════════════════════════════════════════════════

def get_client() -> OpenAI:
    """Create OpenAI client pointing at LM Studio."""
    return OpenAI(
        base_url=config.LM_STUDIO_BASE_URL,
        api_key="lm-studio",  # LM Studio doesn't require a real key
    )


def agent_propose_change(
    client: OpenAI,
    program: str,
    current_code: str,
    history: list[dict],
) -> tuple[str, str]:
    """
    Ask the agent LLM to propose a single improvement to train.py.

    Returns:
        (description, new_code) — the change description and modified code
    """
    history_text = ""
    if history:
        last_n = history[-10:]  # Show last 10 experiments
        history_text = "\n## Recent Experiments\n\n"
        for h in last_n:
            status = "KEPT" if h.get("kept") else "REVERTED"
            history_text += (
                f"- Experiment {h['id']}: {h['description']} → "
                f"val_bpb={h.get('val_bpb', 'N/A')} [{status}]\n"
            )

    system_prompt = (
        "You are an autonomous ML research agent. Your job is to improve "
        "a training script by making small, targeted modifications. "
        "You may only modify the code between the markers in train.py. "
        "Each change should test ONE idea. Respond with:\n"
        "1. A one-line DESCRIPTION of what you're changing and why\n"
        "2. The complete modified train.py code\n\n"
        "Format your response exactly as:\n"
        "DESCRIPTION: <one line>\n"
        "```python\n<complete train.py code>\n```"
    )

    user_prompt = (
        f"# Research Program\n\n{program}\n\n"
        f"{history_text}\n"
        f"# Current train.py\n\n```python\n{current_code}\n```\n\n"
        "Propose ONE small improvement. Return the complete modified train.py."
    )

    response = client.chat.completions.create(
        model=config.AGENT_MODEL,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        max_tokens=4096,
        temperature=0.7,
    )

    reply = response.choices[0].message.content

    # Parse description
    desc_match = re.search(r"DESCRIPTION:\s*(.+)", reply)
    description = desc_match.group(1).strip() if desc_match else "Unknown change"

    # Parse code block
    code_match = re.search(r"```python\n(.*?)```", reply, re.DOTALL)
    if code_match:
        new_code = code_match.group(1).strip()
    else:
        raise ValueError("Agent did not return a valid code block")

    return description, new_code


# ══════════════════════════════════════════════════════
# Experiment Execution
# ══════════════════════════════════════════════════════

def run_training(budget_sec: int) -> float | None:
    """
    Run train.py and extract val_bpb from output.
    Returns val_bpb or None if training failed.
    """
    try:
        result = subprocess.run(
            [sys.executable, str(config.TRAIN_FILE)],
            capture_output=True,
            text=True,
            timeout=budget_sec + 30,  # Extra buffer for startup/shutdown
            cwd=str(config.BASE_DIR),
        )

        output = result.stdout + result.stderr

        # Extract final RESULT line
        match = re.search(r"RESULT:\s*val_bpb\s*=\s*([\d.]+)", output)
        if match:
            return float(match.group(1))

        # Fallback: find last val_bpb in output
        matches = re.findall(r"val_bpb\s+([\d.]+)", output)
        if matches:
            return float(matches[-1])

        print(f"[runner] Could not extract val_bpb from output")
        print(f"[runner] stdout: {result.stdout[-500:]}")
        return None

    except subprocess.TimeoutExpired:
        print(f"[runner] Training exceeded timeout ({budget_sec + 30}s)")
        return None
    except Exception as e:
        print(f"[runner] Training failed: {e}")
        return None


# ══════════════════════════════════════════════════════
# Logging
# ══════════════════════════════════════════════════════

def log_experiment(experiment: dict):
    """Append experiment result to JSONL log and vault."""
    config.LOG_DIR.mkdir(parents=True, exist_ok=True)
    with open(config.RESULTS_FILE, "a") as f:
        f.write(json.dumps(experiment) + "\n")

    # Copy to vault for Obsidian visibility
    try:
        config.VAULT_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        vault_log = config.VAULT_RESULTS_DIR / "results.jsonl"
        with open(vault_log, "a") as f:
            f.write(json.dumps(experiment) + "\n")

        # Update summary markdown
        update_vault_summary(experiment)
    except Exception as e:
        print(f"[log] Could not write to vault: {e}")


def update_vault_summary(latest: dict):
    """Update a markdown summary in the vault for Obsidian."""
    summary_path = config.VAULT_RESULTS_DIR / "AutoResearch_Log.md"

    header = (
        "# Auto Research Experiment Log\n\n"
        "Auto-generated by SKI Auto Research runner.\n\n"
        "| # | Time | Description | val_bpb | Status |\n"
        "|---|------|-------------|---------|--------|\n"
    )

    # Read existing experiments from JSONL
    results_path = config.VAULT_RESULTS_DIR / "results.jsonl"
    rows = []
    if results_path.exists():
        with open(results_path) as f:
            for line in f:
                try:
                    exp = json.loads(line.strip())
                    status = "Kept" if exp.get("kept") else "Reverted"
                    val = f"{exp.get('val_bpb', 'N/A'):.6f}" if isinstance(exp.get("val_bpb"), float) else "N/A"
                    rows.append(
                        f"| {exp.get('id', '?')} | {exp.get('timestamp', '?')[:19]} | "
                        f"{exp.get('description', '?')[:50]} | {val} | {status} |"
                    )
                except (json.JSONDecodeError, KeyError):
                    continue

    with open(summary_path, "w") as f:
        f.write(header)
        for row in rows:
            f.write(row + "\n")
        f.write(f"\n---\n*Last updated: {datetime.now().isoformat()[:19]}*\n")


# ══════════════════════════════════════════════════════
# Main Loop
# ══════════════════════════════════════════════════════

def run(max_experiments: int, budget_sec: int):
    """Main auto-research loop."""
    print("=" * 60)
    print("  SKI Auto Research Runner")
    print(f"  Agent: {config.AGENT_MODEL} via {config.LM_STUDIO_BASE_URL}")
    print(f"  Budget: {budget_sec}s per experiment")
    print(f"  Max experiments: {max_experiments}")
    print("=" * 60)

    client = get_client()

    # Verify LM Studio connection
    try:
        models = client.models.list()
        available = [m.id for m in models.data]
        print(f"[init] LM Studio models: {available}")
        if config.AGENT_MODEL not in available:
            print(f"[WARN] Model '{config.AGENT_MODEL}' not in available models. "
                  f"Using first available: {available[0]}")
            config.AGENT_MODEL = available[0]
    except Exception as e:
        print(f"[ERROR] Cannot connect to LM Studio: {e}")
        sys.exit(1)

    # Load program
    program = config.PROGRAM_FILE.read_text()

    # Ensure data exists
    print("[init] Checking training data...")
    import prepare
    prepare.download_and_prepare()

    # Get baseline
    print("\n[baseline] Running baseline training...")
    original_code = config.TRAIN_FILE.read_text()
    baseline_bpb = run_training(budget_sec)

    if baseline_bpb is None:
        print("[ERROR] Baseline training failed. Fix train.py before running autoresearch.")
        sys.exit(1)

    print(f"[baseline] val_bpb = {baseline_bpb:.6f}")
    best_bpb = baseline_bpb
    history = []

    log_experiment({
        "id": 0,
        "timestamp": datetime.now().isoformat(),
        "description": "Baseline",
        "val_bpb": baseline_bpb,
        "kept": True,
        "type": "baseline",
    })

    # Experiment loop
    for exp_id in range(1, max_experiments + 1):
        print(f"\n{'─' * 60}")
        print(f"  Experiment {exp_id}/{max_experiments}")
        print(f"  Best val_bpb so far: {best_bpb:.6f}")
        print(f"{'─' * 60}")

        current_code = config.TRAIN_FILE.read_text()

        # 1. Ask agent for a change
        try:
            description, new_code = agent_propose_change(
                client, program, current_code, history
            )
            print(f"[agent] Proposed: {description}")
        except Exception as e:
            print(f"[agent] Failed to propose change: {e}")
            history.append({
                "id": exp_id,
                "timestamp": datetime.now().isoformat(),
                "description": f"Agent error: {e}",
                "val_bpb": None,
                "kept": False,
            })
            continue

        # 2. Backup current code
        backup_code = current_code

        # 3. Write new code
        config.TRAIN_FILE.write_text(new_code)

        # 4. Run training
        print(f"[train] Running experiment (budget: {budget_sec}s)...")
        val_bpb = run_training(budget_sec)

        # 5. Evaluate
        kept = False
        if val_bpb is not None and val_bpb < best_bpb:
            improvement = best_bpb - val_bpb
            print(f"[result] IMPROVEMENT! val_bpb {best_bpb:.6f} → {val_bpb:.6f} "
                  f"(Δ = -{improvement:.6f})")
            best_bpb = val_bpb
            kept = True
        else:
            if val_bpb is not None:
                print(f"[result] No improvement: val_bpb {val_bpb:.6f} >= {best_bpb:.6f}")
            else:
                print(f"[result] Training failed, reverting")
            # Revert
            config.TRAIN_FILE.write_text(backup_code)
            print(f"[result] Reverted to previous code")

        # 6. Log
        experiment = {
            "id": exp_id,
            "timestamp": datetime.now().isoformat(),
            "description": description,
            "val_bpb": val_bpb,
            "best_bpb": best_bpb,
            "kept": kept,
        }
        history.append(experiment)
        log_experiment(experiment)

    # Summary
    kept_count = sum(1 for h in history if h.get("kept"))
    print(f"\n{'=' * 60}")
    print(f"  Auto Research Complete")
    print(f"  Experiments: {len(history)}")
    print(f"  Kept: {kept_count}")
    print(f"  Baseline val_bpb: {baseline_bpb:.6f}")
    print(f"  Final val_bpb:    {best_bpb:.6f}")
    if baseline_bpb > best_bpb:
        print(f"  Improvement:      {baseline_bpb - best_bpb:.6f} ({(baseline_bpb - best_bpb) / baseline_bpb * 100:.2f}%)")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SKI Auto Research Runner")
    parser.add_argument("--max-experiments", type=int, default=config.MAX_EXPERIMENTS)
    parser.add_argument("--budget", type=int, default=config.WALL_CLOCK_BUDGET_SEC,
                        help="Wall-clock budget per experiment in seconds")
    args = parser.parse_args()
    run(args.max_experiments, args.budget)
