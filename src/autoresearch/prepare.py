"""
SKI Auto Research — Data Preparation

This file is NEVER modified by the agent. It contains fixed data loading
and preprocessing constants used by train.py.

Customize this for your specific training data source.
"""

import os
import struct
import numpy as np
from pathlib import Path

# ── Constants ──
DATA_DIR = Path(__file__).parent / "data"
TRAIN_FILE = DATA_DIR / "train.bin"
VAL_FILE = DATA_DIR / "val.bin"

# Tokenizer vocab size — set to match your tokenizer
VOCAB_SIZE = 50257  # GPT-2 default


def download_and_prepare():
    """Download and tokenize training data if not already present."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    if TRAIN_FILE.exists() and VAL_FILE.exists():
        print(f"[prepare] Data already exists at {DATA_DIR}")
        return

    # Default: use a small text corpus for initial experiments
    # Replace this with your own data pipeline
    print("[prepare] Downloading sample dataset...")

    try:
        import tiktoken
        enc = tiktoken.get_encoding("gpt2")
    except ImportError:
        print("[prepare] tiktoken not installed. Run: uv pip install tiktoken")
        print("[prepare] Creating dummy data for testing...")
        _create_dummy_data()
        return

    # Download a small sample text (Shakespeare for testing)
    import urllib.request
    url = "https://raw.githubusercontent.com/karpathy/char-rnn/master/data/tinyshakespeare/input.txt"
    text_path = DATA_DIR / "input.txt"

    if not text_path.exists():
        urllib.request.urlretrieve(url, text_path)
        print(f"[prepare] Downloaded {text_path}")

    with open(text_path, "r") as f:
        text = f.read()

    tokens = enc.encode(text)
    print(f"[prepare] Total tokens: {len(tokens)}")

    # 90/10 train/val split
    split = int(len(tokens) * 0.9)
    train_tokens = np.array(tokens[:split], dtype=np.uint16)
    val_tokens = np.array(tokens[split:], dtype=np.uint16)

    train_tokens.tofile(TRAIN_FILE)
    val_tokens.tofile(VAL_FILE)
    print(f"[prepare] train.bin: {len(train_tokens)} tokens")
    print(f"[prepare] val.bin:   {len(val_tokens)} tokens")


def _create_dummy_data():
    """Create minimal dummy data for testing the pipeline."""
    n_train = 100_000
    n_val = 10_000
    np.random.seed(42)
    np.random.randint(0, VOCAB_SIZE, size=n_train, dtype=np.uint16).tofile(TRAIN_FILE)
    np.random.randint(0, VOCAB_SIZE, size=n_val, dtype=np.uint16).tofile(VAL_FILE)
    print(f"[prepare] Created dummy data: {n_train} train, {n_val} val tokens")


def load_tokens(split: str) -> np.ndarray:
    """Load tokenized data for a given split ('train' or 'val')."""
    path = TRAIN_FILE if split == "train" else VAL_FILE
    if not path.exists():
        raise FileNotFoundError(f"Data not found at {path}. Run prepare.py first.")
    return np.fromfile(path, dtype=np.uint16)


if __name__ == "__main__":
    download_and_prepare()
