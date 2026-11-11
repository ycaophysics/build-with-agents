# <BUILD NAME> build status

Plan: `plan.md` here (copy of `<ORIGINAL PLAN PATH>`). <WHICH SECTION IS THE AUTHORITY>
Started: <YYYY-MM-DD HH:MM> by <LEAD AND MODEL>.

- Main checkout: `<MAIN_CHECKOUT>` (the owner's; never edited by the build)
- Worktree: `<WORKTREE>`, branch `<BRANCH>`
- Base branch `<BASE>`, its commit: `<FULL SHA>`

**READY / NOT READY: NOT READY** — <one line, rewritten in place as the build moves>

## Runners

| Runner | Model | State | Since | Allowance left (usage.py line and time checked) |
|---|---|---|---|---|
| Claude subagent | claude-opus-5-5, high | up | | <claude line> |
| Claude subagent, easy | claude-sonnet-5-5, high | up | | (same line) |
| codex (review) | gpt-6.1-sol, xhigh | <up / logged out / down> | | <codex line> |
| cursor (review) | grok-4.7-xhigh | | | <cursor line> |
| agy Carbon (review) | gemini-4-carbon-high | | | <agy-gemini line> |
| agy Opus (worker, when Claude is out) | claude-opus-5-5-high | | | <agy-claude line> |

## Owner answers during the build

- <date>: <question> -> <his answer, verbatim where short>

## Lead's choices (made instead of waiting; for the owner to confirm or reverse)

| Decision | Chosen, and why | Other options | Told the owner |
|---|---|---|---|

## Items

States: todo, running <time> <runner>, done, partial, not done (why).

| Item | Tier | Worker | State | Commits | Tests |
|---|---|---|---|---|---|
| 0.1 Resume check | | lead | | | |
| 0.2 Nothing else building | | lead | | | |
| 0.3 Worktree + branch | | lead | | | |
| 0.4 Build folder | | lead | | | |
| 0.5 Tools in the worktree | | lead | | | |
| 0.6 Runner preflight | | lead | | | |
| 0.7 Baseline tests | | lead | | | |
| M1.1 <task> | | | | | |
| M1.R Milestone 1 checks + review | | lead | | | |

## Reviews

| Milestone | Pin | Codex | Cursor | Carbon | BIG -> repair commit | Not read |
|---|---|---|---|---|---|---|

## Follow-up list (SMALL findings and observations; they become TODOS.md lines at the end)

-

## Measurements

-
