# SwarmBench / Harbor — Codespaces Harness

> A portable, repo-name-agnostic harness that lets you run **Harbor SwarmBench
> tasks** (oracle / single-agent / multi-agent) on a **free GitHub Codespace**.
> No local Docker. No cloud bill. Drop it into any task repo, add three
> secrets, click "Create Codespace", and run.

This repo contains **only the execution machinery** — no tasks, no secrets, no
harbor source. You bring your own `tasks/` directory and your own `harbor/`
engine; the harness wires them together and gives you the run-scripts +
devcontainer that turn a Codespace into a SwarmBench runner.

For Cursor / AI agents driving this harness, see [`AGENTS.md`](./AGENTS.md) —
Cursor reads it automatically.

---

## Table of Contents

- [What you get](#what-you-get)
- [How it works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Codespace hardware specs](#codespace-hardware-specs)
- [Secrets reference](#secrets-reference)
- [Environment variables](#environment-variables)
- [Script reference](#script-reference)
  - [`scripts/env.sh`](#scriptsenv-sh)
  - [`scripts/run_stable.sh`](#scriptsrun_stable-sh)
  - [`scripts/run_oracle.sh`](#scriptsrun_oracle-sh)
  - [`scripts/run_single.sh`](#scriptsrun_single-sh)
  - [`scripts/run_multi.sh`](#scriptsrun_multi-sh)
  - [`scripts/show_rewards.sh`](#scriptsshow_rewards-sh)
- [Running a task](#running-a-task)
- [Connecting Cursor to a Codespace](#connecting-cursor-to-a-codespace)
- [Quota & lifecycle](#quota--lifecycle)
- [File sync (local ↔ Codespace)](#file-sync-local--codespace)
- [Troubleshooting](#troubleshooting)
- [Don'ts](#donts)
- [License](#license)

---

## What you get

```
.devcontainer/
  devcontainer.json       # Docker-in-Docker + Python + uv + gh CLI + 3 secrets
  post-create.sh          # installs uv/tmux/jq/htop, syncs harbor venv
scripts/
  env.sh                  # derives WORKSPACE_ROOT + HARBOR_DIR (repo-name-agnostic)
  run_stable.sh           # oracle + single + multi (submission-grade)
  run_oracle.sh           # oracle only (must return reward 1.0)
  run_single.sh           # single-agent only, 1×1
  run_multi.sh            # multi-agent only, 1×1
  show_rewards.sh         # prints oracle/single/multi rewards + the gap
AGENTS.md                 # operational runbook for Cursor / AI agents
README.md                 # this file
```

## How it works

```
   ┌───────────────────────────┐         ┌─────────────────────────────┐
   │   Your laptop (Mac/Win)   │  push   │  Your GitHub repo (origin)  │
   │   • edit task files       │ ──────▶ │  • tasks/<dir>/             │
   │   • Cursor / IDE          │         │  • harbor/                  │
   └───────────────────────────┘         │  • .devcontainer/  ◀── this │
              ▲                          │  • scripts/        ◀── this │
              │  ssh                     └────────────┬────────────────┘
              │                                       │ pull
              │                                       ▼
              │            ┌─────────────────────────────────────────┐
              │            │  GitHub Codespace (4 CPU, 8 GiB Docker) │
              └────────────│  • Docker-in-Docker                     │
                           │  • harbor venv (uv sync'd)              │
                           │  • 3 secrets injected as env vars       │
                           │  • runs your task in tmux               │
                           │       │                                 │
                           │       ▼ HTTPS                           │
                           │  ┌─────────────────┐                    │
                           │  │  Fireworks API  │ (kimi-k2 inference)│
                           │  └─────────────────┘                    │
                           └─────────────────────────────────────────┘
```

The Codespace is a Linux VM with Docker-in-Docker. Your task's
`environment/Dockerfile` is built **inside the Codespace** (not on your
laptop), and the resulting container runs there too. The LLM inference is
remote (Fireworks); the Codespace just orchestrates. Wall time per
submission-grade run: ~25–40 min. Active runs burn quota; suspended
Codespaces don't.

## Prerequisites

In **your** task repo (the one you'll add this harness to):

1. **harbor must be vendored** at `<repo>/harbor/harbor_src/` (or
   `<repo>/harbor/`) with a working `pyproject.toml`. `scripts/env.sh`
   probes both layouts.
2. **At least one task** under `<repo>/tasks/<task_dir>/` with the standard
   Harbor layout:
   ```
   tasks/<task_dir>/
     task.toml
     instruction.md
     decomposition.yaml      # multi-agent definition (if applicable)
     environment/
       Dockerfile            # builds the task container
       input_artifacts/      # files mounted read-only into the task
     solution/
       solve.sh              # oracle agent's deterministic solution
       oracle.json           # gold answer key (optional, task-dependent)
     tests/
       test.sh               # invokes verify.py
       verify.py             # writes /logs/verifier/reward.json
       oracle.json           # gold answer key consumed by verify.py
   ```
3. **A Fireworks API key** with access to a Kimi-K2 deployment (you bring
   this; the harness ships none).
4. **GitHub account** with Codespaces enabled (default for personal
   accounts).

## Quick start

```bash
# 1. Get the harness — easiest: fork this repo into your account,
#    or copy .devcontainer/ + scripts/ + AGENTS.md into your existing repo.
gh repo fork Aawegg/swarmbench-codespaces-harness --clone --remote=false
# (or manually click "Fork" on GitHub)

# 2. Add the 3 secrets at
#    GitHub → your avatar → Settings → Codespaces → Secrets
#    Grant each to your task repo. See "Secrets reference" below.

# 3. Create the Codespace
#    GitHub → your repo → green "Code" button → Codespaces → Create on main
#    First boot: ~5–10 min (post-create.sh installs uv/tmux + syncs harbor venv)

# 4. Verify (terminal inside the Codespace)
source scripts/env.sh && echo "env OK: HARBOR_DIR=$HARBOR_DIR SWARM_MODEL=$SWARM_MODEL"
docker version --format '{{.Server.Version}}'

# 5. Run a task (always via tmux so it survives ssh disconnects)
tmux new -d -s harbor "bash -lc './scripts/run_stable.sh tasks/<your_task_dir> 2>&1 | tee /tmp/harbor.log'"
tail -f /tmp/harbor.log

# 6. When the run completes (oracle + single + multi finished)
tmux kill-session -t harbor 2>/dev/null
./scripts/show_rewards.sh tasks/<your_task_dir>

# 7. Stop the Codespace from the Mac to preserve quota
gh codespace stop -c <your-codespace-name>
```

## Codespace hardware specs

Defined in `.devcontainer/devcontainer.json` via `hostRequirements`:

| Resource | Spec |
|---|---|
| Machine type | `standardLinux32gb` (Codespaces' 4-CPU SKU) |
| CPU | 4 cores |
| RAM | 15 GiB host (Docker VM ~8 GiB) |
| Disk | 32 GiB |
| OS | Ubuntu 22.04 (`mcr.microsoft.com/devcontainers/base:ubuntu-22.04`) |
| Architecture | amd64 |
| Idle timeout | 30 min (auto-suspend) |

Installed during `post-create.sh`:

| Package | Why |
|---|---|
| Docker-in-Docker (Moby) | Builds & runs task containers |
| Python 3.11 | Required by harbor |
| `uv` | Fast Python venv + dep resolver |
| `gh` CLI | GitHub auth + Codespace ops |
| `tmux` | Non-negotiable for runs > 5 min (see [AGENTS.md](./AGENTS.md)) |
| `jq`, `htop`, `ncdu` | Inspection / debugging utilities |

## Secrets reference

Three secrets are declared in `.devcontainer/devcontainer.json`. The
Codespace injects them as env vars automatically. Add them at
**GitHub → Settings → Codespaces → Secrets**, and under *Repository
access* grant each to your task repo:

| Secret | Required | Example value | What it's for |
|---|---|---|---|
| `FIREWORKS_API_KEY` | ✅ yes | `fw-xxxxxxxxxxxx` | Auth to Fireworks for kimi inference |
| `SWARM_MODEL_DEDICATED` | preferred | `fireworks_ai/accounts/<acct>/deployments/<id>` | Dedicated Kimi deployment (faster, more stable) |
| `SWARM_MODEL_SHARED` | fallback | `fireworks_ai/accounts/fireworks/models/kimi-k2p5` | Serverless Kimi model (used if no dedicated) |

`env.sh` picks `SWARM_MODEL` from `SWARM_MODEL_DEDICATED` first, then
`SWARM_MODEL_SHARED`. If neither is set, `env.sh` errors out.

> **Billing**: the Fireworks key bills usage to whoever owns that
> Fireworks account, not to GitHub. Either use your own key, or get
> explicit sign-off before sharing one with teammates.

## Environment variables

Set automatically by the Codespace + `env.sh`:

| Var | Source | Purpose |
|---|---|---|
| `FIREWORKS_API_KEY` | Codespace secret | Fireworks auth |
| `SWARM_MODEL_DEDICATED` | Codespace secret | Preferred Kimi target |
| `SWARM_MODEL_SHARED` | Codespace secret | Fallback Kimi target |
| `SWARM_MODEL` | `env.sh` | First of `SWARM_MODEL_DEDICATED`, `SWARM_MODEL_SHARED` |
| `WORKSPACE_ROOT` | `env.sh` | Derived from `env.sh` location (repo root) |
| `HARBOR_DIR` | `env.sh` | First of `$WORKSPACE_ROOT/harbor/harbor_src`, `$WORKSPACE_ROOT/harbor` |

Overridable by you when calling the run scripts:

| Var | Default | Used by | Effect |
|---|---|---|---|
| `N_ATTEMPTS` | `1` | `run_stable.sh` | `-k` value for single + multi phases |
| `N_CONCURRENT` | `1` | `run_stable.sh` | `-n` value for single + multi phases |

## Script reference

### `scripts/env.sh`

Sourced by every run script. Repo-name-agnostic — derives everything from
its own location.

```bash
source ./scripts/env.sh
```

What it does:
1. Sets `WORKSPACE_ROOT` to the parent of `scripts/`.
2. Sources `$WORKSPACE_ROOT/.env` if it exists (useful for local dev; the
   Codespace doesn't need it).
3. Sets `SWARM_MODEL` from the dedicated/shared fallback chain.
4. Sets `HARBOR_DIR` by probing `harbor/harbor_src/` then `harbor/`.
5. Fails loudly with a clear error if `FIREWORKS_API_KEY`, `SWARM_MODEL`,
   or `HARBOR_DIR` is missing.

### `scripts/run_stable.sh`

Submission-grade run: **oracle + single + multi**, sequentially. The
default `-k 1 -n 1` is the documented minimum for a SwarmBench submission.

```bash
./scripts/run_stable.sh tasks/<task_dir>

# For extra-confidence repeated trials (NOT required for submission)
N_ATTEMPTS=3 N_CONCURRENT=2 ./scripts/run_stable.sh tasks/<task_dir>
```

Wall time: ~25–40 min at the default. Output: `tasks/<dir>/execution_logs/`
with subdirs `oracle/`, `single-kimi-agent/`, `multi-kimi-agent/`.
Prints `show_rewards.sh` summary at the end.

> **Memory note**: keep `N_CONCURRENT ≤ 2` on the 8 GiB Codespace Docker
> VM. The harbor default (`N_CONCURRENT=4`) can OOM-kill multi-agent
> trials.

### `scripts/run_oracle.sh`

Oracle agent only. Used during task authoring to confirm
`solution/solve.sh` + `tests/verify.py` are consistent.

```bash
./scripts/run_oracle.sh tasks/<task_dir>
```

**Expected result: reward = 1.0.** Anything else means your verifier or
solve.sh is broken. Wall time: ~3–8 min.

### `scripts/run_single.sh`

Single-agent baseline only, `-k 1 -n 1`. Useful for fast iteration when
you only need to recheck the single-agent leg.

```bash
./scripts/run_single.sh tasks/<task_dir>
```

Wall time: ~5–15 min.

### `scripts/run_multi.sh`

Multi-agent (orchestrator + sub-agents) run only, `-k 1 -n 1`. Reads the
task's `decomposition.yaml` to spawn sub-agents.

```bash
./scripts/run_multi.sh tasks/<task_dir>
```

Wall time: ~5–15 min.

### `scripts/show_rewards.sh`

Parses harbor's `result.json` for each phase and prints the rewards plus
the multi-minus-single gap. Used at the end of `run_stable.sh` and also
runnable standalone.

```bash
./scripts/show_rewards.sh tasks/<task_dir>
```

Example output:

```
  oracle               -> 1.0
  single-kimi-agent    -> 0.5833
  multi-kimi-agent     -> 0.8333
  GAP (multi-single)   -> +0.2500   (need >= 0.23)
  STATUS               -> PASS
```

The `>= 0.23` threshold is a sanity check for submission gap requirements;
adjust the constant in the script to match your benchmark's threshold.

## Running a task

Always launch via **tmux** so the job survives ssh disconnects (laptop
sleep, Wi-Fi blip, Cursor reload, etc.). On Codespaces, `nohup`,
`setsid`, `disown`, and `loginctl enable-linger` all fail — only a
daemonized tmux server survives. See [`AGENTS.md`](./AGENTS.md) for the
full explanation.

### From inside the Codespace terminal

```bash
TASK_DIR=tasks/<your_task_dir>

# launch detached
tmux new -d -s harbor "bash -lc './scripts/run_stable.sh $TASK_DIR 2>&1 | tee /tmp/harbor.log'"

# watch
tmux ls                       # session alive?
tail -f /tmp/harbor.log       # live log
tmux attach -t harbor         # interactive (Ctrl-b then d to detach)

# clean up
tmux kill-session -t harbor
./scripts/show_rewards.sh $TASK_DIR
```

### From your laptop (via `gh codespace ssh`)

```bash
CS=<your-codespace-name>
TASK_DIR=tasks/<your_task_dir>

# launch (returns in <1 sec, then disconnect freely)
gh codespace ssh -c $CS -- \
  "tmux new -d -s harbor 'bash -lc \"cd /workspaces/<your-repo-name> && ./scripts/run_stable.sh $TASK_DIR 2>&1 | tee /tmp/harbor.log\"'"

# check status
gh codespace ssh -c $CS -- 'tmux ls && tail -50 /tmp/harbor.log'

# cleanup + stop codespace to save quota
gh codespace ssh -c $CS -- 'tmux kill-session -t harbor 2>/dev/null; echo done'
gh codespace stop -c $CS
```

## Connecting Cursor to a Codespace

**Option A — Codespaces extension (cleanest):**
1. Cursor → Extensions → install `GitHub.codespaces`.
2. Sign in to GitHub when prompted.
3. `Cmd+Shift+P` → *Codespaces: Connect to Codespace* → pick yours.

Cursor opens directly inside the Codespace with terminal + file access;
no separate ssh step.

**Option B — SSH from any terminal:**
```bash
gh auth login
gh codespace list
gh codespace ssh -c <codespace-name>
```

## Quota & lifecycle

- **Free quota per GitHub account**, recurring every month, forever:
  - GitHub Free: **120 core-hours / month** (≈ 30 hr on a 4-core Codespace)
  - GitHub Pro: **180 core-hours / month** (≈ 45 hr on a 4-core Codespace)
- **Codespace auto-suspends after 30 min idle.** Only active running time
  burns quota.
- **After every long-running batch**, stop it from your laptop:
  ```bash
  gh codespace stop -c <codespace-name>
  ```
- **Never `gh codespace delete`** — the secrets, venv, and Docker images
  are baked in. Rebuilding costs ~5–10 min (full `post-create.sh` rerun).
- **No surprise billing**: if you keep no payment method on your GitHub
  account and don't manually raise the Codespaces budget above $0, you
  literally cannot be charged. Free quota exhausted → Codespaces refuses
  to start until the next month.

To verify your current usage: GitHub → Settings → Billing → Codespaces.

## File sync (local ↔ Codespace)

The Codespace workdir is the same git repo. **Push from laptop, pull
from Codespace** is the only sync protocol:

```bash
# laptop, after editing
git add . && git commit -m "..." && git push origin main

# inside Codespace, before running
git pull --ff-only origin main

# after run, to get execution_logs back to the laptop
gh codespace ssh -c <codespace-name> -- \
  "bash -lc 'cd /workspaces/<your-repo-name> && git add tasks/<dir>/execution_logs && git commit -m logs && git push'"
git pull --ff-only origin main   # laptop
```

If `execution_logs/` is `.gitignore`d in your repo, use
`gh codespace cp -r` instead — see `gh codespace cp -h`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FIREWORKS_API_KEY: MISSING` in the post-create banner | Secret not granted to this repo. Settings → Codespaces → Secrets → Repository access. After fixing, **rebuild** the Codespace (Command Palette → "Codespaces: Rebuild Container"). |
| `ERROR: HARBOR_DIR (...) does not exist` from `env.sh` | harbor not at `<repo>/harbor/harbor_src` or `<repo>/harbor`. Add it, then `(cd harbor/harbor_src && uv sync)`. |
| `ERROR: SWARM_MODEL not set` from `env.sh` | Neither `SWARM_MODEL_DEDICATED` nor `SWARM_MODEL_SHARED` injected. Re-check secret names + repository access. |
| `gh codespace ssh: error connecting to ...tunnels...visualstudio.com` | Transient Azure tunnel hiccup. Wait 10 s and retry. |
| Run "disappeared" right after disconnect | Almost always just the ssh tunnel died. Reconnect and run `tmux ls` — the job is usually still running. See [AGENTS.md → "Did my job actually die?"](./AGENTS.md). |
| Multi-agent trial OOM-killed | Lower `N_CONCURRENT` to 1 or 2. 4 OOMs reliably on the 8 GiB Docker VM. |
| Oracle reward = 0.0 | `solve.sh` doesn't produce what `verify.py` expects (mismatched output schema is the #1 cause). Open `execution_logs/oracle/.../agent/output.json` and `execution_logs/oracle/.../verifier/reward.json` to see the discrepancy. |
| First-time Docker build times out | Increase `[environment].build_timeout_sec` in `task.toml` to `900` or `1200`. The image is cached after the first build. |
| `gh codespace ssh` hangs forever | The Codespace is `Shutdown`. Start it: `gh api -X POST /user/codespaces/<name>/start`, wait 30 s, retry. |
| `harbor: command not found` inside the Codespace | The harbor venv didn't sync. From the repo root: `(cd harbor/harbor_src && uv sync)`. |

## Don'ts

- ❌ **Don't `gh codespace delete`** — baked secrets/venv/images vanish.
  Rebuilding costs ~10 min.
- ❌ **Don't pass `FIREWORKS_API_KEY` on the laptop CLI** — it's a
  Codespace secret, not a laptop env var.
- ❌ **Don't run `harbor run` on the laptop** without `--n-concurrent-trials
  2`. The harbor default OOMs both the 16 GiB Mac and the 8 GiB Codespace
  Docker VM under heavy load.
- ❌ **Don't `git push --force`** from the laptop while a Codespace job is
  mid-run. The next `git pull` inside the Codespace will conflict.
- ❌ **Don't `gh auth switch`** if you have multiple GitHub accounts on
  the same laptop. Use per-shell `export GH_TOKEN=$(gh auth token -u <handle>)`.
  See [AGENTS.md → "Critical: never call `gh auth switch`"](./AGENTS.md).
- ❌ **Don't set `[agent].timeout_sec = 1800`** in `task.toml`. 1800 s is a
  known failure mode (premature `AgentTimeoutError`). Use 3600 s; bump to
  5400 s for heavy corpora. Single and multi must share the same timeout.

## License

MIT — do whatever you want with the harness scripts and config. The
harbor engine, your tasks, and the Fireworks API are governed by their
own licenses and terms.
