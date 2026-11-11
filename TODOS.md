# Follow-up list

Small problems found by the Codex and Carbon reviews of commit 6aba0fb (2026-11-11) that were not
fixed in the repair commit. None of them can happen on the skill's normal path today.

## Read-only guard (`bin/agy-readonly-guard.mjs`)
- The `--allow-read-commands` mode, which nothing uses, accepts `git branch -D x` (it allows any
  `git branch`) and `git diff --output=file` (it writes). Remove the mode, or refuse those two.

## Installing (`install.sh`)
- A runner that is installed but has no `skills` folder yet is skipped. Create the folder when the
  runner's own config folder exists.
- A broken junction (its target was moved) is not removed, because `[ -e ]` is false for it, so the
  next install fails. A directory symlink is deleted with `rm -rf` instead of being unlinked.

## Running workers (`bin/dispatch.sh`)
- A worker that wrote `PASS` is accepted even when its runner exited with an error or wrote no
  report (the line then says `report=(no report written)`).
- The rate-limit check looks for words such as `quota`, `insufficient`, `401` and `429` anywhere in
  the last 4 KB of a failed run, so an ordinary crash that mentions one of them reads as
  `RATELIMITED`.

## Running reviews (`bin/review.sh`)
- `--print-timeout` equals the outer deadline, so agy giving up first shows as `FAIL rc=1`, not
  `TIMEOUT`. On Windows the outer `timeout` may stop only the wrapper and leave the real
  Node or Codex process running.
- The agy guard is written into the shared review checkout while Codex and Cursor read it, and the
  changed-files warning ignores `.agents/`. A repository that tracks its own `.agents/` files would
  have them overwritten.

## Paths and checks (`bin/review.sh`, `bin/dispatch.sh`, `bin/preflight.sh`, `bin/roster.sh`)
- `win()` uses `cygpath -m`, not `-ma`, so a relative build or brief path breaks after the script
  changes folder.
- `preflight.sh` calls `timeout` without checking it exists (it prints "MISSING" at the end but the
  earlier checks fail with exit 127, and agy is then reported as needing a sign-in).
- `roster.sh` does not check that `cursor-agent` or `agy` exist before falling back to the default
  folders.

## Instructions (`SKILL.md`)
- "When Codex is the lead" sends medium tasks straight to agy Carbon even when Claude's allowance
  is `ok`; it only matters when Codex was started as the lead on purpose.
