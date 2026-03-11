#!/usr/bin/env bash
# Session start check: GPU status and cost reminder
# Called automatically by Claude Code on session start

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COST_LOG="$PROJECT_DIR/experiments/cost_log.csv"

echo "=== 2D Merge Attention Research ==="
echo "Branch: claude/2d-merge-attention-VMQJb"
echo ""

# Auto-create .env from environment variable if missing
if [[ ! -f "$PROJECT_DIR/.env" ]] && [[ -n "${LAMBDA_API_KEY:-}" ]]; then
    echo "LAMBDA_API_KEY=$LAMBDA_API_KEY" > "$PROJECT_DIR/.env"
    echo "Auto-created .env from environment variable."
    echo ""
elif [[ ! -f "$PROJECT_DIR/.env" ]]; then
    echo "NOTE: No .env file found. GPU management requires LAMBDA_API_KEY."
    echo "Set LAMBDA_API_KEY env var (auto-creates .env) or: echo 'LAMBDA_API_KEY=your_key' > .env"
    echo ""
fi

# Check SSH key is registered with Lambda (needed for instance launch)
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
    if [[ -n "${LAMBDA_API_KEY:-}" ]]; then
        SSH_KEY_COUNT=$(curl -s --max-time 5 \
            -H "Authorization: Bearer $LAMBDA_API_KEY" \
            "https://cloud.lambdalabs.com/api/v1/ssh-keys" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin).get('data', [])
print(len(data))
" 2>/dev/null || echo "0")
        if [[ "$SSH_KEY_COUNT" -eq 0 ]]; then
            echo "WARNING: No SSH keys registered with Lambda Labs."
            echo "Register one at https://cloud.lambdalabs.com/ssh-keys or via API."
            echo "gpu.sh launch will fail without a registered SSH key."
            echo ""
        fi
    fi
fi

# Check for running instances (only if API key available)
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
    if [[ -n "${LAMBDA_API_KEY:-}" ]]; then
        RESPONSE=$(curl -s --max-time 5 \
            -H "Authorization: Bearer $LAMBDA_API_KEY" \
            "https://cloud.lambdalabs.com/api/v1/instances" 2>/dev/null || echo '{"data":[]}')

        COUNT=$(echo "$RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
instances = data.get('data', [])
print(len(instances))
" 2>/dev/null || echo "0")

        if [[ "$COUNT" -gt 0 ]]; then
            echo "WARNING: $COUNT GPU instance(s) currently running!"
            echo "Run '/gpu-manage status' to see details and costs."
            echo "Remember to stop instances when not training."
        else
            echo "No GPU instances running. (Good — no costs accruing.)"
        fi
        echo ""
    fi
fi

# Show recent cost if log exists
if [[ -f "$COST_LOG" ]]; then
    LINE_COUNT=$(wc -l < "$COST_LOG")
    if [[ "$LINE_COUNT" -gt 1 ]]; then
        echo "Recent GPU activity logged. Run '/gpu-manage cost' for summary."
        echo ""
    fi
fi

# Show experiment status
REGISTRY="$PROJECT_DIR/experiments/registry.json"
if [[ -f "$REGISTRY" ]]; then
    python3 -c "
import json
with open('$REGISTRY') as f:
    reg = json.load(f)
exps = reg.get('experiments', [])
if exps:
    active = [e for e in exps if e.get('status') not in ('completed', 'abandoned')]
    completed = [e for e in exps if e.get('status') == 'completed']
    print(f'Experiments: {len(completed)} completed, {len(active)} active/pending')
" 2>/dev/null || true
fi

echo ""
echo "Skills: /gpu-manage, /run-experiment, /analyze-results, /read-arxiv-paper"
