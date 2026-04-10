# SKI Auto Research Program

## Objective

Optimize the training code in `train.py` to achieve the lowest possible
validation bits-per-byte (val_bpb) within a fixed 5-minute wall-clock budget
per experiment.

## Current Setup

- **GPU:** NVIDIA RTX 3060 · 12GB VRAM · CUDA
- **Agent LLM:** Bonsai Prism 8B via LM Studio (localhost:1234)
- **Metric:** val_bpb (lower is better, vocabulary-size-independent)
- **Budget:** 5 minutes wall-clock per experiment

## Research Directions

Try the following categories of improvements, one at a time:

### 1. Learning Rate & Schedule
- Experiment with learning rate warmup schedules
- Try cosine annealing, linear decay, or one-cycle policies
- Adjust peak learning rate

### 2. Architecture Tweaks
- Modify attention head count or embedding dimensions
- Try different positional encoding schemes
- Experiment with layer normalization placement (pre-norm vs post-norm)

### 3. Optimizer Settings
- Tune AdamW beta parameters and weight decay
- Try gradient clipping thresholds
- Experiment with Muon optimizer parameters if available

### 4. Data & Batching
- Adjust batch size vs gradient accumulation tradeoffs
- Experiment with sequence length
- Try different data sampling strategies

### 5. Regularization
- Dropout rates per layer
- Label smoothing
- Weight initialization strategies

## Rules

1. Only modify `train.py` — never touch `prepare.py` or this file
2. Each experiment must complete within the 5-minute budget
3. Keep changes small and isolated (one idea per experiment)
4. If val_bpb improves, the change is kept; otherwise it is discarded
5. Log every experiment with its change description and result
6. Do NOT reduce model quality for speed — optimize both together
