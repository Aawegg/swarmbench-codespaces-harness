#!/bin/bash
# Usage:  ./scripts/run_oracle.sh <task_path>
# Expected result: reward = 1.0. Anything else => verifier or solve.sh is broken.
set -euo pipefail
source "$(dirname "$0")/env.sh"

TASK="${1:?usage: run_oracle.sh <task_path>}"
TASK_ABS="$(cd "$TASK" && pwd)"

cd "$HARBOR_DIR"

uv run harbor run \
  -p "$TASK_ABS" \
  -a oracle \
  --job-name "oracle" \
  --jobs-dir "$TASK_ABS/execution_logs" \
  --ve FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
  --ae FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
  --quiet
