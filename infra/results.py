#!/usr/bin/env python3
"""Results analysis for 2D Merge Attention experiments.

Compare experiments, evaluate decision gates, generate reports.
"""

import argparse
import json
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
EXPERIMENTS_DIR = PROJECT_DIR / "experiments"
REGISTRY_FILE = EXPERIMENTS_DIR / "registry.json"


def load_registry():
    if REGISTRY_FILE.exists():
        return json.loads(REGISTRY_FILE.read_text())
    return {"experiments": []}


def load_experiment(exp_id):
    exp_dir = EXPERIMENTS_DIR / exp_id
    config_file = exp_dir / "config.json"
    metrics_file = exp_dir / "metrics.json"

    if not config_file.exists():
        return None

    config = json.loads(config_file.read_text())
    metrics = json.loads(metrics_file.read_text()) if metrics_file.exists() else {}
    return {**config, "metrics": metrics}


def cmd_compare(args):
    experiments = []
    for exp_id in args.experiment_ids:
        exp = load_experiment(exp_id)
        if exp is None:
            print(f"WARNING: Experiment {exp_id} not found, skipping.")
            continue
        experiments.append(exp)

    if len(experiments) < 2:
        print("Need at least 2 experiments to compare.")
        sys.exit(1)

    # Header
    print(f"\n{'Metric':<30}", end="")
    for exp in experiments:
        label = f"{exp['variant']}"
        print(f" {label:<20}", end="")
    print()
    print("-" * (30 + 20 * len(experiments)))

    # Config comparison
    for key in ["depth", "complex_attention", "flash_attention", "phase"]:
        print(f"{key:<30}", end="")
        for exp in experiments:
            val = str(exp.get(key, "?"))
            print(f" {val:<20}", end="")
        print()

    print("-" * (30 + 20 * len(experiments)))

    # Metrics comparison
    all_metric_keys = set()
    for exp in experiments:
        all_metric_keys.update(exp.get("metrics", {}).keys())

    for key in sorted(all_metric_keys):
        print(f"{key:<30}", end="")
        for exp in experiments:
            val = exp.get("metrics", {}).get(key, "—")
            if isinstance(val, float):
                print(f" {val:<20.6f}", end="")
            else:
                print(f" {str(val):<20}", end="")
        print()


def cmd_summary(args):
    registry = load_registry()
    phase_exps = [
        e for e in registry["experiments"]
        if e.get("phase") == args.phase
    ]

    if not phase_exps:
        print(f"No experiments found for Phase {args.phase}.")
        return

    print(f"\n=== Phase {args.phase} Summary ===\n")
    for exp in phase_exps:
        exp_data = load_experiment(exp["experiment_id"])
        status = exp.get("status", "unknown")
        variant = exp.get("variant", "?")
        depth = exp.get("depth", "?")
        metrics = exp_data.get("metrics", {}) if exp_data else {}

        print(f"  {exp['experiment_id']}")
        print(f"    Variant: {variant}, Depth: {depth}, Status: {status}")
        if metrics:
            for k, v in sorted(metrics.items()):
                if isinstance(v, float):
                    print(f"    {k}: {v:.6f}")
                else:
                    print(f"    {k}: {v}")
        print()


def cmd_decision(args):
    registry = load_registry()
    phase_exps = [
        e for e in registry["experiments"]
        if e.get("phase") == args.phase and e.get("status") == "completed"
    ]

    if not phase_exps:
        print(f"No completed experiments for Phase {args.phase}.")
        print("Cannot evaluate decision gate.")
        return

    print(f"\n=== Phase {args.phase} Decision Gate ===\n")

    if args.phase == 1:
        baseline = None
        complex_variants = []
        for exp in phase_exps:
            exp_data = load_experiment(exp["experiment_id"])
            if exp.get("variant") == "baseline":
                baseline = exp_data
            else:
                complex_variants.append(exp_data)

        if not baseline:
            print("No baseline experiment completed. Cannot evaluate.")
            return

        if not complex_variants:
            print("No complex variant experiments completed. Cannot evaluate.")
            return

        baseline_loss = baseline.get("metrics", {}).get("final_val_loss")
        print(f"Baseline final val loss: {baseline_loss or 'NOT RECORDED'}")
        print()

        for cv in complex_variants:
            cv_loss = cv.get("metrics", {}).get("final_val_loss")
            variant = cv.get("variant", "?")
            print(f"{variant} final val loss: {cv_loss or 'NOT RECORDED'}")

            if baseline_loss is not None and cv_loss is not None:
                if cv_loss < baseline_loss:
                    improvement = (baseline_loss - cv_loss) / baseline_loss * 100
                    print(f"  -> SIGNAL DETECTED: {improvement:.1f}% lower loss")
                    print(f"  -> DECISION: Proceed to Phase 2")
                elif cv_loss > baseline_loss * 1.05:
                    print(f"  -> Complex variant is worse. Check for bugs.")
                else:
                    print(f"  -> No meaningful difference.")
            print()

        # Half-heads check
        half_head_variants = [
            cv for cv in complex_variants
            if "half" in cv.get("variant", "").lower()
        ]
        if half_head_variants and baseline_loss is not None:
            for hv in half_head_variants:
                hv_loss = hv.get("metrics", {}).get("final_val_loss")
                if hv_loss is not None and hv_loss <= baseline_loss * 1.02:
                    print("STRONG SIGNAL: Half-heads complex matches full-heads baseline!")
                    print("Prioritize head-count ablation in Phase 4.")

    else:
        print(f"Decision gate for Phase {args.phase} not yet implemented.")
        print("Evaluate manually based on the research plan.")


def main():
    parser = argparse.ArgumentParser(description="Experiment results analysis")
    sub = parser.add_subparsers(dest="command")

    p_compare = sub.add_parser("compare", help="Compare experiments side-by-side")
    p_compare.add_argument("experiment_ids", nargs="+")
    p_compare.set_defaults(func=cmd_compare)

    p_summary = sub.add_parser("summary", help="Summarize all experiments in a phase")
    p_summary.add_argument("phase", type=int)
    p_summary.set_defaults(func=cmd_summary)

    p_decision = sub.add_parser("decision", help="Evaluate decision gate for a phase")
    p_decision.add_argument("phase", type=int)
    p_decision.set_defaults(func=cmd_decision)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()
