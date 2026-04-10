"""
SKI Auto Research — Training Script

THIS FILE IS THE ONLY FILE THE AGENT MODIFIES.

Contains a minimal GPT model, optimizer, and training loop.
The agent proposes changes to improve val_bpb (validation bits-per-byte).

Based on Karpathy's autoresearch pattern, adapted for the SKI system.
"""

import math
import time
import struct
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from pathlib import Path

import config  # NEU: Config importieren für das dynamische Budget

# ── Import data loader from prepare.py ──
from prepare import load_tokens, VOCAB_SIZE

# ══════════════════════════════════════════════════════
# Hyperparameters (agent may modify these)
# ══════════════════════════════════════════════════════

# Model
N_LAYER = 6
N_HEAD = 6
N_EMBD = 384
BLOCK_SIZE = 256
DROPOUT = 0.2

# Training
BATCH_SIZE = 64
LEARNING_RATE = 3e-4
WEIGHT_DECAY = 0.1
BETA1 = 0.9
BETA2 = 0.95
GRAD_CLIP = 1.0

# Schedule
WARMUP_ITERS = 100
MAX_ITERS = 5000
LR_DECAY_ITERS = 5000
MIN_LR = 3e-5

# Evaluation
EVAL_INTERVAL = 250
EVAL_ITERS = 200

# ══════════════════════════════════════════════════════
# Model Definition
# ══════════════════════════════════════════════════════

class CausalSelfAttention(nn.Module):
    def __init__(self):
        super().__init__()
        assert N_EMBD % N_HEAD == 0
        self.c_attn = nn.Linear(N_EMBD, 3 * N_EMBD)
        self.c_proj = nn.Linear(N_EMBD, N_EMBD)
        self.attn_dropout = nn.Dropout(DROPOUT)
        self.resid_dropout = nn.Dropout(DROPOUT)
        self.n_head = N_HEAD
        self.n_embd = N_EMBD

    def forward(self, x):
        B, T, C = x.size()
        q, k, v = self.c_attn(x).split(self.n_embd, dim=2)
        k = k.view(B, T, self.n_head, C // self.n_head).transpose(1, 2)
        q = q.view(B, T, self.n_head, C // self.n_head).transpose(1, 2)
        v = v.view(B, T, self.n_head, C // self.n_head).transpose(1, 2)
        # Use PyTorch scaled_dot_product_attention (Flash Attention when available)
        y = F.scaled_dot_product_attention(q, k, v, is_causal=True, dropout_p=DROPOUT if self.training else 0.0)
        y = y.transpose(1, 2).contiguous().view(B, T, C)
        y = self.resid_dropout(self.c_proj(y))
        return y


class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.c_fc = nn.Linear(N_EMBD, 4 * N_EMBD)
        self.gelu = nn.GELU()
        self.c_proj = nn.Linear(4 * N_EMBD, N_EMBD)
        self.dropout = nn.Dropout(DROPOUT)

    def forward(self, x):
        x = self.c_fc(x)
        x = self.gelu(x)
        x = self.c_proj(x)
        x = self.dropout(x)
        return x


class Block(nn.Module):
    def __init__(self):
        super().__init__()
        self.ln_1 = nn.LayerNorm(N_EMBD)
        self.attn = CausalSelfAttention()
        self.ln_2 = nn.LayerNorm(N_EMBD)
        self.mlp = MLP()

    def forward(self, x):
        x = x + self.attn(self.ln_1(x))
        x = x + self.mlp(self.ln_2(x))
        return x


class GPT(nn.Module):
    def __init__(self):
        super().__init__()
        self.transformer = nn.ModuleDict(dict(
            wte=nn.Embedding(VOCAB_SIZE, N_EMBD),
            wpe=nn.Embedding(BLOCK_SIZE, N_EMBD),
            drop=nn.Dropout(DROPOUT),
            h=nn.ModuleList([Block() for _ in range(N_LAYER)]),
            ln_f=nn.LayerNorm(N_EMBD),
        ))
        self.lm_head = nn.Linear(N_EMBD, VOCAB_SIZE, bias=False)
        self.transformer.wte.weight = self.lm_head.weight  # weight tying

        # Init weights
        self.apply(self._init_weights)
        for pn, p in self.named_parameters():
            if pn.endswith("c_proj.weight"):
                torch.nn.init.normal_(p, mean=0.0, std=0.02 / math.sqrt(2 * N_LAYER))

        n_params = sum(p.numel() for p in self.parameters())
        print(f"Model parameters: {n_params / 1e6:.2f}M")

    def _init_weights(self, module):
        if isinstance(module, nn.Linear):
            torch.nn.init.normal_(module.weight, mean=0.0, std=0.02)
            if module.bias is not None:
                torch.nn.init.zeros_(module.bias)
        elif isinstance(module, nn.Embedding):
            torch.nn.init.normal_(module.weight, mean=0.0, std=0.02)

    def forward(self, idx, targets=None):
        B, T = idx.size()
        assert T <= BLOCK_SIZE, f"Sequence length {T} exceeds block size {BLOCK_SIZE}"
        pos = torch.arange(0, T, dtype=torch.long, device=idx.device)

        tok_emb = self.transformer.wte(idx)
        pos_emb = self.transformer.wpe(pos)
        x = self.transformer.drop(tok_emb + pos_emb)
        for block in self.transformer.h:
            x = block(x)
        x = self.transformer.ln_f(x)

        if targets is not None:
            logits = self.lm_head(x)
            loss = F.cross_entropy(logits.view(-1, logits.size(-1)), targets.view(-1), ignore_index=-1)
        else:
            logits = self.lm_head(x[:, [-1], :])
            loss = None

        return logits, loss

# ══════════════════════════════════════════════════════
# Data Loading
# ══════════════════════════════════════════════════════

train_data = load_tokens("train")
val_data = load_tokens("val")

def get_batch(split: str):
    data = train_data if split == "train" else val_data
    ix = torch.randint(len(data) - BLOCK_SIZE, (BATCH_SIZE,))
    x = torch.stack([torch.from_numpy(data[i:i+BLOCK_SIZE].astype(np.int64)) for i in ix])
    y = torch.stack([torch.from_numpy(data[i+1:i+1+BLOCK_SIZE].astype(np.int64)) for i in ix])
    if torch.cuda.is_available():
        x, y = x.cuda(), y.cuda()
    return x, y

# ══════════════════════════════════════════════════════
# Learning Rate Schedule
# ══════════════════════════════════════════════════════

def get_lr(it):
    if it < WARMUP_ITERS:
        return LEARNING_RATE * it / WARMUP_ITERS
    if it > LR_DECAY_ITERS:
        return MIN_LR
    decay_ratio = (it - WARMUP_ITERS) / (LR_DECAY_ITERS - WARMUP_ITERS)
    coeff = 0.5 * (1.0 + math.cos(math.pi * decay_ratio))
    return MIN_LR + coeff * (LEARNING_RATE - MIN_LR)

# ══════════════════════════════════════════════════════
# Evaluation
# ══════════════════════════════════════════════════════

@torch.no_grad()
def estimate_loss(model):
    out = {}
    model.eval()
    for split in ["train", "val"]:
        losses = torch.zeros(EVAL_ITERS)
        for k in range(EVAL_ITERS):
            X, Y = get_batch(split)
            _, loss = model(X, Y)
            losses[k] = loss.item()
        out[split] = losses.mean().item()
    model.train()
    return out

def loss_to_bpb(loss):
    """Convert cross-entropy loss (nats) to bits-per-byte."""
    # Approximate: bpb = loss * log2(e) / chars_per_token
    # For GPT-2 tokenizer, ~3.5 chars per token on average
    return loss / math.log(2) / 3.5

# ══════════════════════════════════════════════════════
# Training Loop
# ══════════════════════════════════════════════════════

def train():
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")

    model = GPT().to(device)
    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=LEARNING_RATE,
        betas=(BETA1, BETA2),
        weight_decay=WEIGHT_DECAY,
    )

    if device == "cuda":
        model = torch.compile(model)

    best_val_loss = float("inf")
    t0 = time.time()

    for it in range(MAX_ITERS):
        # Check wall-clock budget dynamically
        elapsed = time.time() - t0
        if elapsed > config.WALL_CLOCK_BUDGET_SEC:
            print(f"\n[budget] Wall-clock limit reached at iter {it} ({elapsed:.0f}s)")
            break

        # Learning rate schedule
        lr = get_lr(it)
        for param_group in optimizer.param_groups:
            param_group["lr"] = lr

        # Evaluate periodically
        if it % EVAL_INTERVAL == 0 or it == MAX_ITERS - 1:
            losses = estimate_loss(model)
            val_bpb = loss_to_bpb(losses["val"])
            train_bpb = loss_to_bpb(losses["train"])
            print(f"iter {it:5d} | train_bpb {train_bpb:.4f} | val_bpb {val_bpb:.4f} | lr {lr:.2e} | {elapsed:.0f}s")

            if losses["val"] < best_val_loss:
                best_val_loss = losses["val"]

        # Forward + backward
        X, Y = get_batch("train")
        _, loss = model(X, Y)
        loss.backward()

        # Gradient clipping
        if GRAD_CLIP > 0:
            torch.nn.utils.clip_grad_norm_(model.parameters(), GRAD_CLIP)

        optimizer.step()
        optimizer.zero_grad(set_to_none=True)

    # Final evaluation
    final_losses = estimate_loss(model)
    val_bpb = loss_to_bpb(final_losses["val"])
    elapsed = time.time() - t0
    print(f"\n{'='*60}")
    print(f"RESULT: val_bpb = {val_bpb:.6f}")
    print(f"Time: {elapsed:.1f}s | Iters: {min(it+1, MAX_ITERS)}")
    print(f"{'='*60}")

    return val_bpb


if __name__ == "__main__":
    train()
