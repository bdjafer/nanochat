#!/usr/bin/env bash
# Lambda Labs GPU Instance Manager
# Usage: bash infra/gpu.sh <command> [args...]
#
# Commands: status, launch, stop, stop-all, ssh, cost, setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COST_LOG="$PROJECT_DIR/experiments/cost_log.csv"
API_BASE="https://cloud.lambdalabs.com/api/v1"

# Load API key
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
fi

if [[ -z "${LAMBDA_API_KEY:-}" ]]; then
    echo "ERROR: LAMBDA_API_KEY not set. Create .env with: LAMBDA_API_KEY=your_key"
    exit 1
fi

AUTH_HEADER="Authorization: Bearer $LAMBDA_API_KEY"

# Ensure cost log exists
mkdir -p "$(dirname "$COST_LOG")"
if [[ ! -f "$COST_LOG" ]]; then
    echo "timestamp,action,instance_id,instance_type,hourly_rate,notes" > "$COST_LOG"
fi

log_cost() {
    local action="$1" instance_id="$2" instance_type="${3:-}" hourly_rate="${4:-}" notes="${5:-}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$action,$instance_id,$instance_type,$hourly_rate,$notes" >> "$COST_LOG"
}

# Hourly rates (approximate, USD)
get_rate() {
    case "${1:-}" in
        gpu_1x_h100_sxm5)  echo "3.29" ;;
        gpu_1x_a100_sxm4)  echo "1.29" ;;
        gpu_8x_h100_sxm5)  echo "23.92" ;;
        gpu_8x_a100_sxm4)  echo "10.32" ;;
        *)                  echo "0.00" ;;
    esac
}

cmd_status() {
    echo "=== Lambda Labs Instance Status ==="
    local response
    response=$(curl -s -H "$AUTH_HEADER" "$API_BASE/instances")

    local count
    count=$(echo "$response" | python3 -c "
import json, sys
from datetime import datetime, timezone
data = json.load(sys.stdin)
instances = data.get('data', [])
if not instances:
    print('No running instances.')
    sys.exit(0)
print(f'Running instances: {len(instances)}')
print()
total_hourly = 0
for inst in instances:
    iid = inst['id']
    itype = inst['instance_type']['name']
    status = inst['status']
    ip = inst.get('ip', 'pending')
    region = inst.get('region', {}).get('name', '?')
    # Calculate uptime
    launched = inst.get('launched_at', '')
    if launched:
        try:
            launch_dt = datetime.fromisoformat(launched.replace('Z', '+00:00'))
            uptime = datetime.now(timezone.utc) - launch_dt
            hours = uptime.total_seconds() / 3600
            uptime_str = f'{hours:.1f}h'
        except:
            hours = 0
            uptime_str = '?'
    else:
        hours = 0
        uptime_str = 'pending'
    # Cost estimate
    rates = {
        'gpu_1x_h100_sxm5': 3.29, 'gpu_1x_a100_sxm4': 1.29,
        'gpu_8x_h100_sxm5': 23.92, 'gpu_8x_a100_sxm4': 10.32,
    }
    rate = rates.get(itype, 0)
    cost = rate * hours
    total_hourly += rate
    print(f'  ID:     {iid}')
    print(f'  Type:   {itype}')
    print(f'  Status: {status}')
    print(f'  IP:     {ip}')
    print(f'  Region: {region}')
    print(f'  Uptime: {uptime_str}')
    print(f'  Rate:   \${rate:.2f}/hr')
    print(f'  Accrued: ~\${cost:.2f}')
    print()
print(f'Total hourly burn: \${total_hourly:.2f}/hr')
if total_hourly > 0:
    print(f'WARNING: Instances are running! Remember to stop when done.')
")
    echo "$count"
}

cmd_launch() {
    local instance_type="${1:-gpu_1x_h100_sxm5}"
    local region="${2:-}"
    local rate
    rate=$(get_rate "$instance_type")

    echo "Launching instance:"
    echo "  Type: $instance_type"
    echo "  Rate: \$$rate/hr"

    local payload
    if [[ -n "$region" ]]; then
        payload="{\"region_name\": \"$region\", \"instance_type_name\": \"$instance_type\", \"ssh_key_names\": [], \"quantity\": 1}"
    else
        payload="{\"instance_type_name\": \"$instance_type\", \"ssh_key_names\": [], \"quantity\": 1}"
    fi

    local response
    response=$(curl -s -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" \
        -d "$payload" "$API_BASE/instance-operations/launch")

    local instance_id
    instance_id=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
ids = data.get('data', {}).get('instance_ids', [])
if ids:
    print(ids[0])
else:
    error = data.get('error', {})
    print(f'LAUNCH FAILED: {error.get(\"message\", json.dumps(data))}', file=sys.stderr)
    sys.exit(1)
")

    if [[ $? -eq 0 ]]; then
        echo "Launched: $instance_id"
        log_cost "launch" "$instance_id" "$instance_type" "$rate" ""
        echo ""
        echo "Instance is booting. Run 'bash infra/gpu.sh status' to check when ready."
        echo "REMINDER: Stop this instance when done! \$$rate/hr"
    fi
}

cmd_stop() {
    local instance_id="$1"
    echo "Stopping instance: $instance_id"

    local response
    response=$(curl -s -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" \
        -d "{\"instance_ids\": [\"$instance_id\"]}" "$API_BASE/instance-operations/terminate")

    echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
terminated = data.get('data', {}).get('terminated_instances', [])
if terminated:
    for t in terminated:
        print(f'Terminated: {t[\"id\"]}')
else:
    error = data.get('error', {})
    print(f'STOP FAILED: {error.get(\"message\", json.dumps(data))}')
"
    log_cost "stop" "$instance_id" "" "" ""
}

cmd_stop_all() {
    echo "Stopping ALL instances..."
    local response
    response=$(curl -s -H "$AUTH_HEADER" "$API_BASE/instances")

    local ids
    ids=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
instances = data.get('data', [])
for inst in instances:
    print(inst['id'])
")

    if [[ -z "$ids" ]]; then
        echo "No running instances to stop."
        return
    fi

    while IFS= read -r id; do
        cmd_stop "$id"
    done <<< "$ids"
}

cmd_ssh() {
    local instance_id="$1"
    local response
    response=$(curl -s -H "$AUTH_HEADER" "$API_BASE/instances/$instance_id")

    echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
inst = data.get('data', {})
ip = inst.get('ip', '')
if ip:
    print(f'ssh ubuntu@{ip}')
else:
    print('Instance IP not yet available. Wait for boot to complete.')
"
}

cmd_cost() {
    local days="${1:-7}"
    echo "=== Cost Summary (last $days days) ==="

    python3 -c "
import csv, sys
from datetime import datetime, timezone, timedelta

cost_log = '$COST_LOG'
cutoff = datetime.now(timezone.utc) - timedelta(days=$days)

launches = {}  # instance_id -> (launch_time, instance_type, hourly_rate)
total_cost = 0.0

with open(cost_log) as f:
    reader = csv.DictReader(f)
    for row in reader:
        ts = datetime.fromisoformat(row['timestamp'].replace('Z', '+00:00'))
        if ts < cutoff:
            continue
        action = row['action']
        iid = row['instance_id']
        if action == 'launch':
            rate = float(row.get('hourly_rate', 0))
            launches[iid] = (ts, row.get('instance_type', ''), rate)
        elif action == 'stop' and iid in launches:
            launch_ts, itype, rate = launches[iid]
            hours = (ts - launch_ts).total_seconds() / 3600
            cost = rate * hours
            total_cost += cost
            print(f'  {iid[:12]}... {itype:30s} {hours:6.1f}h  \${cost:8.2f}')
            del launches[iid]

# Still-running instances
for iid, (launch_ts, itype, rate) in launches.items():
    hours = (datetime.now(timezone.utc) - launch_ts).total_seconds() / 3600
    cost = rate * hours
    total_cost += cost
    print(f'  {iid[:12]}... {itype:30s} {hours:6.1f}h  \${cost:8.2f}  (STILL RUNNING)')

print(f'')
print(f'Total estimated cost: \${total_cost:.2f}')
"
}

cmd_setup() {
    local instance_id="$1"
    echo "Getting SSH info for instance $instance_id..."

    local ip
    ip=$(curl -s -H "$AUTH_HEADER" "$API_BASE/instances/$instance_id" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('data', {}).get('ip', ''))
")

    if [[ -z "$ip" ]]; then
        echo "ERROR: Instance IP not available yet. Wait for boot."
        exit 1
    fi

    echo "Setting up instance at $ip..."
    echo "Run these commands on the remote instance:"
    echo ""
    echo "  # Clone and setup"
    echo "  git clone https://github.com/bdjafer/nanochat.git"
    echo "  cd nanochat"
    echo "  git checkout claude/2d-merge-attention-DfRZ2"
    echo "  pip install uv && uv sync --extra gpu"
    echo ""
    echo "  # Verify GPU"
    echo "  python -c 'import torch; print(torch.cuda.device_count(), \"GPUs available\")'"
}

# --- Main dispatch ---
case "${1:-help}" in
    status)    cmd_status ;;
    launch)    cmd_launch "${2:-gpu_1x_h100_sxm5}" "${3:-}" ;;
    stop)      cmd_stop "${2:?Usage: gpu.sh stop <instance_id>}" ;;
    stop-all)  cmd_stop_all ;;
    ssh)       cmd_ssh "${2:?Usage: gpu.sh ssh <instance_id>}" ;;
    cost)      cmd_cost "${2:-7}" ;;
    setup)     cmd_setup "${2:?Usage: gpu.sh setup <instance_id>}" ;;
    help|*)
        echo "Usage: bash infra/gpu.sh <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  status              List running instances with costs"
        echo "  launch [type] [reg] Launch new instance (default: gpu_1x_h100_sxm5)"
        echo "  stop <id>           Terminate an instance"
        echo "  stop-all            Terminate ALL instances"
        echo "  ssh <id>            Print SSH command"
        echo "  cost [days]         Show cost summary (default: 7 days)"
        echo "  setup <id>          Print setup commands for new instance"
        echo ""
        echo "Instance types:"
        echo "  gpu_1x_h100_sxm5    Single H100 (~\$3.29/hr) - Phase 1"
        echo "  gpu_1x_a100_sxm4    Single A100 (~\$1.29/hr) - Phase 1 budget"
        echo "  gpu_8x_h100_sxm5    8x H100 (~\$23.92/hr) - Phase 2+"
        echo "  gpu_8x_a100_sxm4    8x A100 (~\$10.32/hr) - Phase 2+ budget"
        ;;
esac
