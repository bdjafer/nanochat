---
name: gpu-manage
description: Manage Lambda Labs GPU instances — launch, check status, stop, and track costs. Use whenever the user needs GPU compute or you need to verify instance state.
---

## GPU Instance Management

You manage Lambda Labs GPU instances for the 2D Merge Attention research project. **Cost discipline is paramount** — instances cost ~$3/GPU/hr.

### Before ANY GPU operation

1. Source the API key: `source /home/user/nanochat/.env` (must contain `LAMBDA_API_KEY`)
2. If `.env` doesn't exist, ask the user to provide their Lambda API key.

### Available commands

Run these via `bash /home/user/nanochat/infra/gpu.sh <command>`:

- **`status`** — List all running instances with uptime, cost accrued, and instance type. **Run this first, always.**
- **`launch <instance_type> [region]`** — Launch a new instance. Instance types:
  - `gpu_1x_h100_sxm5` — Single H100 (~$3/hr) — Phase 1
  - `gpu_8x_h100_sxm5` — 8×H100 node (~$24/hr) — Phase 2+
  - Ask the user to confirm before launching. Show the hourly cost.
- **`stop <instance_id>`** — Terminate an instance. **Always confirm with user first.**
- **`stop-all`** — Terminate ALL running instances. Emergency cost control.
- **`ssh <instance_id>`** — Print SSH command to connect.
- **`cost [days]`** — Show cost summary from the log. Default: last 7 days.
- **`setup <instance_id>`** — Run initial setup on a new instance (clone repo, install deps).

### Cost tracking

Every launch and stop is automatically logged to `experiments/cost_log.csv` with timestamp, action, instance_id, instance_type, and estimated cost.

### Safety rules

1. **NEVER** launch an instance without checking `status` first — there may already be one running.
2. **NEVER** launch 8×H100 without explicit user approval (that's $24/hr).
3. **ALWAYS** remind the user to stop instances when a training run completes.
4. If an instance has been running >2 hours with no active training, warn the user.
5. At session end, **always** check status and remind about running instances.

### Workflow

Typical workflow for running an experiment:
```
1. /gpu-manage status              → Check what's running
2. /gpu-manage launch gpu_1x_h100  → Launch (with user confirmation)
3. /gpu-manage ssh <id>            → Get SSH command
4. [run experiment on instance]
5. /gpu-manage stop <id>           → Shut down when done
6. /gpu-manage cost                → Review spending
```
