---
name: analyze-results
description: Analyze and compare experiment results — loss curves, CORE scores, parameter counts, wall-clock times. Use after experiments complete.
---

## Experiment Analysis

Compare training runs to determine whether the complex attention hypothesis shows signal.

### Available analyses

Run via `python /home/user/nanochat/infra/results.py <command>`:

- **`compare <exp_id_1> <exp_id_2> [...]`** — Side-by-side comparison table
- **`loss-curve <exp_id_1> <exp_id_2> [...]`** — Plot loss curves (saves PNG)
- **`summary <phase>`** — Summary of all experiments in a phase
- **`decision <phase>`** — Evaluate decision gate for a phase

### What to compare (Phase 1)

For Phase 1, the key metrics are:

| Metric | What it tells us |
|--------|-----------------|
| Training loss at matched steps | Does complex attention learn faster? |
| Final validation loss (BPB) | Does complex attention generalize better? |
| CORE score (if available) | Does it translate to downstream tasks? |
| Wall-clock time per step | What's the computational overhead? |
| Parameter count | Are we comparing fairly? |

### Decision gate evaluation

For Phase 1, the decision logic is:
1. If Complex-A achieves **lower loss** than baseline at matched steps → **PROCEED** to Phase 2
2. If Complex-A-half-heads **matches** baseline (full heads, real) → **strong signal**, prioritize head-count ablation
3. If **no measurable difference** → try Options B, C. If still nothing → **STOP**
4. If complex variant is **unstable** (loss spikes, NaN) → debug optimizer, don't abandon

### Reporting

After analysis, update `experiments/phase_{N}_report.md` with:
- Comparison tables
- Key findings
- Decision: proceed / stop / investigate
- Next steps

### Reading experiment data

Experiment results live in `experiments/<exp_id>/`:
- `config.json` — What was run
- `metrics.json` — Final metrics (loss, CORE, etc.)
- `loss_curve.csv` — Step-by-step training loss
- `notes.md` — Observations and annotations

The registry at `experiments/registry.json` indexes all experiments.
