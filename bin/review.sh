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
#   carbon  agy on Gemini 4 Carbon (Argon is no longer used: owner, 2026-11-10). A PreToolUse
#           guard in <checkout>/.agents/ refuses every write, web, MCP, subagent and shell tool
#           (agy's headless mode ends the run with no output when a shell command needs a
#           permission, and --dangerously-skip-permissions is refused by Claude Code's auto
#           mode). It reads with its own file tools and logs each tool call to
#           <build>/logs/<m>-carbon-guard.log. The checkout is a throwaway, and any file changed
#           anyway is reported on its line.
#
# Exit: 0 when at least one reviewer wrote a review, 1 when none did, 2 on bad usage.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=roster.sh
. "$HERE/roster.sh"
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
BRIEF="$BUILD/reviews/$M-brief.md"
[ -f "$BRIEF" ] || { echo "$M NOBRIEF $BRIEF does not exist" >&2; exit 2; }
git -C "$CO" rev-parse --git-dir >/dev/null 2>&1 || { echo "$M NOCHECKOUT $CO is not a git checkout" >&2; exit 2; }
mkdir -p "$BUILD/logs" "$BUILD/reviews"

win() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
CO_W="$(win "$CO")"; BUILD_W="$(win "$BUILD")"; BRIEF_W="$(win "$BRIEF")"
ASK="Read ${BRIEF_W} and follow it exactly. Reply with the review report only."

deadline() {  # deadline <seconds> <command...>
  local t="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout --kill-after=60 "$t" "$@"; else "$@"; fi
}

run_codex() {
  deadline "$TIMEOUT" codex exec - -s read-only -m "$CODEX_REVIEW_MODEL" \
    -c "model_reasoning_effort=\"$CODEX_REVIEW_EFFORT\"" -C "$CO_W" \
    -o "$(win "$BUILD/reviews/$M-codex.md")" < "$BRIEF" > "$BUILD/logs/$M-codex.log" 2>&1
}

run_cursor() {
  deadline "$TIMEOUT" "$CURSOR" -p --mode plan --model "$CURSOR_REVIEW_MODEL" --trust --workspace "$CO_W" \
    --add-dir "$BUILD_W" --output-format text "$ASK" \
    > "$BUILD/reviews/$M-cursor.md" 2> "$BUILD/logs/$M-cursor.log"
}

run_carbon() {
  # agy hands the hook command to Windows with its quotes intact, so no quotes and no spaces:
  # the guard is copied next to hooks.json (the hook's working directory) and the log path must
  # be space-free.
  local glog; glog="$(win "$BUILD/logs/$M-carbon-guard.log")"
  case "$glog" in *" "*) glog="guard.log" ;; esac
  mkdir -p "$CO/.agents"
  cp "$HERE/agy-readonly-guard.mjs" "$CO/.agents/guard.mjs"
  printf '{\n  "read-only-guard": {\n    "PreToolUse": [\n      {"matcher": "*", "hooks": [{"type": "command", "command": "node guard.mjs %s", "timeout": 10}]}\n    ]\n  }\n}\n' \
    "$glog" > "$CO/.agents/hooks.json"
  (cd "$CO" && deadline "$CARBON_TIMEOUT" "$AGY" -p "$ASK Shell commands are switched off for this review: use your file reading, listing and search tools." \
    --model "$CARBON_REVIEW_MODEL" --sandbox --add-dir "$BUILD_W" --print-timeout "${CARBON_TIMEOUT}s" \
    --output-format text) > "$BUILD/reviews/$M-carbon.md" 2> "$BUILD/logs/$M-carbon.log"
}

is_limited() {
  tail -c 4000 "$1" 2>/dev/null | grep -qiE "rate.?limit|usage limit|session limit|resource[_ -]?exhausted|quota|too many requests|\b429\b|\b401\b|\b403\b|at capacity|overloaded|out of credits|unauthori[sz]ed|not authenticated|authentication required|not logged in"
}

declare -A PID START
for r in $REVIEWERS; do
  case "$r" in codex|cursor|carbon) ;; *) echo "$M $r UNKNOWN reviewer (want codex, cursor or carbon)" >&2; continue ;; esac
  rm -f "$BUILD/reviews/$M-$r.md"
  START[$r]=$(date +%s)
  "run_$r" & PID[$r]=$!
done

model_of() { case "$1" in codex) echo "$CODEX_REVIEW_MODEL";; cursor) echo "$CURSOR_REVIEW_MODEL";; carbon) echo "$CARBON_REVIEW_MODEL";; esac; }

any=0
for r in $REVIEWERS; do
  [ -n "${PID[$r]:-}" ] || continue
  wait "${PID[$r]}"; rc=$?
  e=$(( $(date +%s) - START[$r] )); dur=$(printf '%02d:%02d:%02d' $((e/3600)) $((e%3600/60)) $((e%60)))
  out="$BUILD/reviews/$M-$r.md"; log="$BUILD/logs/$M-$r.log"
  bytes=$(wc -c < "$out" 2>/dev/null || echo 0); bytes=$(echo "$bytes" | tr -d ' ')
  note=""
  if [ "$r" = carbon ]; then
    changed=$(git -C "$CO" status --porcelain 2>/dev/null | grep -v ' \.agents/' | wc -l | tr -d ' ')
    [ "$changed" != 0 ] && note=" WARNING carbon changed $changed file(s) in the review checkout"
  fi
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    echo "$M $r:$(model_of "$r") TIMEOUT $(timeout_of "$r")s $dur log=$log$note"
  elif [ "$bytes" -gt 200 ] && [ "$rc" -eq 0 ]; then
    echo "$M $r:$(model_of "$r") DONE $dur ${bytes} bytes file=$out$note"; any=1
  elif is_limited "$log" || is_limited "$out"; then
    echo "$M $r:$(model_of "$r") RATELIMITED $dur log=$log$note"
  elif [ "$rc" -ne 0 ]; then
    echo "$M $r:$(model_of "$r") FAIL rc=$rc $dur log=$log$note"
  else
    echo "$M $r:$(model_of "$r") EMPTY ${bytes} bytes $dur log=$log$note"
  fi
done
[ "$any" -eq 1 ]
