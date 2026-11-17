#!/usr/bin/env bash
# Check every runner before a build, one line each. Nothing here edits a file.
#
#   preflight.sh          logins, versions, and that every roster model is listed
#   preflight.sh --live   also asks each reviewer model for one word, read-only (about 1-3 min)
#
# A runner that is down does not stop the build: the lead routes around it and writes it in
# status.md. Only the owner logs a runner in; never handle his credentials.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=roster.sh
. "$HERE/roster.sh"
# shellcheck source=deadline.sh
. "$HERE/deadline.sh"  # run_deadline: the checks below need no GNU timeout
LIVE=""; [ "${1:-}" = "--live" ] && LIVE=yes
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

listed() {  # listed <file> <model>...  -> names the models missing from the list
  local f="$1" miss=""; shift
  for m in "$@"; do grep -qE "(^|[[:space:]])$m([[:space:]]|$)" "$f" || miss="$miss $m"; done
  echo "$miss"
}

# Before the runner checks, so a missing timeout is not mistaken for anything a runner printed.
if command -v timeout >/dev/null 2>&1; then
  echo "timeout: available"
else
  echo "timeout: MISSING (not needed: these checks, dispatch.sh and review.sh use bin/deadline.sh)"
fi

# Claude Code
if command -v claude >/dev/null 2>&1; then
  echo "claude : ok, $(claude --version 2>/dev/null | head -1); workers run as subagents of this session"
else
  echo "claude : NOT on PATH"
fi

# Codex
if command -v codex >/dev/null 2>&1; then
  st="$(codex login status 2>&1 | head -1)"
  case "$st" in
    *"Logged in"*)
      line="codex  : ok, $(codex --version 2>/dev/null | head -1), $st; review model $CODEX_REVIEW_MODEL at $CODEX_REVIEW_EFFORT"
      # Codex has no command that lists models; the cache it keeps of them is the best check there is.
      cache="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
      if [ -f "$cache" ]; then
        rmiss=""; grep -qF "\"$CODEX_REVIEW_MODEL\"" "$cache" || rmiss=" $CODEX_REVIEW_MODEL"
        miss=""; for m in "$CODEX_WORKER_MODEL" "$CODEX_HARD_MODEL"; do grep -qF "\"$m\"" "$cache" || miss="$miss $m"; done
        [ -n "$rmiss" ] && line="$line; REVIEW MODEL NOT IN CODEX'S MODEL CACHE:$rmiss (the Codex reviewer may be unavailable; do not replace it with another model)"
        [ -n "$miss" ] && line="$line; WORKER MODEL NOT IN CODEX'S MODEL CACHE:$miss (skip that entry on its tier's list and tell the owner; never substitute)"
      else
        line="$line; models NOT CHECKED: Codex has no model cache yet"
      fi
      if [ -n "$LIVE" ]; then
        if echo "Reply with the single word READY." | run_deadline 300 codex exec - -s read-only -m "$CODEX_REVIEW_MODEL" \
             -c "model_reasoning_effort=\"low\"" --skip-git-repo-check -o "$T/codex.txt" >"$T/codex.log" 2>&1 \
           && grep -qi ready "$T/codex.txt"; then line="$line; answered"
        else line="$line; DID NOT ANSWER: $(tail -c 300 "$T/codex.log" | tr '\n' ' ')"; fi
      fi
      echo "$line" ;;
    *) echo "codex  : NOT LOGGED IN ($st). The owner runs: codex login" ;;
  esac
else
  echo "codex  : NOT on PATH"
fi

# cursor-agent (-e, not -x: Git Bash reads the executable bit as false on a .cmd)
if [ -e "$CURSOR" ]; then
  run_deadline 90 "$CURSOR" --list-models >"$T/cursor.txt" 2>&1; rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "cursor : NOT CHECKED, its model list did not come back within 90 s (not read as logged out); run preflight again"
  elif grep -qiE "authentication required|not logged in|login" "$T/cursor.txt" && ! grep -q " - " "$T/cursor.txt"; then
    if command -v cygpath >/dev/null 2>&1; then login="& '$(cygpath -w "$CURSOR")' login"   # PowerShell
    else login="'$CURSOR' login"; fi
    echo "cursor : LOGGED OUT. The owner runs: $login"
  else
    rmiss="$(listed "$T/cursor.txt" "$CURSOR_REVIEW_MODEL")"
    miss="$(listed "$T/cursor.txt" "$CURSOR_EASY_MODEL" "$CURSOR_OPUS_MODEL" "$CURSOR_FABLE_MODEL")"
    line="cursor : ok; review model $CURSOR_REVIEW_MODEL"
    [ -n "$rmiss" ] && line="$line; REVIEW MODEL NOT LISTED:$rmiss (the Cursor reviewer is unavailable; do not replace it with another model)"
    [ -n "$miss" ] && line="$line; WORKER MODEL NOT LISTED:$miss (skip that entry on its tier's list and tell the owner; never substitute)"
    if [ -n "$LIVE" ]; then
      if run_deadline 300 "$CURSOR" -p --mode ask --model "$CURSOR_REVIEW_MODEL" --trust --output-format text \
           "Reply with the single word READY." >"$T/cursor-live.txt" 2>&1 && grep -qi ready "$T/cursor-live.txt"; then
        line="$line; answered"
      else line="$line; DID NOT ANSWER: $(tail -c 300 "$T/cursor-live.txt" | tr '\n' ' ')"; fi
    fi
    echo "$line"
  fi
else
  echo "cursor : NOT FOUND at $CURSOR"
fi

# agy (Antigravity CLI)
if [ -e "$AGY" ]; then
  run_deadline 90 "$AGY" models >"$T/agy.txt" 2>&1; rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "agy    : NOT CHECKED, its model list did not come back within 90 s (not read as logged out); run preflight again"
  elif ! grep -qE "^(gemini|claude|gpt)" "$T/agy.txt"; then
    echo "agy    : NO MODEL LIST ($(tail -c 200 "$T/agy.txt" | tr '\n' ' ')). The owner opens agy once and signs in"
  else
    rmiss="$(listed "$T/agy.txt" "$CARBON_REVIEW_MODEL")"
    miss="$(listed "$T/agy.txt" "$AGY_OPUS_MODEL" "$AGY_CARBON_MODEL" "$AGY_EASY_MODEL")"
    line="agy    : ok, $(run_deadline 30 "$AGY" --version 2>/dev/null | head -1); review model $CARBON_REVIEW_MODEL"
    [ -n "$rmiss" ] && line="$line; REVIEW MODEL NOT LISTED:$rmiss (the Carbon reviewer is unavailable; do not replace it with another model)"
    [ -n "$miss" ] && line="$line; WORKER MODEL NOT LISTED:$miss (skip that entry on its tier's list and tell the owner; never substitute)"
    if [ -n "$LIVE" ]; then
      mkdir -p "$T/agyws" && (cd "$T/agyws" && run_deadline 300 "$AGY" -p "Reply with the single word READY. Do not use any tools." \
           --model "$CARBON_REVIEW_MODEL" --sandbox --print-timeout 240s --output-format text) >"$T/agy-live.txt" 2>&1
      if grep -qi ready "$T/agy-live.txt"; then line="$line; answered"
      else line="$line; DID NOT ANSWER: $(tail -c 300 "$T/agy-live.txt" | tr '\n' ' ')"; fi
    fi
    echo "$line"
  fi
else
  echo "agy    : NOT FOUND at $AGY"
fi

# Local models (Ollama, LM Studio, Lemonade): easy tasks only, and only when the owner turns them on.
if ! local_on; then
  echo "local  : off (the owner turns local workers on with LOCAL_WORKERS=on; easy tasks only)"
else
  # The harness drives every local server (LOCAL_HARNESS: codex, qwen or opencode).
  if ! local_harness_ok; then harness=""; hnote="LOCAL_HARNESS is '$LOCAL_HARNESS'; it must be codex, qwen or opencode"
  elif ! command -v "$LOCAL_HARNESS" >/dev/null 2>&1; then harness=""; hnote="$LOCAL_HARNESS (LOCAL_HARNESS) is not on PATH"
  else harness="$LOCAL_HARNESS $(run_deadline 30 "$LOCAL_HARNESS" --version 2>/dev/null | tail -1 | sed 's/^codex-cli //')"; fi
  for r in $LOCAL_RUNNERS; do
    m="$(worker_models "$r")"; u="$(local_url "$r")"
    if [ -z "$m" ]; then
      echo "$(printf '%-7s' "$r"): not used, no model named ($(printf '%s' "$r" | tr '[:lower:]' '[:upper:]')_MODEL)"
    elif [ -z "$harness" ]; then
      echo "$(printf '%-7s' "$r"): DOWN, $hnote"
    elif ! curl -s -m 5 "$u/models" >"$T/$r.json" 2>/dev/null; then
      echo "$(printf '%-7s' "$r"): DOWN, no server answers at $u (start it, or set $(printf '%s' "$r" | tr '[:lower:]' '[:upper:]')_URL)"
    elif ! grep -qF "\"$m\"" "$T/$r.json"; then
      echo "$(printf '%-7s' "$r"): MODEL NOT LISTED: $m is not served at $u (load or pull it; never substitute)"
    else
      ctx=""
      if [ "$r" = ollama ]; then  # Ollama reports the context of a loaded model; a harness's first request is 3-15k tokens
        ctx="$(curl -s -m 5 "${u%/v1}/api/ps" 2>/dev/null | tr ',' '\n' | awk -v n="\"name\":\"$m\"" '
          index($0, "\"name\":\"") { f = index($0, n) > 0 }
          f && /"context_length":/ { gsub(/[^0-9]/, ""); print; exit }')"
        if [ -z "$ctx" ]; then ctx="; context not known until the model is loaded"
        elif [ "$ctx" -lt 32768 ]; then ctx="; CONTEXT SMALL: $ctx tokens (a worker needs 32768 or more; set OLLAMA_CONTEXT_LENGTH)"
        else ctx="; context $ctx tokens"; fi
      fi
      echo "$(printf '%-7s' "$r"): ok, $m at $u$ctx; driven by $harness; easy tasks only"
    fi
  done
fi
