# SwarmBench / Harbor Codespaces Harness

A portable, repo-name-agnostic harness for running Harbor SwarmBench tasks
(oracle / single-agent / multi-agent) on a free GitHub Codespace. Drop it into
**any** task repo, add three secrets, and you can run your own tasks on free
cloud Docker — no local Docker needed.

This bundle contains **no tasks** — only the execution machinery. You bring
your own `tasks/` directory and your own `harbor/` engine.

---

## What's in the bundle

```
.devcontainer/
  devcontainer.json     # Docker-in-Docker + Python + uv + gh + the 3 secrets
  post-create.sh        # installs uv/tmux/jq, syncs harbor venv
scripts/
  env.sh                # derives WORKSPACE_ROOT + HARBOR_DIR (repo-name-agnostic)
  run_stable.sh         # oracle + single + multi (submission-grade)
  run_single.sh         # single-agent only, 1x1
  run_multi.sh          # multi-agent only, 1x1
  run_oracle.sh         # oracle only (must return reward 1.0)
  show_rewards.sh       # prints oracle/single/multi rewards + the gap
```

## Prerequisites in your repo

1. **harbor must be present** at `<repo>/harbor/harbor_src` (vendored), the
   same layout the run scripts expect. `env.sh` also falls back to
   `<repo>/harbor`. If you don't have harbor yet, add it and confirm
   `harbor/harbor_src/pyproject.toml` exists.
2. **Your tasks** live under `<repo>/tasks/<task_dir>/` with the standard
   Harbor layout (`task.toml`, `instruction.md`, `environment/`, `solution/`,
   `tests/`, `decomposition.yaml`).

## Install (one time)

1. Copy `.devcontainer/` and `scripts/` from this bundle into the **root** of
   your task repo. (If you already have a `scripts/` dir, merge — don't clobber
   your own helpers; these five `run_*` + `show_rewards` + `env.sh` are all the
   harness needs.)
2. Make the scripts executable and commit:
   ```bash
   chmod +x scripts/*.sh .devcontainer/post-create.sh
   git add .devcontainer scripts && git commit -m "Add Codespaces harness" && git push
   ```

## Add the three secrets (required)

GitHub → your avatar → **Settings** → **Codespaces** → **Secrets** →
**New secret**. Add all three, and under *Repository access* grant each to
this repo:

| Secret | Value |
|---|---|
| `FIREWORKS_API_KEY` | your Fireworks API key |
| `SWARM_MODEL_DEDICATED` | your dedicated Fireworks deployment URL (preferred) |
| `SWARM_MODEL_SHARED` | a serverless Kimi model URL (fallback) |

`devcontainer.json` declares these three names, so the Codespace injects them
automatically as env vars. `env.sh` picks `SWARM_MODEL` from
`SWARM_MODEL_DEDICATED`, falling back to `SWARM_MODEL_SHARED`.

> The Fireworks key bills usage to whoever owns that Fireworks account. Use
> your own key, or get explicit sign-off before sharing one.

## Create the Codespace

On your repo: green **Code** button → **Codespaces** tab →
**Create codespace on main**. First boot runs `post-create.sh` (~5-10 min:
installs uv/tmux, syncs the harbor venv).

When it's done the terminal banner should show `FIREWORKS_API_KEY: set`. If it
says `MISSING`, the secret wasn't granted to this repo — fix it and rebuild.

## Verify

```bash
cd /workspaces/<your-repo-name>
source scripts/env.sh && echo "env OK: HARBOR_DIR=$HARBOR_DIR SWARM_MODEL=$SWARM_MODEL"
docker version --format '{{.Server.Version}}'   # docker-in-docker up?
```

## Run a task

Always run via **tmux** so the job survives ssh disconnects (laptop sleep,
network blip, Cursor reload). On Codespaces, only a daemonized tmux server
survives — `nohup`/`setsid`/`disown` all get reaped by `systemd-logind`.

```bash
TASK_DIR=tasks/<your_task_dir>

# launch detached (returns immediately)
tmux new -d -s harbor "bash -lc 'cd /workspaces/<your-repo-name> && ./scripts/run_stable.sh $TASK_DIR 2>&1 | tee /tmp/harbor.log'"

# watch progress
tmux ls                       # session alive?
tail -f /tmp/harbor.log       # live log
tmux attach -t harbor         # Ctrl-b then d to detach

# when done
tmux kill-session -t harbor
```

`run_stable.sh` defaults to `-k 1 -n 1` (the submission minimum: one oracle,
one single, one multi). Wall clock ~25-40 min per task. For repeated trials:

```bash
N_ATTEMPTS=3 N_CONCURRENT=2 ./scripts/run_stable.sh tasks/<dir>
```

Keep `N_CONCURRENT <= 2` on an 8 GiB Codespace or multi-agent trials may OOM.

## Connect from Cursor (optional)

**GitHub Codespaces extension:** install `GitHub.codespaces` in Cursor, sign in,
`Cmd+Shift+P` → *Codespaces: Connect to Codespace* → pick yours.

**Or SSH from any terminal:**
```bash
gh auth login
gh codespace list                       # find your codespace name
gh codespace ssh -c <codespace-name>
```

## Quota & lifecycle

- Free Codespaces quota is ~120-180 core-hours/month per account. The Codespace
  auto-suspends after 30 min idle; only active running time burns quota.
- After a batch finishes, stop it to preserve quota:
  ```bash
  gh codespace stop -c <codespace-name>
  ```
- Don't delete the Codespace — the venv and Docker images are cached. Rebuilding
  costs ~10 min.

## Sync protocol (local <-> Codespace)

The Codespace workdir is the same git repo. **Push from local, pull from
Codespace:**
```bash
# local, after editing task files
git add . && git commit -m "..." && git push

# inside Codespace, before running
git pull --ff-only
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FIREWORKS_API_KEY: MISSING` in banner | Secret not granted to this repo. Settings > Codespaces > Secrets > Repository access. |
| `HARBOR_DIR ... does not exist` | harbor not at `harbor/harbor_src`. Add it, then `(cd harbor/harbor_src && uv sync)`. |
| `error connecting to ...tunnels...visualstudio.com` | Transient Azure tunnel hiccup. Wait 10s, retry. |
| Run "disappeared" after disconnect | Almost always just the ssh tunnel died. Check `tmux ls` — the job is usually still running. |
| Multi-agent trial OOM-killed | Lower `N_CONCURRENT` to 1-2. |
