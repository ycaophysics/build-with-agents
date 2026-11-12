---
name: build-with-agents
description: |
  Run an implementation build the owner's way: this session leads, bounded workers write the code
  in a worktree (Claude subagents by default; Cursor, Antigravity agy (Opus, Gemini 4 Carbon,
  Gemini 4 Hydrogen) and Codex when allowed, named by the owner, or when Claude is out), and Codex, Cursor
  and agy Gemini 4 Carbon review each milestone read-only at the same time. It checks how much
  allowance each runner has left and routes work around one that is nearly out. It runs from setup
  to the final report without stopping to wait for the owner.
  Use when the owner says "build this", "implement this plan", "run the build", "start the build",
  "/build-with-agents <plan>", or pastes a plan or build prompt and asks for it to be implemented
  with subagents. Also resumes a stopped build: "/build-with-agents resume <build folder>".
  Not for a request that asks only for a plan or a prompt: that is documents only.
argument-hint: "<plan path, or paste the plan> [notes] | resume <build folder>"
---

# Build with agents

You are the **lead**. You set up, cut the plan into tasks, dispatch each task to a worker, check
what comes back, run the milestone reviews, keep the status file, and report to the owner. You do
not write the feature code yourself.

Everything reusable lives here and in this skill's `bin/` and `templates/`. The owner gives only
the plan (and any notes). `<SKILL>` below means this skill's folder,
`~/.claude/skills/build-with-agents`. Write absolute paths in briefs and commands (expand `~`).

## Four rules that shape everything

1. **Your context is the scarce resource.** You outlive every worker. Read only a worker's final
   report, never its transcript; outside runners print one line through the scripts. All state
   lives in `status.md` on disk, never only in your memory. If you are compacted or restarted, the
   status file is the truth.
2. **Something the owner can see lands early.** Order the work so the first milestone ends in a
   visible or runnable change. One outside review per milestone, not per step.
3. **Only big problems are fixed during the build.** A big problem gets one repair and no second
   review round. Everything smaller goes on the follow-up list.
4. **Never stop in between** (owner, 2026-11-10). The build runs from setup to the final report
   without waiting for the owner; only his own "stop" or "wait" in this conversation pauses it.
   Never open a question dialog: it holds the whole build until he answers. A question goes in a
   message and in `status.md`, and the build goes on with your choice (section 6). Never end a turn
   with nothing running in the background (a worker, a review, a test run): its notification is
   what wakes you, and a turn that ends with nothing running stops the build until he types. The
   final report is the only turn that ends with nothing running.

## 0. Read the owner's message

- **The plan**: a path, or pasted text. Pasted text is saved as `plan.md` in the build folder.
  If the plan is itself a build prompt with its own rules (reviewers, models, milestones), its
  explicit rules win and this skill fills in the rest. User instructions win over both. A stop or
  approval point in a plan becomes a message to the owner, and the build carries on (rule 4).
- `resume <folder>`: go to **Resume** below.
- If he asked only for a plan or a prompt, stop: this skill builds. Give him the prompt inline as
  one pasteable block instead.
- Owner decisions the plan leaves open: make a choice for each as section 6 says, tell him all of
  them in one message, and start.

## 1. The roster

| Seat | Runner | Model | Started by |
|---|---|---|---|
| Lead | this Claude Code session | Opus 5.5 | |
| Lead when Claude Code is out (see **When Codex is the lead**) | codex | `gpt-6-astra` | the owner |
| Worker, hard and medium tasks | Claude subagent | Opus 5.5 (`claude-opus-5-5`): the repo's `opus-high` agent if `.claude/agents/opus-high.md` exists; else `general-purpose` with `model: "opus"`, `effort: "high"` | Agent tool |
| Worker, hard task still blocked after its follow-up (its step up) | Claude subagent | Fable 5.2 (`claude-fable-5-2`): `general-purpose` with `model: "fable"`, `effort: "high"` | Agent tool |
| Worker, easy tasks | Claude subagent | Sonnet 5.5 (`claude-sonnet-5-5`): `general-purpose` with `model: "sonnet"`, `effort: "high"` | Agent tool |
| Worker, hard when Claude Code is out | agy | `claude-opus-5-5-high` (the same Opus 5.5, Antigravity plan) | `dispatch.sh` (outside workers must be allowed) |
| Worker, hard second fallback; medium third fallback | cursor-agent | `claude-opus-5-5-high` (Opus 5.5 on Cursor's plan) | `dispatch.sh` (allowed) |
| Worker, hard third fallback; medium when Claude Code is out | agy | `gemini-4-carbon-medium` (high is too slow for work) | `dispatch.sh` (allowed) |
| Worker, hard fourth fallback | codex | `gpt-6-astra`, reasoning `xhigh` | `dispatch.sh` (allowed) |
| Worker, medium second fallback; easy third fallback | codex | `gpt-6.1-sol`, reasoning `xhigh` | `dispatch.sh` (allowed) |
| Worker, a hard task's step up when Claude Code is out | cursor-agent | `claude-fable-5-2-high` | `dispatch.sh` (allowed) |
| Worker, easy when Claude Code is out | cursor-agent | `cursor-grok-4.6-high-fast` | `dispatch.sh` (allowed) |
| Worker, easy second fallback | agy | `gemini-4-hydrogen-high` | `dispatch.sh` (allowed) |
| Reviewer | codex | `gpt-6.1-sol`, reasoning `xhigh`, read-only. **Never astra.** | `review.sh` |
| Reviewer | cursor-agent | `grok-4.7-xhigh`, plan mode (read-only) | `review.sh` |
| Reviewer | agy | `gemini-4-carbon-high`, behind a read-only guard. **Never Argon** (Carbon is better: owner, 2026-11-10). | `review.sh` |

The model IDs also live in `<SKILL>/bin/roster.sh`; change both in the same edit. Never pick a
model outside this table, never fall back to `auto`, never swap a reviewer's model because it is
down. If a task looks too big for its tier, move it up a tier. "Never astra" is a reviewer rule:
Astra is a hard task's last fallback and the model when Codex leads. No fallback list holds two
models that draw on the same `usage.py` line (see **Allowance**), because a rate-limited or `LOW`
line is marked down as a whole. agy has two lines, so agy Opus and agy Carbon can share the hard
list; Cursor and Codex have one line each, so each appears once per list.

Where things are: on Windows, `cursor-agent` is `%LOCALAPPDATA%\cursor-agent\cursor-agent.cmd`
and `agy` is `%LOCALAPPDATA%\agy\bin\agy.exe`, and neither is on Git Bash's PATH. On macOS and
Linux both are on PATH, or in `~/.local/bin`. The `CURSOR_AGENT` and `AGY` environment variables
override either. The scripts run in Git Bash on Windows and in any bash 3.2 or later elsewhere,
macOS's own included. Only the owner logs a runner in (`codex login`, `cursor-agent login`, opening
`agy` once); never handle his credentials.

**Outside workers need the owner's permission.** cursor-agent, agy, codex and `claude -p` editing
files unattended are refused by Claude Code's auto mode ("Create Unsafe Agents") unless the owner
has added a permission rule for `<SKILL>/bin/dispatch.sh`. Look for one in
`~/.claude/settings.json` and the repo's `.claude/settings*.json`. Without it, every task goes to
a Claude subagent; do not try an outside worker, and never work around a refusal. Reviews are
read-only and need no rule.

**Allowance.** `python3 -I <SKILL>/bin/usage.py` (`python` on Windows) prints one line per runner:
the share left in each window and when it resets. It takes about 10 seconds (80 at the very most:
every outside call has a deadline), only reads, writes nothing, and never stops a build.

| Line | Governs |
|---|---|
| `claude` | the lead and every Claude subagent |
| `codex` | the Codex reviewer and Codex as a worker |
| `cursor` | the Cursor reviewer and every Cursor worker |
| `agy-gemini` | agy Carbon (worker and reviewer) and agy Gemini 4 Hydrogen |
| `agy-claude` | agy Opus |

A line is `LOW` when any window has 10% or less left, `unknown` when it could not be read (a tool
is missing or logged out), and `ok` otherwise; the output ends with `LOW:` and `UNKNOWN:` lists.
It reads `quota-cli` for every runner, agy included (`install.sh` installs it). Hermes (`hermes
usage`) is optional: when it is installed, it fills in agy's lines if quota-cli cannot read them.
On macOS the `cursor` line is `unknown`, because cursor-agent keeps its login in the Keychain
there. The settings and their overrides are described at the top of `usage.py` and go in
`<SKILL>/local.env`, which git ignores.

- **When to run it**: at setup after the preflight, before each milestone review, after any
  `RATELIMITED` line, and once at the end. Copy its lines into the Runners table in `status.md`;
  the first and last run also go under Measurements.
- **Workers**: a `LOW` line counts as rate-limited before any model on it is tried. Go to the next
  entry on the task's list, and bring the line back when a later run shows it `ok`. If `claude` is
  `LOW`, give every task to the tier's outside runners when outside workers are allowed (otherwise
  carry on with Claude), and tell the owner in one line what is left and when it resets.
- **Reviewers** always run, as before. Write a `LOW` reviewer's line next to its review in
  `status.md`, so a failure there explains itself.
- **`unknown` changes nothing.** Only `LOW` moves work.

## 2. Setup (you, in order; record each in `status.md`)

`<base>` below is the branch the plan builds on; when the plan names none, the repo's default
branch (`main` or `master`, whichever exists).

1. **Resume check.** If the build folder already has a `status.md`, go to **Resume**.
2. **Nothing else is building here.** In the main checkout: `git status`, `git log <base> -5`,
   `git worktree list`, and the running python, node, codex, cursor-agent, agy and claude
   processes with their command lines (`ps -Ao pid,command` on macOS and Linux). If another
   process is editing this repo now, write it in `status.md`, tell the owner in one line, and carry
   on: the build works only in its own worktree.
   The owner's own running app and scheduled jobs are expected (see **Repo notes**).
3. **Worktree and branch.** Never build in the main checkout. From the main checkout:
   `git worktree add ../<repo-short>-wt-<slug> -b <branch> <base>`. Record the base commit.
4. **Build folder**: `~/.claude/plans/<slug>-build/` with `logs/`, `reviews/`,
   `briefs/`, `reports/`. Copy the plan in as `plan.md` so reviewers read the same text you do.
5. **Tools in the worktree** (see **Repo notes**): which interpreter, `npm ci`, links.
6. **Runners**: `bash <SKILL>/bin/preflight.sh --live`. One line per runner. A logged-out or
   missing runner does not stop the build: mark it down in `status.md`, tell the owner it needs
   his login, and route around it. Then run `usage.py` (see **Allowance**).
7. **Status file** from `<SKILL>/templates/status.md`; copy into it what you noted in steps 2 to 6.
8. **Baseline**: run the repo's checks once on the untouched worktree. If something already fails,
   record it in `status.md` as failing before the build, tell the owner in one line, and carry on;
   it is not yours to fix and does not count against the build.

## 3. Cut the plan into milestones and tasks

- Use the plan's own milestones and task list when it has them. Otherwise make two to four
  milestones; each ends in something the owner can see or run, visible work first.
- Each task: one bounded job, the files it owns, the plan sections that bind it, its exact
  verification commands, and a tier:
  - **hard**: money, orders, broker or account paths, state machines, concurrency, migrations,
    anything where a mistake loses money or data. Claude subagent on Opus 5.5 (outside: agy Opus,
    then Cursor Opus, then agy Carbon medium, then codex Astra). Its step up, when it stays
    blocked, is Fable 5.2 (section 4). Never a fast or easy-tier model.
  - **medium**: plumbing with real edge cases, tests that need thought, screens. Claude subagent
    on Opus 5.5 (outside: agy Carbon medium, then codex Sol, then Cursor Opus).
  - **easy**: mechanical and fully specified (copy edits from given text, renames, a constant, a
    test from a given table). Claude subagent on Sonnet 5.5 at high effort (outside, only when
    Claude is out: Cursor grok, then agy Gemini 4 Hydrogen, then codex Sol).
- Write the milestones and tasks into `status.md` before the first dispatch. Smallest build that
  meets the plan: no extra features, refactors or extra review rounds.

## 4. Dispatch

- **Claim the row first**: mark it `running <time> <runner>` in `status.md`, then dispatch. A row
  left at `todo` while a worker was editing is how the same task gets run twice.
- **Brief**: write `<build>/briefs/<task>.md` = `<SKILL>/templates/worker-rules.md` with its
  angle brackets filled in, plus the task section. Workers read the brief from disk.
- **Claude worker**: Agent tool, prompt "Read `<brief>` and follow it exactly. Your final message
  is your report." Name the tier's model and effort from the roster on the call: Opus for hard and
  medium, `model: "sonnet"` and `effort: "high"` for easy, `model: "fable"` and `effort: "high"`
  for a hard task's step up. Let it run in the background and wait for its notification.
- **Outside worker** (only when allowed):
  `bash <SKILL>/bin/dispatch.sh <task> <claude|agy|cursor|codex> <model> <brief> <worktree> <build>`.
  It prints one line: `PASS`, `VERIFYFAIL`, `NOVERDICT`, `FAIL`, `EMPTY`, `RATELIMITED` (exit
  86) or `TIMEOUT` (exit 87). Read `<build>/reports/<task>.md`, not the log; on a failure read only
  `tail -c 2000` of the log, never `tail -n`.
- **Rate limited, or `LOW` in the latest `usage.py` run**: reroute the same task to the next entry
  on its tier's list at once; do not wait. Mark that allowance line down in `status.md` with the
  time (for agy, `agy-claude` or `agy-gemini`, whichever the model draws on), run
  `usage.py` to see when its window resets, and look at it again then (after 30 minutes if that is
  `unknown`).
- **One code-changing worker at a time** in the build worktree: workers share its files and its
  git index. Run workers in parallel only for tasks that touch disjoint files, at most three at
  once, each in its own worktree that you make from the build branch head
  (`git -C <worktree> worktree add <path> -b <task-branch> HEAD`); bring each back with
  `git -C <worktree> cherry-pick <head>..<task-branch>` and remove its worktree. If the
  cherry-pick stops on a conflict, run `git -C <worktree> cherry-pick --abort` so the build
  worktree is not left in the middle of one, record that task as not merged in `status.md`, and
  carry on with the build. (The Agent tool's own worktree option starts from the main checkout's
  HEAD, not the build branch.)
- **Check every claim yourself** after each worker: `git -C <worktree> log` and `show --stat` for
  its commits, rerun the tests it says passed, and confirm the main checkout is still clean and
  `<base>` has not moved. A worker exiting cleanly proves nothing.
- **PARTIAL or BLOCKED**: one follow-up dispatch that names the gap. Still blocked: move the task
  up a tier once. A hard task moves up to Fable 5.2: a Claude subagent, or Cursor
  `claude-fable-5-2-high` when Claude is rate limited or `LOW`; if neither can run, go to section 6
  rather than a weaker model. Still blocked after that: handle it as section 6 says. Never a third
  attempt at the same tier.

## 5. Milestone review

1. **Full checks** at the milestone head: the repo's whole test suite (pytest as section 7 says),
   frontend tests and build, doc checks. Record exit codes and counts.
2. **Pin**: record the head as `<pin>` in `status.md`, then make a detached, throwaway checkout:
   `git -C <worktree> worktree add <repos folder>/<repo-short>-review-m<N> <pin> --detach`
   (`<repos folder>` is the folder that holds the main checkout).
   You may keep working in the build worktree meanwhile, on work that does not depend on this
   review.
3. **Packet** in `<build>/reviews/`: `m<N>.diff` (`git diff <last pin or base>..<pin>`; the last
   milestone also gets `full.diff` from the base), `m<N>-commits.txt` (`git log --oneline`), and
   `m<N>-brief.md` from `<SKILL>/templates/review-brief.md` with every angle bracket filled in.
   Its reading order names the files that carry money, records or state first: a reviewer that
   reads everything runs out of time before it writes (a Carbon review did, 2026-11-10).
4. **Run** `usage.py` first and write each reviewer's line in `status.md` (a `LOW` reviewer still
   runs). Then `bash <SKILL>/bin/review.sh m<N> <review checkout> <build>` in the background; it runs
   Codex, Cursor and agy Carbon at the same time (usually 10 to 25 minutes; Carbon high is slow,
   so it is stopped at 90 minutes, the others at 45) and prints one line each. Name
   reviewers after the build folder to run only some (for example `... <build> carbon` when the
   owner asks for a Carbon review alone). Read only `<build>/reviews/m<N>-<reviewer>.md`. If the
   plan names another reviewer (for example a Claude Opus 5.5 `xhigh` review), run it too, in a
   fresh subagent told to review only.
5. **Check every finding against the code yourself.** Reviewers are wrong sometimes; say which
   findings held up.
6. **BIG** = money moving wrongly, data lost or written where it must not be, a false or
   misleading sentence on a screen, a security hole, failing tests or build, a screen that visibly
   misses its approved design, or the change not doing what the plan says. Each BIG that holds up
   gets one repair task; rerun its tests; record the repair commit against the finding. No second
   review round.
7. **SMALL** findings that hold up go on the follow-up list in `status.md`.
8. **A reviewer that cannot run** (logged out, rate limited, timed out, empty): go on with the
   others and write down what it did not read. Never write a review in its place and never swap in
   another model.
9. **Remove the review checkout**: `git -C <worktree> worktree remove --force <review checkout>`
   (`--force` because agy's guard leaves an untracked `.agents/hooks.json` in it).
10. **Tell the owner in three lines**: what now works, a screenshot or before/after when the
    milestone is visible, and what comes next. Start the next milestone's work in the same turn;
    never wait for a reply.

## 6. Problems that do not stop the build

Nothing here pauses the build (rule 4). Each goes into `status.md` and the final report.

- **A decision the plan does not make, a plan that cannot be built as written, or code that
  contradicts it.** Choose the option the plan, the repo's docs or the code already point to;
  otherwise the one easiest to undo. Where money, records or credentials are involved, choose the
  option that does less and stays safe: leave a step out rather than guess how it moves money.
  Write it under "Lead's choices" in `status.md` and say "lead's choice" in its commit message.
  Tell the owner in plain English: what you saw, what you chose, and the other options. If he
  answers differently, his answer becomes a task.
- **A big problem whose repair failed, or a task still blocked after its tier move.** Keep the
  branch's tests passing (undo a failed attempt with `git revert`, never `reset`), carry on with
  everything that does not need it, and report NOT READY with the evidence.
- **Another process editing the repo, or a runner logged out.** Work only in the build's own
  worktree; give each task to any runner on its tier that can do it. A task no runner can do is
  recorded as not done.
- **Push, merge, deploy, a pull request, real money, real credentials.** None of these happens
  during the build without the owner's word, and none of them is a reason to stop: the final report
  names them as the next step he can take.

## 7. Rules for the whole build

- Commit each logical step as it goes green, not a whole milestone at once. Every commit message
  ends with a `Co-Authored-By:` line naming the model that actually did that work.
- Never push, merge, rebase onto `<base>`, open a PR or deploy unless the owner says so.
- Tests run with the command the repo's `CLAUDE.md` and `AGENTS.md` name; that command wins. When
  it is pytest and pytest-xdist is installed, add `-n auto`. If `-n` is rejected, record it in
  `status.md` and run the repo's command without `-n`; that alone does not fail the build. The
  worker template says the same.
- Owner-facing words are plain English: what a person sees and can do. No "gate", no invented
  shorthand, no internal codes on screen.
- Docs are edited in place; obsolete text is deleted, not corrected below.
- Never stage with `git add -A` or `.`; never `reset --hard`, `clean`, or stash someone else's
  work.

## 8. The final report (to the owner, plain English, short)

First, in this order (the owner's rule for every worktree):
- Write the follow-up list into the repo's `TODOS.md` (or its deferred-work file) and commit it as
  the build's last commit on the build branch.
- Look in the build worktree for uncommitted files, then remove the worktree, and confirm with
  `git worktree list` that it is gone and that its folder is gone from disk (`git worktree remove`
  can leave `node_modules` behind).
- Switch the main checkout to the build branch, so he can run the work from the folder he already
  uses. If the main checkout has uncommitted work, leave it where it is and say so. A clean tree is
  not enough: if a python, node, codex, cursor-agent, agy or claude process has a command line that
  names the main checkout, also leave it on its current branch and say so.

Then the report:

1. What now works, as he would see it, with screenshots for screen changes.
2. Every lead's choice, with the other options, for him to confirm or reverse.
3. The branch, its head, the commit list, that nothing was merged or pushed, and whether the main
   checkout is now on the branch (or why not).
4. Test results you ran yourself at the end (commands, counts, exit codes).
5. Each milestone review: the pin, each reviewer's verdict, each big problem and its repair commit,
   and what any missing reviewer did not read.
6. Allowance left on each runner at the start and at the end (the first and last `usage.py` runs),
   so he sees what the build cost, and any runner that was `LOW` and what moved off it.
7. What was not done and why, and the follow-up list (already committed in `TODOS.md`).
8. READY or NOT READY, and the one next step he can take (for example "say merge").

## Resume

Read `status.md`. Trust it over memory. For a row left `running`: check `git -C <worktree> log`,
`git status` and `<build>/reports/<task>.md`. If the work landed, verify it and mark it done. If
not, first check that no worker is still running for the task (a python, node, codex,
cursor-agent, agy or claude process whose command line names the task or the worktree); if one
is, wait for it and do not dispatch. Only then delete `<build>/logs/<task>.lock` if present and
dispatch the task again. Never redo a finished item.

If Claude Code's own usage ran out, this session stops with its workers: the build waits on disk
(`usage.py` shows when it resets).
Either resume here when it resets, or the owner hands the lead to Codex, which reads this same
file, from a terminal in the worktree:

```
codex exec -m gpt-6-astra -s danger-full-access -C "<worktree>" "Read <SKILL>/SKILL.md and act as the lead. Resume the build whose status file is <build>/status.md. You are the lead described in its section 'When Codex is the lead'."
```

## When Codex is the lead

The roster's lead seat is Codex `gpt-6-astra`; Cursor or agy may lead the same way if the owner
starts one with this skill. A lead without Claude Code's Agent tool sends every worker through
`dispatch.sh` (Codex launched with `-s danger-full-access` may run it): hard to
`claude claude-opus-5-5` (on `RATELIMITED`: `agy claude-opus-5-5-high`, then
`cursor claude-opus-5-5-high`, then `agy gemini-4-carbon-medium`, then `codex gpt-6-astra`; a
hard task's step up goes to `claude claude-fable-5-2`, or `cursor claude-fable-5-2-high` on
`RATELIMITED`, and to section 6 if neither runs), medium to `claude claude-opus-5-5` first (on
`RATELIMITED`: `agy gemini-4-carbon-medium`, then `codex gpt-6.1-sol`, then
`cursor claude-opus-5-5-high`), easy to `claude claude-sonnet-5-5` (on `RATELIMITED`:
`cursor cursor-grok-4.6-high-fast`, then `agy gemini-4-hydrogen-high`, then `codex gpt-6.1-sol`).
A `LOW` line from `usage.py` counts as `RATELIMITED` in every chain here. Reviews still run through
`review.sh`. Codex is a one-shot process: a question printed to the screen
reaches nobody, so it follows rule 4 and section 6 the same way (a lead's choice in `status.md`)
and stops only at the final report.

## Other tools

Codex, Cursor and agy load this skill too. `bash ~/.claude/skills/build-with-agents/install.sh`
puts it in each one's skills folder (links for Codex and Cursor; a copy for agy, refreshed by
running it again after an edit), and installs quota-cli if it is missing. Edit only
`~/.claude/skills/build-with-agents`. If `usage.py` says quota-cli is not found, tell the owner to
run the installer; do not install software yourself during a build.

## Repo notes

Read the repo's own `CLAUDE.md` and `AGENTS.md`: they are binding and name the test commands. If
`<SKILL>/repo-notes.local.md` exists (the owner's machine-specific notes, kept out of git), read
the section for the repo you are building in, and copy its data rules into every brief. Deferred
work goes in the repo's `TODOS.md`.
