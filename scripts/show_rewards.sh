#!/bin/bash
# Usage:  ./scripts/show_rewards.sh <task_path>
# Reads Harbor result.json files (score nested at stats.evals.<name>.metrics[0].mean)
# and prints oracle/single/multi rewards + the gap.
set -euo pipefail
TASK="${1:?usage: show_rewards.sh <task_path>}"
TASK_ABS="$(cd "$TASK" && pwd)"

python3 - "$TASK_ABS" <<'PY'
import json, sys
from pathlib import Path

def reward_from(p: Path):
    if not p.is_file():
        return None
    try:
        data = json.loads(p.read_text())
    except Exception as e:
        return f"PARSE ERR: {e}"
    evals = (data.get("stats") or {}).get("evals") or {}
    for ev in evals.values():
        metrics = ev.get("metrics") or []
        if metrics and "mean" in metrics[0]:
            return metrics[0]["mean"]
    if "mean_reward" in data:
        return data["mean_reward"]
    return None

root = Path(sys.argv[1]) / "execution_logs"
rewards = {}
for name in ("oracle", "single-kimi-agent", "multi-kimi-agent"):
    rewards[name] = reward_from(root / name / "result.json")

for k, v in rewards.items():
    print(f"  {k:20s} -> {v}")

s = rewards.get("single-kimi-agent")
m = rewards.get("multi-kimi-agent")
o = rewards.get("oracle")
if isinstance(o, (int, float)) and o != 1.0:
    print(f"  {'ORACLE STATUS':20s} -> FAIL  (must be 1.0, got {o})")
if isinstance(s, (int, float)) and isinstance(m, (int, float)):
    gap = m - s
    status = "PASS" if gap >= 0.23 else "FAIL (gap too small)"
    print(f"  {'GAP (multi-single)':20s} -> {gap:+.4f}   (need >= 0.23)")
    print(f"  {'STATUS':20s} -> {status}")
PY
