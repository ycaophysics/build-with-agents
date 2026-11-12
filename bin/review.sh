#!/usr/bin/env bash
# Run the milestone reviewers at the same time, read-only, on a pinned checkout, and print ONE
# line per reviewer. The lead then reads only <build>/reviews/<milestone>-<reviewer>.md.
#
#   review.sh <milestone> <review-checkout> <build-dir> [codex] [cursor] [carbon]
#
#   review.sh m1 ~/code/myrepo-review-m1 ~/.claude/plans/x-build
#
# The brief must already be at <build>/reviews/<milestone>-brief.md. With no reviewer named, all
# three run. A reviewer that cannot run is reported, never replaced by another model.
#
# Read-only, per reviewer:
#   codex   sandbox read-only; Codex itself writes only the -o file.
#   cursor  --mode plan, Cursor's read-only planning mode.
#   carbon  agy on Gemini 4 Carbon (Argon is no longer used: owner, 2026-11-10), with --sandbox.
#           A PreToolUse guard refuses every write, web, MCP, subagent and shell tool (agy's
#           headless mode ends the run with no output when a shell command needs a permission,
#           and --dangerously-skip-permissions is refused by Claude Code's auto mode). The guard
#           itself sits in a temp folder; agy reads hooks only from <checkout>/.agents/hooks.json,
#           so that one file is written into the checkout, and only when the repository does not
#           track it. If it does, the guard is not installed and the carbon line says so. Carbon
#           reads with its own file tools, and the guard logs each tool call to
#           <build>/logs/<m>-carbon-guard.log. The checkout is a throwaway, and any file changed
#           anyway is reported on its line.
#
# Exit: 0 when at least one reviewer wrote a review, 1 when none did, 2 on bad usage.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=roster.sh
. "$HERE/roster.sh"
# shellcheck source=deadline.sh
. "$HERE/deadline.sh"  # run_deadline: stops the whole process tree at the deadline
TIMEOUT="${REVIEW_TIMEOUT:-2700}"
# Carbon high is slow: a run stopped at 45 minutes lost its whole review; one given 90 finished
# (2026-11-10). Its brief still asks for the report by minute 35; the rest is margin.
CARBON_TIMEOUT="${CARBON_REVIEW_TIMEOUT:-5400}"
timeout_of() { if [ "$1" = carbon ]; then echo "$CARBON_TIMEOUT"; else echo "$TIMEOUT"; fi; }

if [ "$#" -lt 3 ]; then
  echo "usage: review.sh <milestone> <review-checkout> <build-dir> [codex] [cursor] [carbon]" >&2
  exit 2
fi
M="$1"; CO="$2"; BUILD="$3"; shift 3
REVIEWERS="${*:-codex cursor carbon}"
REVIEWERS="$(printf '%s\n' $REVIEWERS | awk '!seen[$0]++' | tr '\n' ' ')"   # a name given twice runs once
BRIEF="$BUILD/reviews/$M-brief.md"
[ -f "$BRIEF" ] || { echo "$M NOBRIEF $BRIEF does not exist" >&2; exit 2; }
git -C "$CO" rev-parse --git-dir >/dev/null 2>&1 || { echo "$M NOCHECKOUT $CO is not a git checkout" >&2; exit 2; }
mkdir -p "$BUILD/logs" "$BUILD/reviews"

# Absolute paths, because the runners start in another folder: C:/... paths on Windows.
runner_path() {
  cygpath -ma "$1" 2>/dev/null && return
  case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac
}
CO_W="$(runner_path "$CO")"; BUILD_W="$(runner_path "$BUILD")"; BRIEF_W="$(runner_path "$BRIEF")"
ASK="Read ${BRIEF_W} and follow it exactly. Reply with the review report only."

run_codex() {
  run_deadline "$TIMEOUT" codex exec - -s read-only -m "$CODEX_REVIEW_MODEL" \
    -c "model_reasoning_effort=\"$CODEX_REVIEW_EFFORT\"" -C "$CO_W" \
    -o "$(runner_path "$BUILD/reviews/$M-codex.md")" < "$BRIEF" > "$BUILD/logs/$M-codex.log" 2>&1
}

run_cursor() {
  run_deadline "$TIMEOUT" "$CURSOR" -p --mode plan --model "$CURSOR_REVIEW_MODEL" --trust --workspace "$CO_W" \
    --add-dir "$BUILD_W" --output-format text "$ASK" \
    > "$BUILD/reviews/$M-cursor.md" 2> "$BUILD/logs/$M-cursor.log"
}

# Carbon's guard is set up before any reviewer starts, and nothing the repository tracks is
# written: the guard goes in a temp folder, and hooks.json goes into the checkout only when the
# repository does not track it. CARBON_NOTE is added to the carbon line. HOOKS_MADE marks the one
# file this script wrote into the checkout, the only file the changed-files check leaves out.
CARBON_NOTE=""; HOOKS_MADE=""; GUARD_DIR=""; GUARD_LOG_TMP=""
cleanup() {
  if [ -n "$GUARD_LOG_TMP" ] && [ -s "$GUARD_LOG_TMP" ]; then
    cp "$GUARD_LOG_TMP" "$BUILD/logs/$M-carbon-guard.log"
  fi
  if [ -n "$GUARD_DIR" ]; then rm -rf "$GUARD_DIR"; fi
}
trap cleanup EXIT

setup_carbon_guard() {
  if git -C "$CO" ls-files --error-unmatch -- .agents/hooks.json >/dev/null 2>&1; then
    CARBON_NOTE=" WARNING guard not installed: the checkout tracks .agents/hooks.json, so carbon ran with --sandbox only"
    return
  fi
  GUARD_DIR="$(mktemp -d)"
  cp "$HERE/agy-readonly-guard.mjs" "$GUARD_DIR/guard.mjs"
  # agy hands the hook command to Windows with its quotes intact, so the paths in it can have no
  # quotes and no spaces. The same rule is kept on macOS and Linux. There, the short-name fallback
  # (cygpath -d) does not exist, but temp folders have no spaces.
  local gpath glog
  gpath="$(runner_path "$GUARD_DIR/guard.mjs")"
  case "$gpath" in *" "*) gpath="$(cygpath -d "$GUARD_DIR/guard.mjs" 2>/dev/null | tr '\\' '/')" ;; esac
  case "$gpath" in ""|*" "*)
    CARBON_NOTE=" WARNING guard not installed: its temp path has spaces, so carbon ran with --sandbox only"
    return ;;
  esac
  glog="$(runner_path "$BUILD/logs/$M-carbon-guard.log")"
  case "$glog" in *" "*) GUARD_LOG_TMP="$GUARD_DIR/guard.log"; glog="$(runner_path "$GUARD_LOG_TMP")" ;; esac
  mkdir -p "$CO/.agents"
  printf '{\n  "read-only-guard": {\n    "PreToolUse": [\n      {"matcher": "*", "hooks": [{"type": "command", "command": "node %s %s", "timeout": 10}]}\n    ]\n  }\n}\n' \
    "$gpath" "$glog" > "$CO/.agents/hooks.json" && HOOKS_MADE=yes
}

run_carbon() {
  # agy's own --print-timeout is two minutes past the outer deadline, so the deadline is what stops
  # a slow run and its line says TIMEOUT, not FAIL rc=1.
  (cd "$CO" && run_deadline "$CARBON_TIMEOUT" "$AGY" -p "$ASK Shell commands are switched off for this review: use your file reading, listing and search tools." \
    --model "$CARBON_REVIEW_MODEL" --sandbox --add-dir "$BUILD_W" --print-timeout "$((CARBON_TIMEOUT + 120))s" \
    --output-format text) > "$BUILD/reviews/$M-carbon.md" 2> "$BUILD/logs/$M-carbon.log"
}

is_limited() {
  tail -c 4000 "$1" 2>/dev/null | grep -qiE "rate.?limit|usage limit|session limit|resource[_ -]?exhausted|too many requests|\b429\b|at capacity|overloaded|out of credits|unauthori[sz]ed|not authenticated|authentication required|not logged in"
}

case " $REVIEWERS " in *" carbon "*) setup_carbon_guard ;; esac

# Each reviewer's pid and start time go in PID_<reviewer> and START_<reviewer>: the bash that
# macOS ships (3.2) has no associative arrays.
STARTED=""
for r in $REVIEWERS; do
  case "$r" in codex|cursor|carbon) ;; *) echo "$M $r UNKNOWN reviewer (want codex, cursor or carbon)" >&2; continue ;; esac
  rm -f "$BUILD/reviews/$M-$r.md"
  printf -v "START_$r" '%s' "$(date +%s)"
  "run_$r" & printf -v "PID_$r" '%s' "$!"
  STARTED="$STARTED $r"
done

model_of() { case "$1" in codex) echo "$CODEX_REVIEW_MODEL";; cursor) echo "$CURSOR_REVIEW_MODEL";; carbon) echo "$CARBON_REVIEW_MODEL";; esac; }

any=0
for r in $STARTED; do
  pid_var="PID_$r"; start_var="START_$r"
  wait "${!pid_var}"; rc=$?
  e=$(( $(date +%s) - ${!start_var} )); dur=$(printf '%02d:%02d:%02d' $((e/3600)) $((e%3600/60)) $((e%60)))
  out="$BUILD/reviews/$M-$r.md"; log="$BUILD/logs/$M-$r.log"
  bytes=$(wc -c < "$out" 2>/dev/null || echo 0); bytes=$(echo "$bytes" | tr -d ' ')
  note=""
  if [ "$r" = carbon ]; then
    # Every change counts, tracked .agents/ files included; only the hooks.json this script wrote
    # is left out.
    changed=$(git -C "$CO" status --porcelain --untracked-files=all 2>/dev/null \
      | { if [ -n "$HOOKS_MADE" ]; then grep -vxF '?? .agents/hooks.json'; else cat; fi; } | wc -l | tr -d ' ')
    [ "$changed" != 0 ] && note=" WARNING carbon changed $changed file(s) in the review checkout"
    note="$note$CARBON_NOTE"
  fi
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    echo "$M $r:$(model_of "$r") TIMEOUT $(timeout_of "$r")s $dur log=$log$note"
  elif [ "$rc" -eq 0 ] && grep -qiE '^[[:space:]*#]*verdict' "$out" 2>/dev/null; then
    # A finished review has a verdict line, whatever its length: a clean one ("VERDICT: READY /
    # BIG: none / SMALL: none") is about 50 bytes, and a long refusal with no verdict is not one.
    echo "$M $r:$(model_of "$r") DONE $dur ${bytes} bytes file=$out$note"; any=1
  elif is_limited "$log" || is_limited "$out"; then
    echo "$M $r:$(model_of "$r") RATELIMITED $dur log=$log$note"
  elif [ "$rc" -ne 0 ]; then
    echo "$M $r:$(model_of "$r") FAIL rc=$rc $dur log=$log$note"
  else
    echo "$M $r:$(model_of "$r") EMPTY ${bytes} bytes, no verdict line $dur log=$log$note"
  fi
done
[ "$any" -eq 1 ]
