#!/usr/bin/env bash
# Hand one build task to one outside worker and print ONE line, so the lead's context never
# holds a worker transcript. Claude subagents do not go through here: the lead starts them with
# its own Agent tool. This is for cursor-agent, agy, codex, and `claude -p` when the lead is
# not Claude Code. It also runs the local models (Ollama, LM Studio, Lemonade) through Codex CLI
# Qwen Code or OpenCode (LOCAL_HARNESS in roster.sh), when the owner has turned them on, and only
# for an easy task.
#
#   dispatch.sh <task> <runner> <model> <brief> <worktree> <build-dir>
#     runner: claude | agy | cursor | codex | ollama | lmstudio | lemonade
#
#   dispatch.sh E3 cursor cursor-grok-4.6-high-fast  <build>/briefs/E3.md  <worktree>  <build>
#   dispatch.sh D1 agy    claude-opus-5-5-high       <build>/briefs/D1.md  <worktree>  <build>
#   dispatch.sh E4 ollama qwen3.8:27b                <build>/briefs/E4.md  <worktree>  <build>
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
#   2   usage, missing file, the task is already running (lock), a model that is not one of this
#       runner's worker models in roster.sh (NOTINROSTER), or a runner that is not installed
#       (NORUNNER; for a local runner, also a server that does not answer or does not list the
#       model, or a harness that is not installed or not codex, qwen or opencode). A local runner also
#       refuses while local workers are off (LOCALOFF), for a brief whose "Tier:" line is not
#       easy (NOTEASY), and while the same server is running another task of this build
#       (LOCALBUSY). Nothing was started: correct the call, or take the next entry on the list.
#
# These runners edit files unattended. Claude Code's auto mode refuses to start one ("Create
# Unsafe Agents") unless the owner has allowed this script with a permission rule. A refusal is
# not a failure to work around: give the task to a Claude subagent instead.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=roster.sh
. "$HERE/roster.sh"   # CURSOR and AGY (where those runners live), CODEX_WORKER_EFFORT
# shellcheck source=deadline.sh
. "$HERE/deadline.sh"  # run_deadline: stops the whole process tree at the deadline
TIMEOUT="${DISPATCH_TIMEOUT:-3600}"
CLAUDE_EFFORT="${DISPATCH_EFFORT:-high}"

if [ "$#" -ne 6 ]; then
  echo "usage: dispatch.sh <task> <claude|agy|cursor|codex|ollama|lmstudio|lemonade> <model> <brief> <worktree> <build-dir>" >&2
  exit 2
fi
TASK="$1"; RUNNER="$2"; MODEL="$3"; BRIEF="$4"; WT="$5"; BUILD="$6"

case "$RUNNER" in claude|agy|cursor|codex|ollama|lmstudio|lemonade) ;; *)
  echo "$TASK - unknown runner '$RUNNER' (want claude, agy, cursor, codex, ollama, lmstudio or lemonade)" >&2; exit 2 ;;
esac
LOCAL=""; case "$RUNNER" in ollama|lmstudio|lemonade) LOCAL=yes ;; esac
if [ -n "$LOCAL" ] && ! local_on; then
  echo "$TASK $RUNNER LOCALOFF local workers are off; only the owner turns them on (LOCAL_WORKERS=on)" >&2; exit 2
fi
ALLOWED="$(worker_models "$RUNNER")"
if [ -n "$LOCAL" ] && [ -z "$ALLOWED" ]; then
  echo "$TASK $RUNNER NOTINROSTER no $RUNNER model is set; the owner names one ($(printf '%s' "$RUNNER" | tr '[:lower:]' '[:upper:]')_MODEL in local.env)" >&2; exit 2
fi
case " $ALLOWED " in *" $MODEL "*) ;; *)
  echo "$TASK $RUNNER NOTINROSTER '$MODEL' is not on the roster as a worker model for $RUNNER (roster.sh); allowed: $ALLOWED" >&2
  exit 2 ;;
esac
[ -f "$BRIEF" ] || { echo "$TASK $RUNNER NOBRIEF $BRIEF does not exist" >&2; exit 2; }
if [ -n "$LOCAL" ] && ! grep -qiE '^Tier:[[:space:]]*easy([[:space:]]|$)' "$BRIEF"; then
  echo "$TASK $RUNNER NOTEASY local models take only easy tasks, and the brief has no 'Tier: easy' line" >&2; exit 2
fi
case "$RUNNER" in
  claude|codex) command -v "$RUNNER" >/dev/null 2>&1 || { echo "$TASK $RUNNER NORUNNER $RUNNER is not on PATH" >&2; exit 2; } ;;
  cursor) [ -e "$CURSOR" ] || { echo "$TASK $RUNNER NORUNNER cursor-agent not found at $CURSOR (set CURSOR_AGENT)" >&2; exit 2; } ;;
  agy)    [ -e "$AGY" ]    || { echo "$TASK $RUNNER NORUNNER agy not found at $AGY (set AGY)" >&2; exit 2; } ;;
  *)
    local_harness_ok || { echo "$TASK $RUNNER NORUNNER LOCAL_HARNESS is '$LOCAL_HARNESS'; it must be codex, qwen or opencode" >&2; exit 2; }
    command -v "$LOCAL_HARNESS" >/dev/null 2>&1 || { echo "$TASK $RUNNER NORUNNER $LOCAL_HARNESS, which drives the local models (LOCAL_HARNESS), is not on PATH" >&2; exit 2; }
    local_up "$RUNNER" || { echo "$TASK $RUNNER NORUNNER $(local_url "$RUNNER") does not answer, or does not list $MODEL" >&2; exit 2; } ;;
esac
git -C "$WT" rev-parse --git-dir >/dev/null 2>&1 || { echo "$TASK $RUNNER NOWORKTREE $WT is not a git checkout" >&2; exit 2; }

mkdir -p "$BUILD/logs" "$BUILD/reports"

# One task, one worker. Two dispatches of the same task would edit the same files.
LOCK="$BUILD/logs/$TASK.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "$TASK $RUNNER LOCKED already dispatched (remove $LOCK if that is stale)" >&2
  exit 2
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
# One local task per server: a second one would share the same model and memory.
if [ -n "$LOCAL" ]; then
  SLOCK="$BUILD/logs/local-$RUNNER.lock"
  if ! mkdir "$SLOCK" 2>/dev/null; then
    echo "$TASK $RUNNER LOCALBUSY $RUNNER is running another task of this build (remove $SLOCK if that is stale)" >&2
    exit 2
  fi
  trap 'rmdir "$LOCK" "$SLOCK" 2>/dev/null' EXIT
fi

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
# A local model does not know its own name, and its harness tells it it is Codex, Qwen or
# OpenCode: left alone, its commits named gpt-6.1-sol, gpt-5.5-codex or "Qwen" (tested 2026-11-17).
if [ -n "$LOCAL" ]; then
  PROMPT="$PROMPT
The model doing this task is ${MODEL}, running on this machine; your harness's name for you is not it. End every commit message with exactly this line: Co-Authored-By: ${MODEL} <noreply@localhost>"
fi

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
    # that edits, runs tests and writes its report needs full access. The effort is set here, not
    # left to the owner's ~/.codex/config.toml (Codex's own default for gpt-6.1-sol is low).
    printf '%s' "$PROMPT" | run_with_deadline codex exec - -m "$MODEL" -s danger-full-access \
      -c "model_reasoning_effort=\"$CODEX_WORKER_EFFORT\"" -C "$WT_W" -o "$(runner_path "$BUILD/logs/$TASK-$STAMP.last.md")" >"$LOG" 2>&1; rc=$? ;;
  ollama|lmstudio|lemonade)
    # Each harness runs with a home of its own, never the owner's: the owner's ~/.codex (skills,
    # MCP servers, global instructions) made a 137,599-token request that no small model's
    # context holds, and the owner's ~/.qwen adds a memory recall and a memory extractor to every
    # run (tested 2026-11-17). The repo's AGENTS.md (and QWEN.md) still apply.
    if [ "$LOCAL_HARNESS" = qwen ]; then
      # Qwen Code against the server's Chat Completions endpoint. Its home holds only settings
      # that keep it from reporting usage or writing memories. The key is a placeholder, so a
      # real OPENAI_API_KEY in the environment is never sent to the local server. --add-dir lets
      # its file tools write the report and verdict outside the worktree.
      LHOME="$BUILD/logs/$TASK-$STAMP.qwen-home"; mkdir -p "$LHOME"
      printf '%s\n' '{"privacy": {"usageStatisticsEnabled": false}, "telemetry": {"enabled": false, "logPrompts": false},' \
        ' "memory": {"enableManagedAutoMemory": false, "enableManagedAutoDream": false, "enableAutoSkill": false}}' > "$LHOME/settings.json"
      (cd "$WT" && printf '%s' "$PROMPT" | QWEN_HOME="$(runner_path "$LHOME")" QWEN_CODE_SUPPRESS_YOLO_WARNING=1 \
        run_with_deadline qwen --auth-type openai --openai-base-url "$(local_url "$RUNNER")" --openai-api-key local \
        -m "$MODEL" --yolo --add-dir "$BUILD_W" --chat-recording false -o text) >"$LOG" 2>&1; rc=$?
    elif [ "$LOCAL_HARNESS" = opencode ]; then
      # OpenCode against the server's Chat Completions endpoint. Config, data and cache live in
      # this folder, never the owner's ~/.config/opencode. A repo opencode.json is not loaded, and
      # this config is applied last, so the repo cannot point the run at another provider. Web
      # search and web fetch are denied. The model list is the copy bundled with the release
      # (checked on 1.19.6, 2026-11-17). --auto approves tool calls; external_directory is allowed
      # so the report and verdict, which sit outside the worktree, can be written.
      LHOME="$BUILD/logs/$TASK-$STAMP.opencode-home"
      mkdir -p "$LHOME/config/opencode" "$LHOME/data" "$LHOME/state" "$LHOME/cache"
      mid=$(printf '%s' "$MODEL" | sed 's/\\/\\\\/g; s/"/\\"/g')
      url=$(printf '%s' "$(local_url "$RUNNER")" | sed 's/\\/\\\\/g; s/"/\\"/g')
      CFG="$LHOME/config/opencode/opencode.json"
      cat > "$CFG" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "share": "disabled",
  "model": "localrt/${mid}",
  "small_model": "localrt/${mid}",
  "enabled_providers": ["localrt"],
  "provider": {
    "localrt": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "${RUNNER}",
      "options": { "baseURL": "${url}", "apiKey": "local" },
      "models": { "${mid}": { "name": "${mid}" } }
    }
  },
  "permission": {
    "edit": "allow",
    "bash": "allow",
    "read": "allow",
    "external_directory": "allow",
    "websearch": "deny",
    "webfetch": "deny"
  }
}
EOF
      (cd "$WT" && printf '%s' "$PROMPT" | XDG_CONFIG_HOME="$(runner_path "$LHOME/config")" \
        XDG_DATA_HOME="$(runner_path "$LHOME/data")" XDG_STATE_HOME="$(runner_path "$LHOME/state")" \
        XDG_CACHE_HOME="$(runner_path "$LHOME/cache")" OPENCODE_DISABLE_MODELS_FETCH=1 \
        OPENCODE_DISABLE_AUTOUPDATE=1 OPENCODE_DISABLE_PROJECT_CONFIG=1 \
        OPENCODE_DISABLE_DEFAULT_PLUGINS=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
        OPENCODE_DISABLE_CLAUDE_CODE=1 OPENCODE_DISABLE_LSP_DOWNLOAD=1 \
        OPENCODE_CONFIG_CONTENT="$(cat "$CFG")" \
        run_with_deadline opencode run --pure --auto --dir "$WT_W" --model "localrt/$MODEL") >"$LOG" 2>&1; rc=$?
    else
      # Codex against the server's Responses endpoint. Plugins are off: a fresh Codex home
      # otherwise clones the plugin catalog on every run.
      LHOME="$BUILD/logs/$TASK-$STAMP.codex-home"; mkdir -p "$LHOME"
      printf '%s' "$PROMPT" | CODEX_HOME="$(runner_path "$LHOME")" run_with_deadline codex exec - -m "$MODEL" \
        -c "model_providers.localrt.name=\"$RUNNER\"" -c "model_providers.localrt.base_url=\"$(local_url "$RUNNER")\"" \
        -c 'model_providers.localrt.wire_api="responses"' -c 'model_provider="localrt"' \
        --disable plugins --disable remote_plugin -s danger-full-access -C "$WT_W" -o "$(runner_path "$BUILD/logs/$TASK-$STAMP.last.md")" >"$LOG" 2>&1; rc=$?
    fi ;;
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

# A worker that writes the verdict from Windows PowerShell leaves a byte-order mark (UTF-8) or a
# UTF-16 file (seen 2026-11-17): drop the NUL bytes and anything before the first letter.
v="$(tr -d '\000[:space:]' < "$VERDICT" | LC_ALL=C sed 's/^[^A-Za-z]*//' | tr '[:lower:]' '[:upper:]')"
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
