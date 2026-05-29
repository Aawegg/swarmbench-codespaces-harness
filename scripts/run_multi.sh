#!/bin/bash
# Usage:  ./scripts/run_multi.sh <task_path>
# Multi-agent run, 1x1. ~5-15 min.
set -euo pipefail
source "$(dirname "$0")/env.sh"

TASK="${1:?usage: run_multi.sh <task_path>}"
TASK_ABS="$(cd "$TASK" && pwd)"

cd "$HARBOR_DIR"

uv run harbor run \
  -p "$TASK_ABS" \
  -a swarm-kimi-multi \
  -m "$SWARM_MODEL" \
  -k 1 -n 1 \
  --job-name "multi-kimi-agent" \
  --jobs-dir "$TASK_ABS/execution_logs" \
  --ve FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
  --ae FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
  --quiet
