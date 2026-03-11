---
name: run-experiment
description: Run a structured training experiment with proper configuration capture, logging, and result archival. Use when launching any nanochat training run.
---

## Structured Experiment Runner

Every training run in this project must be a **tracked experiment**. This ensures reproducibility and clean comparison between variants.

### Before running

1. Determine which phase this experiment belongs to (Phase 1, 2, 3, etc.)
2. Determine which variant this is (baseline, complex-A, complex-A-half-heads, etc.)
3. Check that no conflicting experiment is already running (`/gpu-manage status`)

### Creating an experiment

Use the experiment runner script:

```bash
python /home/user/nanochat/infra/experiment.py create \
  --phase 1 \
  --variant "baseline" \
  --depth 8 \
  --description "Phase 1 baseline: unmodified nanochat depth 8" \
  --gpu-instance <instance_id>
```

This creates a directory under `experiments/` with:
- `config.json` — Full experiment configuration (all args, git SHA, timestamp)
- `notes.md` — Human-readable description and hypothesis
- Symlinks for logs and checkpoints

### Running the training

The experiment runner wraps nanochat's training script:

```bash
python /home/user/nanochat/infra/experiment.py run <experiment_id> \
  -- [extra nanochat training args]
```

Or, if running on a remote GPU instance, generate the remote command:

```bash
python /home/user/nanochat/infra/experiment.py remote-cmd <experiment_id>
```

### After training completes

```bash
python /home/user/nanochat/infra/experiment.py finish <experiment_id>
```

This:
- Copies final metrics (loss curves, CORE scores) into the experiment directory
- Updates `experiments/registry.json` with final results
- Reminds you to shut down the GPU instance

### Experiment naming convention

`p{phase}_{variant}_{depth}d_{timestamp}`

Example: `p1_baseline_8d_20260311_143022`

### Single-variable discipline

When creating an experiment, the runner will compare your config against existing experiments in the same phase. If more than one parameter differs from the comparison variant, it will **warn you**. This is a guardrail, not a hard block — sometimes you intentionally change multiple things.

### Phase 1 specific configs

For Phase 1, use these settings:
- `--depth 8`
- Reduced data: `--num-iterations` set to ~2000 steps (enough for signal, not full convergence)
- Flash Attention disabled for complex variants
- Single GPU

Variants:
1. Baseline: stock nanochat `--depth 8`
2. Complex-A: `--depth 8 --complex-attention optionA`
3. Complex-A-half-heads: `--depth 8 --complex-attention optionA --num-heads-divisor 2`
