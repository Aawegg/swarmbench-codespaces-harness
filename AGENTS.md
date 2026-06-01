# AGENTS.md — How a Cursor agent should run model jobs in this repo

> **TL;DR for any chat working in this repo:** do not run `harbor` / Docker
> containers on the local Mac. SSH into a GitHub Codespace and run them
> there. The Codespace already has Docker-in-Docker, `uv`, Python 3.11,
> the harbor venv, and the Fireworks secrets pre-wired via this repo's
> `.devcontainer/`.

This file is the operational runbook for any Cursor / AI agent that
drives the Codespaces harness in this repo. It is **completely
parameterized** — fill in your codespace names and GitHub account
handles in the "Setup" section at the top once, and the rest applies to
every run.

## Setup — fill these in once per chat

Pin the chat's codespace + account at the top of the session and stick to
it for the entire chat. Don't `gh auth switch` (see "The two real
hazards" below).

```bash
# Replace with YOUR values:
export CS=<your-codespace-name>           # e.g. "myrepo-runner-abc123xyz"
export GH_TOKEN=$(gh auth token -u <your-github-handle>)
```

If you have multiple codespaces (e.g. one per GitHub account for more
free quota), maintain a table like this in your fork of this file:

| Codespace name | Account `gh auth -u` |
|---|---|
| `<codespace-1>` | `<handle-1>` |
| `<codespace-2>` | `<handle-2>` |

All codespaces should be `standardLinux32gb` (4 CPU / 15 GiB / 32 GiB),
workdir `/workspaces/<repo-name>`, user `vscode` (passwordless sudo).

## Critical: never call `gh auth switch` — use `GH_TOKEN` per command

`gh auth switch -u X` flips the **global** active account in the macOS
keychain. Every parallel chat on this Mac immediately starts using
account `X` on its next `gh` call. That has caused false alarms where
chats thought codespaces were deleted (they were just looking with the
wrong account's token).

**Pin the account per command with `GH_TOKEN`. Never `gh auth switch`.**

```bash
# to use a specific codespace, set GH_TOKEN to that account's token
GH_TOKEN=$(gh auth token -u <handle>) gh codespace ssh -c <codespace-name> -- '<cmd>'
```

`GH_TOKEN` is a per-process override that bypasses the global active
account. Two chats can hit two different codespaces from the same Mac
with zero interference.

Shorthand: each chat exports `GH_TOKEN` once at session start with
`export GH_TOKEN=$(gh auth token -u <handle>)`. Subsequent commands in
that shell then use that account; the other chat exports a different
token. Neither affects the other.

## How to reach a codespace from any chat (Mac terminal)

```bash
# one-shot command (non-interactive bash login shell, so secrets + uv are on PATH)
gh codespace ssh -c $CS -- 'bash -lc "<YOUR COMMAND>"'

# interactive shell (use sparingly; agents should prefer one-shot)
gh codespace ssh -c $CS

# wake it up if it's stopped (idle timeout = 30 min)
gh api -X POST /user/codespaces/$CS/start

# stop it when done to preserve quota
gh codespace stop -c $CS
```

If `gh codespace ssh` ever returns `error connecting to
...tunnels...visualstudio.com`, wait 10 s and retry — transient Azure
tunnel hiccup, not a real failure.

## Secrets (already set in Codespace, do NOT echo them)

The three secrets declared in `.devcontainer/devcontainer.json` are
automatically injected into the Codespace as env vars:

- `FIREWORKS_API_KEY` — Fireworks API key
- `SWARM_MODEL_DEDICATED` — preferred Fireworks deployment URL
- `SWARM_MODEL_SHARED` — fallback serverless Kimi model URL

A `bash -lc` shell automatically has all three on `$ENV`. Don't try to
pass them from the Mac.

## Running a task — ALWAYS via tmux (survives ssh disconnect)

**Why tmux is non-negotiable for any run > 5 min:** when an ssh tunnel
from `gh codespace ssh` closes (laptop sleep, network blip, manual ^C,
Cursor reload), `systemd-logind` kills every process in the `vscode`
user slice. `setsid`, `nohup`, `disown`, and `loginctl enable-linger`
all fail on Codespaces — only a daemonized tmux server survives,
because it's parented to PID 1, not to the ssh session.

### Canonical launch pattern

```bash
TASK_DIR=tasks/<your_task_dir>

gh codespace ssh -c $CS -- \
  "tmux new -d -s harbor 'bash -lc \"cd /workspaces/<your-repo-name> && git pull --ff-only origin main && ./scripts/run_stable.sh $TASK_DIR 2>&1 | tee /tmp/harbor-$TASK_DIR.log\"'"
```

That returns in <1 sec. The job runs detached. Disconnect freely.

### Watching progress (from Mac, any time)

```bash
# is the tmux session still alive?
gh codespace ssh -c $CS -- 'tmux ls'

# tail the log (replace TASK_DIR)
gh codespace ssh -c $CS -- 'tail -50 /tmp/harbor-<TASK_DIR>.log'

# attach interactively to watch live (Ctrl-b then d to detach)
gh codespace ssh -c $CS
#   inside: tmux attach -t harbor
```

### When the job is done

```bash
# kill the tmux session (the harbor process already exited)
gh codespace ssh -c $CS -- 'tmux kill-session -t harbor 2>/dev/null; echo done'

# stop the codespace to preserve quota
gh codespace stop -c $CS
```

### Submission-grade run

The submission requirement is **one trial each** for oracle, single,
multi (`-k 1 -n 1`). `scripts/run_stable.sh` defaults to that. Wall
clock ~25–40 min per task.

```bash
./scripts/run_stable.sh tasks/<TASK_DIR>
```

For repeated trials (NOT required for submission):

```bash
N_ATTEMPTS=3 N_CONCURRENT=2 ./scripts/run_stable.sh tasks/<TASK_DIR>
```

At `N_CONCURRENT=4` (harbor's default) the 8 GiB docker VM can OOM-kill
multi-agent trials. Stay at `N_CONCURRENT <= 2` if you bump
`N_ATTEMPTS`.

For super-fast single-phase iteration use `scripts/run_single.sh` /
`scripts/run_multi.sh` (each 1×1, ~5–15 min).

### What does NOT work for detachment (don't try these)

| Pattern | Why it fails on Codespaces |
|---|---|
| `setsid cmd` | new session id, same user slice → logind reaps |
| `nohup cmd &` | nohup ignores SIGHUP; logind sends SIGTERM |
| `setsid nohup cmd &` | both are no-ops vs SIGTERM |
| `loginctl enable-linger vscode` | Codespaces blocks the syscall |
| `disown` | bash internal; cgroup membership unchanged |
| `at`/`batch` | atd not installed |
| `systemd-run --user --scope` | dbus user bus not running on this image |

## File sync (Mac ↔ Codespace)

The Codespace's workdir is the same git repo. **Push from Mac, pull
from Codespace** is the only sync protocol:

```bash
# on Mac, after editing task files
git add . && git commit -m "..." && git push origin main

# inside Codespace, before running
git pull --ff-only origin main

# after run, to get execution_logs back to Mac
gh codespace ssh -c $CS -- "bash -lc 'cd /workspaces/<your-repo-name> && git add tasks/<dir>/execution_logs && git commit -m logs && git push'"
git pull --ff-only origin main   # on Mac
```

(If `execution_logs/` is `.gitignore`d for some tasks, use
`gh codespace cp` instead — see `gh codespace cp -h`.)

## Quota & lifecycle

- Free quota per GitHub account: 120 core-hours/month (Free plan) or
  180 core-hours/month (Pro plan), recurring monthly. Codespace
  auto-suspends after 30 min idle; only active running time burns
  quota.
- After every long-running batch, call `gh codespace stop -c $CS` from
  the Mac.
- **Never delete the codespace.** Recreating it costs ~5–10 min of
  provisioning (full `post-create.sh` rerun) and loses any uncommitted
  work. If something looks broken, `git pull` and re-run instead.

## Parallel chats / parallel tasks

If you have multiple codespaces (one per account, for more free quota),
run different tasks on each. Each task uses ~250 MiB actual RAM
(Fireworks API does the heavy work, not local CPU/RAM). Each codespace
can comfortably hold 3–5 concurrent tasks.

**Each parallel task MUST be a different task directory** — concurrent
runs on the same task directory clobber each other's `execution_logs/`.

Set the account ONCE per chat with
`export GH_TOKEN=$(gh auth token -u <handle>)` — **never** use
`gh auth switch`, it's global and breaks the other chat.

## Inter-chat isolation rules (read this if your run "disappeared")

Two Cursor chats sharing this Mac CAN unintentionally kill each
other's runs. Symptom: chat 1 launches a run on Codespace A, chat 2
launches a run on Codespace B, chat 1's run "stops or disconnects".
99% of the time the run is fine and only the SSH tunnel died.
Diagnose before reacting.

### The two real hazards

1. **`gh auth switch -u <user>`** — flips the *global* active account
   in the Mac keychain. The next `gh` call from EITHER chat now uses
   that account's token. If chat 2 ran `gh auth switch -u <handle-B>`
   and then chat 1 does `gh codespace stop -c <codespace-A>`, it sees a
   404 (wrong account) and may retry/recreate, OR may target the wrong
   codespace if the name collides. **Solution: never `gh auth switch`.
   Always per-command/per-shell `GH_TOKEN`.**

2. **`gh codespace stop` / `delete` / `rebuild` targeting the wrong
   codespace.** Each chat must touch only its own assigned codespace.

### Chat assignment contract

When a chat starts working, pin its codespace + account at the top of
its session and stick to it for the whole chat. After that, every
`gh codespace ...` call in that chat uses `$CS` and is isolated from
the other chat. No `auth switch`, no cross-codespace ops.

### "Did my job actually die?" — diagnostic (safe to run from either chat)

A dead SSH terminal ≠ a dead run. Before assuming the worst, check:

```bash
gh codespace ssh -c $CS -- 'tmux ls; echo ---; ps -ef | grep -E "harbor|kimi" | grep -v grep | wc -l'
```

- `tmux ls` shows a session like `harbor: 1 windows ...` → tmux alive
- `ps` count > 0 → harbor/kimi processes still running

If both are present, the run is fine and you just need to re-tail the
log.

### What can never disconnect your run

- Closing the Cursor chat window
- Mac sleep / Wi-Fi blip / VPN flap
- The OTHER chat starting/stopping its OWN codespace
- The OTHER chat's SSH session being open or closed

### What CAN disconnect your run

- The other chat running `gh codespace stop` / `delete` / `rebuild` on
  YOUR codespace (forbidden by the contract above)
- The other chat running `gh auth switch` (forbidden — use `GH_TOKEN`)
- Your own codespace hitting the 30-min idle auto-stop (impossible
  while harbor is actively running — running processes count as
  activity)
- You manually killing the tmux session

## Task config rule (don't get burned)

In every new task's `task.toml`, set `[agent].timeout_sec = 3600` (60
min). **Never use 1800 (30 min)** — it is a known failure mode. With
1800s the agent hits `AgentTimeoutError` before the run naturally
finishes or fails, which muddies QG reviews. With 3600s the agent
fails organically on context-overload (low reward, no exception) which
is the clean failure mode.

Heavy corpora (research / data-analysis / 30+ items) → bump to 5400
(90 min). Single and multi MUST share the same timeout (QD-10
Check 2).

```toml
[agent]
timeout_sec = 3600        # never 1800

[verifier]
timeout_sec = 300

[environment]
cpus = 2
memory_mb = 4096
build_timeout_sec = 600   # first-time docker build can be slow
```

## Don'ts

- ❌ Don't `gh codespace delete` — the secrets, venv, and Docker images
  are baked in. Rebuilding from scratch wastes ~10 min.
- ❌ Don't pass `FIREWORKS_API_KEY` on the Mac CLI — it's a Codespace
  secret, not a Mac env var.
- ❌ Don't run `harbor run` on the Mac without `--n-concurrent-trials
  2` (will swap heavily on 16 GiB Mac, OOM on 8 GiB Codespace).
- ❌ Don't `git push --force` from Mac while a Codespace job is mid-run.
