"""
SKI Auto Research — Configuration

Central configuration for the Auto Research loop.
Reads from environment variables with sensible defaults for the SKI system.
"""

import os
from pathlib import Path

# ── Paths ──
BASE_DIR = Path(__file__).parent
TRAIN_FILE = BASE_DIR / "train.py"
PREPARE_FILE = BASE_DIR / "prepare.py"
PROGRAM_FILE = BASE_DIR / "program.md"
LOG_DIR = BASE_DIR / "logs"
RESULTS_FILE = LOG_DIR / "results.jsonl"

# ── Vault integration ──
# When running on the host, the vault is at D:\28Bots_Core\Obsidian_Vault\root
# Results are symlinked/copied there for Obsidian visibility
VAULT_PATH = Path(os.environ.get(
    "SKI_AUTORESEARCH_VAULT",
    os.environ.get("SKI_VAULT_PATH", r"D:\28Bots_Core\Obsidian_Vault\root")
))
VAULT_RESULTS_DIR = VAULT_PATH / "SKI_Cookbook" / "M12_AutoResearch"

# ── LM Studio (Agent LLM) ──
LM_STUDIO_BASE_URL = os.environ.get(
    "SKI_LM_STUDIO_BASE_URL",
    "http://localhost:1234/v1"
)
AGENT_MODEL = os.environ.get("SKI_AUTORESEARCH_MODEL", "bonsai-prism-8b")

# ── Experiment settings ──
WALL_CLOCK_BUDGET_SEC = int(os.environ.get("SKI_AUTORESEARCH_BUDGET", "300"))  # 5 minutes
MAX_EXPERIMENTS = int(os.environ.get("SKI_AUTORESEARCH_MAX_EXPERIMENTS", "100"))
METRIC_NAME = "val_bpb"  # validation bits-per-byte (lower = better)

# ── GPU ──
CUDA_DEVICE = os.environ.get("CUDA_VISIBLE_DEVICES", "0")

# ── Logging ──
LOG_LEVEL = os.environ.get("SKI_AUTORESEARCH_LOG_LEVEL", "INFO")
