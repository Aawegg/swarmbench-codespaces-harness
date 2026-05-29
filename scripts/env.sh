#!/bin/bash
# Source this from any other script:  source "$(dirname "$0")/env.sh"
#
# Fully portable across machines and repo names:
#   - WORKSPACE_ROOT is derived from this file's own location (the parent
#     directory of scripts/), so it works no matter what the repo is called
#     or where it is checked out (Mac, Codespace, anywhere).
#   - If WORKSPACE_ROOT/.env exists (local dev), it is sourced. On a Codespace
#     the secrets are injected as env vars by the devcontainer, so .env is
#     optional.
#   - SWARM_MODEL defaults to SWARM_MODEL_DEDICATED, then SWARM_MODEL_SHARED.
#   - HARBOR_DIR defaults to $WORKSPACE_ROOT/harbor/harbor_src, then
#     $WORKSPACE_ROOT/harbor.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$WORKSPACE_ROOT/.env" ]; then
  # shellcheck disable=SC1091
  source "$WORKSPACE_ROOT/.env"
fi

: "${SWARM_MODEL:=${SWARM_MODEL_DEDICATED:-${SWARM_MODEL_SHARED:-}}}"
export SWARM_MODEL

if [ -z "${HARBOR_DIR:-}" ]; then
  if [ -d "$WORKSPACE_ROOT/harbor/harbor_src" ]; then
    HARBOR_DIR="$WORKSPACE_ROOT/harbor/harbor_src"
  elif [ -d "$WORKSPACE_ROOT/harbor" ]; then
    HARBOR_DIR="$WORKSPACE_ROOT/harbor"
  fi
fi
export HARBOR_DIR

if [ -z "${FIREWORKS_API_KEY:-}" ]; then
  echo "ERROR: FIREWORKS_API_KEY not set (no .env at $WORKSPACE_ROOT/.env and no env var)." >&2
  echo "       On a Codespace, add it under GitHub > Settings > Codespaces > Secrets." >&2
  exit 1
fi

if [ -z "${SWARM_MODEL:-}" ]; then
  echo "ERROR: SWARM_MODEL not set (and no SWARM_MODEL_DEDICATED / SWARM_MODEL_SHARED fallback)." >&2
  exit 1
fi

if [ -z "${HARBOR_DIR:-}" ] || [ ! -d "$HARBOR_DIR" ]; then
  echo "ERROR: HARBOR_DIR (${HARBOR_DIR:-unset}) does not exist." >&2
  echo "       This harness expects harbor vendored at $WORKSPACE_ROOT/harbor/harbor_src." >&2
  exit 1
fi
