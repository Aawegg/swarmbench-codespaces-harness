#!/bin/bash
# Usage:  ./scripts/run_stable.sh <task_path>
#
# Submission-grade run: oracle + single + multi at -k 1 -n 1 (the documented
# minimum). For extra-confidence repeated trials (NOT required for submission):
#     N_ATTEMPTS=3 N_CONCURRENT=2 ./scripts/run_stable.sh tasks/<dir>
#
# Keep N_CONCURRENT <= 2 on an 8 GiB Codespace or multi-agent trials may OOM.
set -euo pipefail
source "$(dirname "$0")/env.sh"

TASK="${1:?usage: run_stable.sh <task_path>}"
TASK_ABS="$(cd "$TASK" && pwd)"

N_ATTEMPTS="${N_ATTEMPTS:-1}"
N_CONCURRENT="${N_CONCURRENT:-1}"

cd "$HARBOR_DIR"

echo "=== ORACLE (k=1 n=1) ==="
uv run harbor run \
  -p "$TASK_ABS" \
  -a oracle \
  -k 1 -n 1 \
  --job-name "oracle" \
  --jobs-dir "$TASK_ABS/execution_logs" \
  --ve FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
  --quiet

echo ""
echo "=== SINGLE (k=$N_ATTEMPTS n=$N_CONCURRENT) ==="
uv run harbor run \
  -p "$TASK_ABS" \
  -a swarm-kimi-single \
  -m "$SWARM_MODEL" \
  -k "$N_ATTEMPTS" -n "$N_CONCURRENT" \
  --job-name "single-kimi-agent" \
  --jobs-dir "$TASK_ABS/execution_logs" \
  --ve FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
  --ae FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
  --quiet

echo ""
echo "=== MULTI (k=$N_ATTEMPTS n=$N_CONCURRENT) ==="
uv run harbor run \
  -p "$TASK_ABS" \
  -a swarm-kimi-multi \
  -m "$SWARM_MODEL" \
  -k "$N_ATTEMPTS" -n "$N_CONCURRENT" \
  --job-name "multi-kimi-agent" \
  --jobs-dir "$TASK_ABS/execution_logs" \
  --ve FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
  --ae FIREWORKS_API_KEY="$FIREWORKS_API_KEY" \
  --quiet

echo ""
echo "=== SUMMARY ==="
"$(dirname "$0")/show_rewards.sh" "$TASK_ABS"
