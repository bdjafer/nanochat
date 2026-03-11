#!/usr/bin/env python3
"""Experiment runner for 2D Merge Attention research.

Handles experiment creation, configuration capture, execution tracking,
and result archival. Enforces single-variable-at-a-time discipline.
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
EXPERIMENTS_DIR = PROJECT_DIR / "experiments"
REGISTRY_FILE = EXPERIMENTS_DIR / "registry.json"


def load_registry():
    if REGISTRY_FILE.exists():
        return json.loads(REGISTRY_FILE.read_text())
    return {"experiments": []}


def save_registry(registry):
    EXPERIMENTS_DIR.mkdir(parents=True, exist_ok=True)
    REGISTRY_FILE.write_text(json.dumps(registry, indent=2) + "\n")


def get_git_sha():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=PROJECT_DIR, text=True
        ).strip()
    except subprocess.CalledProcessError:
        return "unknown"


def generate_experiment_id(phase, variant, depth):
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    return f"p{phase}_{variant}_{depth}d_{ts}"


def cmd_create(args):
    exp_id = generate_experiment_id(args.phase, args.variant, args.depth)
    exp_dir = EXPERIMENTS_DIR / exp_id
    exp_dir.mkdir(parents=True, exist_ok=True)

    config = {
        "experiment_id": exp_id,
        "phase": args.phase,
        "variant": args.variant,
        "depth": args.depth,
        "description": args.description,
        "gpu_instance": args.gpu_instance or "",
        "git_sha": get_git_sha(),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "status": "created",
        "extra_args": args.extra_args if hasattr(args, "extra_args") else [],
        # Phase 1 defaults
        "flash_attention": args.variant == "baseline",
        "complex_attention": "none" if args.variant == "baseline" else args.variant,
    }

    (exp_dir / "config.json").write_text(json.dumps(config, indent=2) + "\n")

    notes = f"""# Experiment: {exp_id}

## Phase {args.phase} — {args.variant}

**Description:** {args.description}

**Hypothesis:** {"Baseline reference run." if args.variant == "baseline" else "Complex attention with 2D merge preserves relational information, improving learning efficiency."}

**Config:**
- Depth: {args.depth}
- Flash Attention: {config['flash_attention']}
- Complex attention: {config['complex_attention']}
- Git SHA: {config['git_sha']}

## Observations

(Fill in during/after training)

## Result

(Fill in after training completes)
"""
    (exp_dir / "notes.md").write_text(notes)

    # Single-variable check
    registry = load_registry()
    same_phase = [
        e for e in registry["experiments"]
        if e.get("phase") == args.phase and e.get("status") != "abandoned"
    ]
    if same_phase:
        for other in same_phase:
            diffs = []
            for key in ["depth", "complex_attention", "flash_attention"]:
                if config.get(key) != other.get(key):
                    diffs.append(key)
            if len(diffs) > 1:
                print(f"WARNING: Multiple variables differ from {other['experiment_id']}:")
                for d in diffs:
                    print(f"  {d}: {other.get(d)} -> {config.get(d)}")
                print("This violates single-variable discipline. Proceed with caution.")

    # Register
    registry["experiments"].append(config)
    save_registry(registry)

    print(f"Created experiment: {exp_id}")
    print(f"Directory: {exp_dir}")
    return exp_id


def cmd_list(args):
    registry = load_registry()
    phase_filter = getattr(args, "phase", None)
    experiments = registry["experiments"]
    if phase_filter:
        experiments = [e for e in experiments if e.get("phase") == phase_filter]

    if not experiments:
        print("No experiments found.")
        return

    print(f"{'ID':<45} {'Phase':<7} {'Variant':<20} {'Status':<12} {'Depth'}")
    print("-" * 95)
    for e in experiments:
        print(f"{e['experiment_id']:<45} {e.get('phase', '?'):<7} "
              f"{e.get('variant', '?'):<20} {e.get('status', '?'):<12} "
              f"{e.get('depth', '?')}")


def cmd_remote_cmd(args):
    exp_dir = EXPERIMENTS_DIR / args.experiment_id
    if not exp_dir.exists():
        print(f"ERROR: Experiment {args.experiment_id} not found.")
        sys.exit(1)

    config = json.loads((exp_dir / "config.json").read_text())

    # Build the training command
    train_args = [
        "cd nanochat &&",
        "uv run torchrun --standalone --nproc_per_node=1",
        "scripts/base_train.py",
        f"--depth {config['depth']}",
    ]

    if not config.get("flash_attention", True):
        train_args.append("--no-flash-attention")

    if config.get("complex_attention", "none") != "none":
        train_args.append(f"--complex-attention {config['complex_attention']}")

    # Phase 1: reduced training
    if config.get("phase") == 1:
        train_args.append("--num-iterations 2000")

    # Add any extra args
    for extra in config.get("extra_args", []):
        train_args.append(extra)

    # Logging
    exp_id = config["experiment_id"]
    train_args.append(f"2>&1 | tee training_{exp_id}.log")

    cmd = " \\\n  ".join(train_args)
    print("Run this on the GPU instance:")
    print()
    print(cmd)
    print()
    print(f"After training, copy results back:")
    print(f"  scp ubuntu@<ip>:nanochat/training_{exp_id}.log experiments/{exp_id}/")


def cmd_finish(args):
    exp_dir = EXPERIMENTS_DIR / args.experiment_id
    if not exp_dir.exists():
        print(f"ERROR: Experiment {args.experiment_id} not found.")
        sys.exit(1)

    config = json.loads((exp_dir / "config.json").read_text())
    config["status"] = "completed"
    config["completed_at"] = datetime.now(timezone.utc).isoformat()
    (exp_dir / "config.json").write_text(json.dumps(config, indent=2) + "\n")

    # Update registry
    registry = load_registry()
    for e in registry["experiments"]:
        if e["experiment_id"] == args.experiment_id:
            e["status"] = "completed"
            e["completed_at"] = config["completed_at"]
            break
    save_registry(registry)

    print(f"Marked {args.experiment_id} as completed.")
    print()
    print("Next steps:")
    print("  1. Copy training logs and metrics to the experiment directory")
    print("  2. Update experiments/{}/notes.md with observations".format(args.experiment_id))
    print("  3. Run /analyze-results to compare against other variants")
    print("  4. SHUT DOWN THE GPU INSTANCE if not needed")


def main():
    parser = argparse.ArgumentParser(description="Experiment runner for 2D Merge Attention")
    sub = parser.add_subparsers(dest="command")

    # create
    p_create = sub.add_parser("create", help="Create a new experiment")
    p_create.add_argument("--phase", type=int, required=True)
    p_create.add_argument("--variant", required=True)
    p_create.add_argument("--depth", type=int, required=True)
    p_create.add_argument("--description", required=True)
    p_create.add_argument("--gpu-instance", default="")
    p_create.set_defaults(func=cmd_create)

    # list
    p_list = sub.add_parser("list", help="List experiments")
    p_list.add_argument("--phase", type=int)
    p_list.set_defaults(func=cmd_list)

    # remote-cmd
    p_remote = sub.add_parser("remote-cmd", help="Generate remote training command")
    p_remote.add_argument("experiment_id")
    p_remote.set_defaults(func=cmd_remote_cmd)

    # finish
    p_finish = sub.add_parser("finish", help="Mark experiment as completed")
    p_finish.add_argument("experiment_id")
    p_finish.set_defaults(func=cmd_finish)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()
