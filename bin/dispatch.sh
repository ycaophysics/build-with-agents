#!/usr/bin/env bash
# Hand one build task to one outside worker and print ONE line, so the lead's context never
# holds a worker transcript. Claude subagents do not go through here: the lead starts them with
# its own Agent tool. This is for cursor-agent, agy, codex, and `claude -p` when the lead is
# not Claude Code.
#
#   dispatch.sh <task> <runner> <model> <brief> <worktree> <build-dir>
#     runner: claude | agy | cursor | codex
#
#   dispatch.sh E3 cursor cursor-grok-4.6-high-fast  <build>/briefs/E3.md  <worktree>  <build>
#   dispatch.sh D1 agy    claude-opus-5-5-high       <build>/briefs/D1.md  <worktree>  <build>
#
# The worker writes two files, and they are all the lead reads:
#   <build>/reports/<task>.md      its final report (STATUS, COMMITS, FILES CHANGED, ...)
#   <build>/logs/<task>.verdict    the single word PASS or FAIL
# The full transcript goes to <build>/logs/<task>-<stamp>.log and is never read whole.
#
# Exit codes:
#   0   PASS        the runner exited 0, the verdict file says PASS, and the report is written
#   1   FAIL        runner error, VERIFYFAIL, NOVERDICT, EMPTY, or a PASS verdict without a
#                   clean exit or without a report
#   86  RATELIMITED rate limited, out of credit, or logged out: reroute, do not wait
#   87  TIMEOUT     hung and killed at the deadline (DISPATCH_TIMEOUT, default 3600 s)
#   2   usage, missing file, or the task is already running (lock)
#
# These runners edit files unattended. Claude Code's auto mode refuses to start one ("Create
# Unsafe Agents") unless the owner has allowed this script with a permission rule. A refusal is
# not a failure to work around: give the task to a Claude subagent instead.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=roster.sh
. "$HERE/roster.sh"   # CURSOR and AGY: where the two runners live
# shellcheck source=deadline.sh
. "$HERE/deadline.sh"  # run_deadline: stops the whole process tree at the deadline
TIMEOUT="${DISPATCH_TIMEOUT:-3600}"
CLAUDE_EFFORT="${DISPATCH_EFFORT:-high}"

if [ "$#" -ne 6 ]; then
  echo "usage: dispatch.sh <task> <claude|agy|cursor|codex> <model> <brief> <worktree> <build-dir>" >&2
  exit 2
fi
TASK="$1"; RUNNER="$2"; MODEL="$3"; BRIEF="$4"; WT="$5"; BUILD="$6"

case "$RUNNER" in claude|agy|cursor|codex) ;; *)
  echo "$TASK - unknown runner '$RUNNER' (want claude, agy, cursor or codex)" >&2; exit 2 ;;
esac
[ -f "$BRIEF" ] || { echo "$TASK $RUNNER NOBRIEF $BRIEF does not exist" >&2; exit 2; }
git -C "$WT" rev-parse --git-dir >/dev/null 2>&1 || { echo "$TASK $RUNNER NOWORKTREE $WT is not a git checkout" >&2; exit 2; }

mkdir -p "$BUILD/logs" "$BUILD/reports"

# One task, one worker. Two dispatches of the same task would edit the same files.
LOCK="$BUILD/logs/$TASK.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "$TASK $RUNNER LOCKED already dispatched (remove $LOCK if that is stale)" >&2
  exit 2
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
LOG="$BUILD/logs/$TASK-$STAMP.log"
VERDICT="$BUILD/logs/$TASK.verdict"
REPORT="$BUILD/reports/$TASK.md"
rm -f "$VERDICT" "$REPORT"

# Runners get absolute paths, because they start in another folder. On Windows those are C:/...
# paths (forward slashes work in every runner and need no escaping).
runner_path() {
  cygpath -ma "$1" 2>/dev/null && return
  case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac
}
WT_W="$(runner_path "$WT")"; BUILD_W="$(runner_path "$BUILD")"; BRIEF_W="$(runner_path "$BRIEF")"
VERDICT_W="$(runner_path "$VERDICT")"; REPORT_W="$(runner_path "$REPORT")"

# Short on purpose: on Windows cursor-agent runs through cmd.exe, which cuts a command line at
# 8,191 characters, and an inlined brief once lost its "what not to do" list that way. The worker
# reads the brief from disk. cmd.exe also cuts an argument at its first line break (tested
# 2026-11-11), so cursor-agent is given a one-line pointer to this text, not the text itself.
PROMPT="You are an implementation worker doing exactly one task: ${TASK}.
Read ${BRIEF_W} and follow it exactly. Work only in ${WT_W}.
When you finish, write two files; they are the only handoff the lead reads, and a chat answer is not one:
1. ${REPORT_W}: your final report, under 60 lines, with exactly these sections: STATUS (DONE | PARTIAL | BLOCKED), COMMITS (hash + subject), FILES CHANGED, VERIFICATION (each command, exit code, pass/fail counts), OPEN ITEMS, ARTIFACT PATHS.
2. ${VERDICT_W}: the single word PASS or FAIL. PASS only if the verification commands in your brief actually passed. A PASS with failing tests is worse than FAIL, because it is believed."

PROMPT_FILE="$BUILD/logs/$TASK.prompt.md"
printf '%s\n' "$PROMPT" > "$PROMPT_FILE"
PROMPT_ONE_LINE="Read $(runner_path "$PROMPT_FILE") and follow it exactly."

run_with_deadline() { run_deadline "$TIMEOUT" "$@"; }

start=$(date +%s)
case "$RUNNER" in
  claude)
    (cd "$WT" && run_with_deadline claude -p "$PROMPT" --model "$MODEL" --effort "$CLAUDE_EFFORT" \
      --permission-mode bypassPermissions --add-dir "$BUILD_W") >"$LOG" 2>&1; rc=$? ;;
  agy)
    (cd "$WT" && run_with_deadline "$AGY" -p "$PROMPT" --model "$MODEL" --dangerously-skip-permissions \
      --add-dir "$BUILD_W" --print-timeout 0 --output-format text) >"$LOG" 2>&1; rc=$? ;;
  cursor)
    run_with_deadline "$CURSOR" -p --model "$MODEL" --force --trust --workspace "$WT_W" \
      --add-dir "$BUILD_W" --output-format text "$PROMPT_ONE_LINE" >"$LOG" 2>&1; rc=$? ;;
  codex)
    # Codex's Windows sandbox ("unelevated" in ~/.codex/config.toml) cannot create pipes or temp
    # files, which looks like a broken repo. On macOS and Linux its workspace-write sandbox would
    # refuse the report and verdict, which go to the build folder outside the worktree. A worker
    # that edits, runs tests and writes its report needs full access.
    printf '%s' "$PROMPT" | run_with_deadline codex exec - -m "$MODEL" -s danger-full-access \
      -C "$WT_W" -o "$(runner_path "$BUILD/logs/$TASK-$STAMP.last.md")" >"$LOG" 2>&1; rc=$? ;;
esac
elapsed=$(( $(date +%s) - start ))
dur=$(printf '%02d:%02d:%02d' $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60)))
WHO="$RUNNER:$MODEL"

# Only the end of the log is searched, and only when the run did not hand back a verdict: a brief
# that quotes the words "rate limit" once made a finished task look rate limited. Broad words that
# also turn up in ordinary crashes (quota, insufficient, a bare 401 or 403, "resets at") are not
# matched.
is_rate_limited() {
  tail -c 4000 "$1" 2>/dev/null | grep -qiE "rate.?limit|usage limit|session limit|hit your limit|spend(ing)? limit|resource[_ -]?exhausted|too many requests|\b429\b|try again (later|in)|overloaded|at capacity|out of credits|unauthori[sz]ed|not authenticated|authentication required|not logged in|log ?in required"
}

if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
  echo "$TASK $WHO TIMEOUT ${TIMEOUT}s $dur log=$LOG"; exit 87
fi
if [ ! -f "$VERDICT" ]; then
  if is_rate_limited "$LOG"; then echo "$TASK $WHO RATELIMITED $dur log=$LOG"; exit 86; fi
  if [ "$rc" -ne 0 ]; then echo "$TASK $WHO FAIL rc=$rc $dur log=$LOG"; exit 1; fi
  if [ ! -s "$LOG" ]; then echo "$TASK $WHO EMPTY no output $dur log=$LOG"; exit 1; fi
  echo "$TASK $WHO NOVERDICT exited 0 but wrote no verdict $dur log=$LOG"; exit 1
fi

v="$(tr -d '[:space:]' < "$VERDICT" | tr '[:lower:]' '[:upper:]')"
if [ "$v" = "PASS" ]; then
  # PASS counts only with a clean exit and a written report.
  if [ "$rc" -ne 0 ]; then
    echo "$TASK $WHO FAIL rc=$rc verdict says PASS but the runner exited with an error $dur log=$LOG"; exit 1
  fi
  if [ ! -s "$REPORT" ]; then
    echo "$TASK $WHO FAIL verdict says PASS but the report $REPORT is missing or empty $dur log=$LOG"; exit 1
  fi
  echo "$TASK $WHO PASS $dur report=$REPORT"; exit 0
fi
echo "$TASK $WHO VERIFYFAIL verdict=$v $dur report=$REPORT"; exit 1
