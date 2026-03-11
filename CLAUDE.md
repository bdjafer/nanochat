# 2D Merge Attention Research — Nanochat

## Project Summary

This project investigates whether **complex-valued (2D) attention scores** improve transformer parameter efficiency compared to standard real-valued (1D) attention. The hypothesis: 2D merges preserve relational information (via phase/angle), making compensatory mechanisms (residual streams, multi-head redundancy, depth) partially redundant.

**Platform:** nanochat — minimal LLM training pipeline. Single complexity dial: `--depth`.
**Branch:** `claude/2d-merge-attention-DfRZ2`

## Current Phase

**Phase 1 — Sanity Check.** Single GPU, depth 8, reduced data. Determine if complex attention produces any measurable signal.

## Repository Structure

```
nanochat/gpt.py          — Model architecture. CausalSelfAttention is the modification target.
nanochat/flash_attention.py — Flash Attention wrapper. Must handle FA3 disable for Phase 1.
scripts/base_train.py    — Main training script.
scripts/base_eval.py     — Evaluation script.
infra/                   — GPU management, experiment runner, cost tracking.
experiments/             — Experiment configs, logs, results, decisions.
```

## Key Conventions

### Cost Discipline
- **ALWAYS** check GPU instance status before and after work. Use `/gpu-manage status`.
- **ALWAYS** shut down GPU instances when not actively training. $3/hr/GPU adds up.
- **NEVER** leave instances running overnight without explicit user approval.
- Log all GPU costs in `experiments/cost_log.csv`.

### Experiment Protocol
- **One variable at a time.** Every experiment compares variants differing in exactly one way.
- **Record everything.** Full loss curves, per-dataset CORE breakdowns, wall-clock times.
- **Respect decision gates.** If a phase shows no signal, STOP. Do not proceed hoping it appears at scale.
- **Use nanochat's existing eval.** Do not build custom eval. CORE score is the primary metric.

### Code Changes
- Modifications go in `nanochat/gpt.py` (CausalSelfAttention) and `nanochat/flash_attention.py`.
- Everything else (data pipeline, optimizer, eval, training loop) stays identical across variants.
- Tag experimental code clearly: `# 2D-MERGE: description`

### Git
- All work on branch `claude/2d-merge-attention-DfRZ2`.
- Commit messages: `[phase N] description` (e.g., `[phase 1] add complex attention Option A`).
- Never force-push. Never push to master.

## Decision Tree

```
Phase 1: Signal? → No → Try Options B, C → Still no → STOP
                 → Yes → Phase 2: Scales? → No → STOP (publish small-scale)
                                           → Yes → Phase 3-5: Measure efficiency
                                                    → 1.1-1.3× → Phase 6
                                                    → 1.5-2.0× → Phase 6+7
                                                    → 2.0×+    → Phase 6+7+8
```

## Phase 1 Variants

1. **Baseline:** unmodified nanochat, depth 8
2. **Complex-A:** complex attention (magnitude softmax, preserve phase), depth 8
3. **Complex-A-half-heads:** same as #2 but head count halved

## Complex Softmax Options

- **Option A (start here):** softmax on magnitudes, multiply by unit phase
- **Option B:** independent softmax on real and imaginary parts
- **Option C:** full complex exponential: exp(z_j) / Σ exp(z_k)

## GPU Management

GPU instances are managed through Lambda Labs API via `infra/gpu.sh`.
- API key stored in `.env` as `LAMBDA_API_KEY`
- Instance type for Phase 1: single H100 or A100
- Instance type for Phase 2+: 8×H100 node
- **Cost tracking is mandatory.** Every launch/stop is logged.

## Flash Attention Constraint

- Phase 1: Disable Flash Attention, use PyTorch SDPA with complex tensors
- Phase 2+: Two coupled real-valued FA3 passes (real components + imaginary components)

## Files NOT to Commit

- `.env` (API keys)
- `wandb/` (experiment tracking data)
- Large checkpoint files (use `.gitignore`)
