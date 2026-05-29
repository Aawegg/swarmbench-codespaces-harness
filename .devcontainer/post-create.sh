#!/usr/bin/env bash
# Portable post-create for the SwarmBench / Harbor Codespaces harness.
# Works in any repo name: all paths are relative to the workspace root.
set -euo pipefail

echo "[post-create] Installing apt tools (tmux, htop, jq, ncdu)..."
sudo apt-get update -qq
sudo apt-get install -y -qq tmux htop jq ncdu

echo "[post-create] Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

# Persist PATH for future shells
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$rc" ]] && ! grep -q '.local/bin' "$rc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
  fi
done

# Make uv / uvx visible to non-interactive ssh sessions too
sudo ln -sf "$HOME/.local/bin/uv"  /usr/local/bin/uv  2>/dev/null || true
sudo ln -sf "$HOME/.local/bin/uvx" /usr/local/bin/uvx 2>/dev/null || true

# Wire SWARM_MODEL from the dedicated secret (devcontainer secrets can't do
# shell substitution, so we do it here once).
if [[ -n "${SWARM_MODEL_DEDICATED:-}" ]] && ! grep -q 'SWARM_MODEL=' "$HOME/.bashrc" 2>/dev/null; then
  echo "export SWARM_MODEL=\"\${SWARM_MODEL:-\$SWARM_MODEL_DEDICATED}\"" >> "$HOME/.bashrc"
fi

echo "[post-create] uv version: $(uv --version 2>&1 || echo 'NOT INSTALLED')"

echo "[post-create] Verifying Docker-in-Docker..."
docker version --format '{{.Server.Version}}' 2>&1 || \
  echo "WARN: docker daemon not reachable yet (usually up a few seconds after start)"

# Sync the harbor venv if harbor is vendored at <repo>/harbor/harbor_src.
if [[ -f harbor/harbor_src/pyproject.toml ]]; then
  echo "[post-create] Found harbor at ./harbor/harbor_src — syncing venv..."
  (cd harbor/harbor_src && uv sync --no-dev) || echo "WARNING: harbor uv sync failed; run it manually."
elif [[ -f harbor/pyproject.toml ]]; then
  echo "[post-create] Found harbor at ./harbor — syncing venv..."
  (cd harbor && uv sync --no-dev) || echo "WARNING: harbor uv sync failed; run it manually."
else
  echo "[post-create] NOTE: no harbor/ found in this repo."
  echo "               This harness expects harbor vendored at ./harbor/harbor_src"
  echo "               (or ./harbor). Add it, then run: (cd harbor/harbor_src && uv sync)"
fi

echo "[post-create] Done."
echo "  - workspace:             $(pwd)"
echo "  - docker:                $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unreachable')"
echo "  - uv:                    $(uv --version 2>/dev/null || echo 'missing')"
echo "  - FIREWORKS_API_KEY:     $([[ -n "${FIREWORKS_API_KEY:-}" ]] && echo set || echo MISSING)"
echo "  - SWARM_MODEL_DEDICATED: ${SWARM_MODEL_DEDICATED:-unset}"
echo "  - SWARM_MODEL_SHARED:    ${SWARM_MODEL_SHARED:-unset}"
