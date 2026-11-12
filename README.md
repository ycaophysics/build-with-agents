# Build with agents

A Claude Code skill that takes a plan and builds it. The session you start becomes the lead. It splits the plan into milestones and tasks, hands each task to a worker, checks what comes back, and has three other models review each milestone. The lead does not write feature code. Workers do, on a new branch in a separate git worktree, so the folder you work in is left alone until the build ends.

Start a build with a plan file, or paste the plan:

```
/build-with-agents path/to/plan.md
```

Resume a build that stopped:

```
/build-with-agents resume <build folder>
```

The skill only builds. If you ask it for a plan or a prompt, it gives you the prompt as one block you can paste and stops.

Every rule the lead follows is in [SKILL.md](SKILL.md).

## Requirements

- Windows with Git Bash, macOS, or Linux. The scripts need bash 3.2 or later, so the bash that ships with macOS is enough.
- Claude Code.
- Python 3, for the allowance check (`python3`, or `python` on Windows).
- quota-cli for the allowance check. The installer installs it (see below).
- Optional: the Codex CLI, cursor-agent and agy as reviewers and outside workers; Node.js for the agy review guard; Hermes as a second source for agy's allowance. A missing tool is reported, and the build goes on without it.

## Install

### Ask Claude Code to install it

Open a Claude Code session and paste this:

```
Install the build-with-agents skill from https://github.com/ycaophysics/build-with-agents.

1. If ~/.claude/skills/build-with-agents does not exist, clone the repo there. If it exists and is
   a clone of that repo, run `git pull --ff-only` in it instead. If it exists and is anything else,
   stop and tell me what is there.
2. Run `bash ~/.claude/skills/build-with-agents/install.sh` (from Git Bash on Windows). It links the
   skill into Codex, Cursor and agy where they are installed, and installs quota-cli.
3. Show me what install.sh printed, and tell me which tools got the skill and which were skipped.

Do not change my Claude Code settings or permissions, and do not log in to any tool for me.
```

When it finishes, type `/build-with-agents` to check that the skill is there. If it isn't listed, start a new session. Outside workers still need a permission rule and their own logins, which you set up yourself (see [Sign-in and permissions](#sign-in-and-permissions)).

### Install by hand

Claude Code reads `~/.claude/skills/build-with-agents` on its own. Clone the repo to that path:

```
git clone https://github.com/ycaophysics/build-with-agents.git ~/.claude/skills/build-with-agents
```

Codex, Cursor and agy need the installer. Run it from Git Bash on Windows, or from any terminal on macOS and Linux:

```
bash ~/.claude/skills/build-with-agents/install.sh
```

Codex gets a link at `~/.codex/skills/build-with-agents`, and Cursor gets one at `~/.cursor/skills/build-with-agents`, so an edit in the Claude Code folder shows up in both at once. The link is a directory junction on Windows and a symbolic link on macOS and Linux. agy skips linked folders, so the script copies the skill to `~/.gemini/config/skills/build-with-agents` instead. After you edit the skill, run the installer again or agy keeps the old copy.

A tool that is not installed is skipped. If a tool is installed and only its `skills` folder is missing, the script creates that folder. It never changes the folder it installs from. Edit the skill in `~/.claude/skills/build-with-agents`, not in the other tools' folders.

The installer also installs [quota-cli](https://github.com/pinkpixel-dev/quota) 0.4.0 for the allowance check, unless you already have it. An older copy that cargo installed is upgraded, because quota-cli reads agy only from 0.4.0.

- **Linux (x86_64) and Windows:** it downloads the prebuilt binary to `~/.local/bin`, after checking it against a SHA-256 hash pinned in the script.
- **macOS, and other Linux machines:** there is no prebuilt binary, so it builds quota-cli with `cargo install`. This takes under a minute on a recent Mac and needs [Rust](https://rustup.rs) and a C compiler.

To skip this step, pass `--no-quota-cli`.

To remove the skill from Codex, Cursor and agy and keep the Claude Code copy (quota-cli stays installed):

```
bash ~/.claude/skills/build-with-agents/install.sh --remove
```

## How a build runs

1. Setup. The lead checks that nothing else is editing the repo, makes a branch and a worktree from the base branch, checks every runner's login, models and allowance, and runs the repo's tests once to record anything that already failed before the build started.
2. Planning. It uses the plan's own milestones when there are any. Otherwise it makes two to four, ordered so the first one ends in something you can see or run. Each task is sized hard, medium or easy.
3. Work. Each task goes to a worker with a written brief. When the worker finishes, the lead checks its commits and reruns its tests.
4. Review. At the end of each milestone, three reviewers read the change at the same time. Problems that matter get one repair, and the rest go on a follow-up list.
5. Report. The lead commits the follow-up list to the repo's `TODOS.md`, removes the worktree, switches your checkout to the build branch, and tells you what works and whether it is ready.

## Features

### The lead keeps its own context small

The lead has to last the whole build, so it reads each worker's final report and never the transcript. Outside workers and reviewers each print a single line through the scripts in `bin/`. The build's state lives in `status.md` in the build folder: each runner and its allowance, every task and its state, the lead's choices, and the review results. If the lead is compacted or restarted, it trusts that file over its memory.

### Work stays out of your checkout

The build happens on a new branch in its own worktree next to your repo (`../<repo>-wt-<slug>`). Workers may not edit the main checkout, push, merge, open a pull request, or stage with `git add -A`. Only one worker edits the build worktree at a time. Tasks that touch separate files can run in parallel, up to three at once, each in its own worktree. The lead cherry-picks their commits back, and if a cherry-pick conflicts it aborts it and records that task as not merged.

Build files go in `~/.claude/plans/<slug>-build/`: a copy of the plan, `status.md`, and folders for briefs, worker reports, logs and reviews.

### Tasks are sized, and the size picks the model

| Size | What it covers | Default worker | When Claude is out |
|---|---|---|---|
| Hard | Money, orders, accounts, state machines, concurrency, migrations: anything where a mistake loses money or data | Claude subagent, Opus 5.5 at high effort | agy Opus 5.5, then Cursor Opus 5.5, then agy Gemini 4 Carbon (medium), then Codex `gpt-6-astra` at `xhigh` |
| Medium | Plumbing with real edge cases, tests that need thought, screens | Claude subagent, Opus 5.5 at high effort | agy Gemini 4 Carbon (medium), then Codex `gpt-6.1-sol` at `xhigh`, then Cursor Opus 5.5 |
| Easy | Mechanical, fully specified changes such as renames, copy edits from given text, or a test from a given table | Claude subagent, Sonnet 5.5 at high effort | Cursor `cursor-grok-4.6-high-fast`, then agy Gemini 4 Hydrogen, then Codex `gpt-6.1-sol` at `xhigh` |

If the repo has `.claude/agents/opus-high.md`, hard and medium tasks use that agent. Codex is on every list: GPT-6 Astra as the last fallback for hard tasks, GPT-6.1 Sol for medium and easy ones. A task that comes back partial or blocked gets one follow-up attempt, then moves up one size once; it never gets a third try at the same size. A hard task has no bigger size, so it moves up to Claude Fable 5.2 instead (Cursor's Fable 5.2 when Claude is out).

No fallback list holds two models that draw on the same allowance. When an allowance is rate limited or nearly used up, the lead marks it down as a whole, so a second model on it would never be tried. agy's Claude and Gemini models have separate allowances, which is why agy can appear twice on the hard list; Cursor and Codex appear once per list.

Every model ID is in [bin/roster.sh](bin/roster.sh) and in the roster table in SKILL.md. The lead never picks a model outside that list and never falls back to `auto`.

### Outside workers

With your permission, Cursor, agy and Codex take tasks when Claude is rate limited or nearly out of allowance, or when you name them for a build. They edit files unattended, so Claude Code's auto mode refuses to start them until you allow `bin/dispatch.sh` with a permission rule (see [Sign-in and permissions](#sign-in-and-permissions)). Without that rule, every task goes to a Claude subagent.

[bin/dispatch.sh](bin/dispatch.sh) starts one outside worker on one task and prints one line:

| Result | Meaning |
|---|---|
| `PASS` | The worker exited cleanly, wrote its report, and says its verification commands passed |
| `VERIFYFAIL` | The worker finished and says its checks failed |
| `FAIL`, `NOVERDICT`, `EMPTY` | The runner crashed, finished without a verdict, or printed nothing |
| `RATELIMITED` (exit 86) | Rate limited, out of credit, or logged out. The lead moves the task to the next runner at once |
| `TIMEOUT` (exit 87) | Still running at the deadline (one hour by default) and stopped |

A `PASS` verdict with an error exit or a missing report counts as `FAIL`. A lock keeps the same task from being dispatched twice. The full transcript goes to a log file; the lead reads the short report the worker writes.

### Allowance check

[bin/usage.py](bin/usage.py) shows how much each runner has left in each window (5-hour, weekly) and when it resets.

| Line | Read from | Covers |
|---|---|---|
| `claude` | quota-cli | the lead and every Claude subagent |
| `codex` | quota-cli | Codex as reviewer and as worker |
| `cursor` | quota-cli | Cursor as reviewer and as worker |
| `agy-gemini` | quota-cli (Gemini pool) | agy Gemini 4 Carbon and Gemini 4 Hydrogen |
| `agy-claude` | quota-cli (Claude/GPT pool) | agy Opus |

quota-cli reads each tool's saved login without changing it. It reads agy's own login from version 0.4.0. If quota-cli cannot read agy and Hermes is installed, Hermes (`hermes usage`) fills in the two agy lines, so you don't need Hermes. On macOS the `cursor` line shows `unknown`: cursor-agent keeps its login in the Keychain there, and quota-cli 0.4.0 reads it only from `~/.config/cursor/auth.json`. A line is `LOW` when any window has 10% or less left, `unknown` when its numbers could not be read, and `ok` otherwise. The check only reads, usually takes about 10 seconds (80 at most), and never stops a build. Anything in the tools' output that looks like an email address, a login token or a home folder is hidden.

The lead runs the check at setup, before each milestone review, after any `RATELIMITED` result, and at the end. A `LOW` worker is treated as rate limited before it is tried, so its task goes to the next runner for that size, and it comes back once a later check shows it `ok`. If `claude` itself is `LOW`, tasks go to outside workers when you have allowed them, and the lead tells you what is left and when it resets. Reviewers run even when `LOW`. An `unknown` line changes nothing. The first and last checks go in the final report, so you can see what the build used.

### Rate limits partway through a task

A runner can still run out between allowance checks. When a worker hands back no verdict, `dispatch.sh` searches the last 4,000 bytes of its log for messages such as "rate limit", "usage limit", "429", "out of credits" or "not logged in". A match makes the result `RATELIMITED`, and the lead moves the task to the next runner without waiting. [bin/review.sh](bin/review.sh) does the same for reviewers.

### Milestone reviews

At the end of each milestone the lead runs the full test suite, pins the head commit, and makes a throwaway checkout of it. It writes a review packet with the diff, the commit list and a brief. The brief lists the files that carry money, records or state first, so a reviewer that runs short of time has already read those. [bin/review.sh](bin/review.sh) then runs three reviewers at the same time:

| Reviewer | Model | Kept read-only by | Stopped after |
|---|---|---|---|
| Codex | `gpt-6.1-sol`, reasoning `xhigh` | Codex's read-only sandbox | 45 minutes |
| Cursor | `grok-4.7-xhigh` | Cursor's plan mode | 45 minutes |
| agy | Gemini 4 Carbon (high) | a hook, [bin/agy-readonly-guard.mjs](bin/agy-readonly-guard.mjs), that allows only file reading, listing and search tools | 90 minutes |

A review usually takes 10 to 25 minutes. Reviewers are sometimes wrong, so the lead checks each finding against the code itself. A big problem gets one repair and no second review round. Big means money moving wrongly, data lost or written where it must not be, a false or misleading sentence on a screen, a security hole, failing tests or build, a screen that visibly misses its approved design, or a change that does not do what the plan says. Smaller findings go on the follow-up list.

If a reviewer cannot run, the others carry on and the lead records what that reviewer did not read. It never writes the missing review itself or swaps in another model. You can run some of the reviewers by naming them, for example `review.sh m1 <checkout> <build> carbon` for a Carbon review alone. If the plan names an extra reviewer, such as Claude Opus 5.5, the lead runs it too.

### The lead checks what workers claim

A clean exit proves nothing, so after each task the lead reads the worker's commits and reruns the tests the worker says passed. It also confirms that your main checkout is still clean and that the base branch has not moved.

### It runs to the end without asking

The build runs from setup to the final report without waiting for you. When the plan leaves a decision open, the lead picks the option the plan, the repo's docs or the code already point to, and otherwise the one easiest to undo. Where money, records or credentials are involved, it picks the option that does less. Each choice goes under "Lead's choices" in `status.md`, is marked in its commit message, and is sent to you in a message with the other options. If you answer differently, your answer becomes a new task.

Saying "stop" or "wait" in the conversation pauses the build. Pushing, merging, deploying, opening a pull request, and anything involving real money or real credentials wait for your word; the final report lists them as next steps you can take.

A task that stays blocked, or a repair that fails, does not stop the build either. The lead undoes the failed attempt with `git revert`, carries on with everything else, and reports the build as NOT READY with the evidence.

### Resume, or hand the lead to Codex

Since the state is on disk, `/build-with-agents resume <build folder>` picks a build up where it stopped. For each task still marked as running, the lead checks whether the work landed and verifies it if so. If not, it makes sure no worker is still running that task before it dispatches it again. Finished work is never redone.

If Claude Code's own usage runs out, the lead stops along with its workers. You can resume when the window resets, or start Codex as the lead from a terminal in the worktree. Codex reads the same SKILL.md and status file and sends every task through `dispatch.sh`. The command is in SKILL.md under "Resume". Cursor or agy can lead the same way.

### Final report

Before reporting, the lead commits the follow-up list to the repo's `TODOS.md`, checks the worktree for uncommitted files, removes it, and confirms its folder is gone. It then switches your main checkout to the build branch, so you can run the work from the folder you already use. If that checkout has uncommitted work, or a running program is using it, the lead leaves it on its current branch and says so.

The report covers what now works (with screenshots for screen changes), every choice the lead made, the branch and its commits, the test results the lead ran itself, each review and its repairs, the allowance used, what was not done, and a READY or NOT READY verdict with the one next step you can take.

### Runner checks and deadlines

[bin/preflight.sh](bin/preflight.sh) prints one line per runner: whether it is installed and logged in, its version, and whether every model in the roster is available to it. With `--live` it also asks each reviewer model for one word, which takes one to three minutes. A runner that is down is marked in `status.md` and routed around.

Every outside call has a deadline. GNU `timeout` is not used: on Windows it often stops only the wrapper and leaves agy, Node or Codex running, and macOS does not have it. [bin/deadline.sh](bin/deadline.sh) stops the whole process tree instead. Under Git Bash it uses `taskkill`. On Linux and macOS it starts each call in a process group of its own and stops the group. Linux does this with `setsid`; macOS has no `setsid`, so it uses the Perl that ships with macOS.


## Sign-in and permissions

You log each runner in yourself: `codex login`, `cursor-agent login`, and opening `agy` once. The skill never handles those credentials.

Reviews need no extra permission. Outside workers do: Claude Code's auto mode will not let cursor-agent, agy, codex or `claude -p` edit files on their own until you allow `bin/dispatch.sh` with a permission rule in `~/.claude/settings.json` or the repo's `.claude/settings*.json`. Without that rule, every task stays with a Claude subagent.

On Windows, cursor-agent is expected at `%LOCALAPPDATA%\cursor-agent\cursor-agent.cmd` and agy at `%LOCALAPPDATA%\agy\bin\agy.exe`. On macOS and Linux they are looked for on your PATH, then in `~/.local/bin`, where their installers put them. Set `CURSOR_AGENT` or `AGY` if yours are somewhere else.

## Settings

The allowance check reads these from the environment, or from `local.env` next to SKILL.md (git ignores that file):

| Setting | Default | What it does |
|---|---|---|
| `USAGE_LOW_PCT` | 10 | A runner is `LOW` at or below this percent left in any window |
| `QUOTA_CLI` | `quota-cli` on PATH, then `~/.cargo/bin`, then `~/.local/bin` | Path to quota-cli |
| `QUOTA_WATCH` | none | A Python file defining `run_quota_cli(None)`, tried before quota-cli. Useful when quota-cli misreads Cursor on Windows |
| `HERMES` | `hermes` on PATH, then `%LOCALAPPDATA%\hermes\bin` on Windows or `~/.local/bin` elsewhere | Path to Hermes, which is optional |

The other scripts read these environment variables:

| Variable | Default | What it does |
|---|---|---|
| `DISPATCH_TIMEOUT` | 3600 | Seconds before an outside worker is stopped |
| `DISPATCH_EFFORT` | `high` | Effort for `claude -p` workers |
| `REVIEW_TIMEOUT` | 2700 | Seconds before the Codex and Cursor reviews are stopped |
| `CARBON_REVIEW_TIMEOUT` | 5400 | Seconds before the agy Carbon review is stopped |
| `CODEX_REVIEW_MODEL`, `CODEX_REVIEW_EFFORT`, `CURSOR_REVIEW_MODEL`, `CARBON_REVIEW_MODEL` | see `bin/roster.sh` | Reviewer models. `auto`, and any model with "astra" in its name, are ignored |
| `CURSOR_AGENT`, `AGY` | under `%LOCALAPPDATA%` on Windows; on PATH, then in `~/.local/bin`, elsewhere | Where cursor-agent and agy are installed |

If `repo-notes.local.md` exists next to SKILL.md, the lead reads the section for the repo it is building and copies its data rules into every worker's brief. Git ignores this file too.

## Files

| Path | What it is |
|---|---|
| `SKILL.md` | The runbook the lead follows |
| `bin/dispatch.sh` | Runs one task on one outside worker |
| `bin/review.sh` | Runs the milestone reviewers |
| `bin/usage.py` | The allowance check |
| `bin/preflight.sh` | Checks each runner before a build |
| `bin/roster.sh` | Every model ID, and where cursor-agent and agy live |
| `bin/deadline.sh` | Deadlines that stop a whole process tree |
| `bin/agy-readonly-guard.mjs` | Keeps the agy reviewer read-only |
| `templates/` | The status file, worker rules and review brief that the lead fills in |
| `install.sh` | Installs the skill for Codex, Cursor and agy, and installs quota-cli |
| `TODOS.md` | Known follow-ups |
