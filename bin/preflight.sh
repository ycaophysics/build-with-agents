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
LIVE=""; [ "${1:-}" = "--live" ] && LIVE=yes
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

listed() {  # listed <file> <model>...  -> names the models missing from the list
  local f="$1" miss=""; shift
  for m in "$@"; do grep -qE "(^|[[:space:]])$m([[:space:]]|$)" "$f" || miss="$miss $m"; done
  echo "$miss"
}

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
      if [ -n "$LIVE" ]; then
        if echo "Reply with the single word READY." | timeout 300 codex exec - -s read-only -m "$CODEX_REVIEW_MODEL" \
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
  timeout 90 "$CURSOR" --list-models >"$T/cursor.txt" 2>&1
  if grep -qiE "authentication required|not logged in|login" "$T/cursor.txt" && ! grep -q " - " "$T/cursor.txt"; then
    echo "cursor : LOGGED OUT. The owner runs: & '$(cygpath -w "$CURSOR")' login"
  else
    miss="$(listed "$T/cursor.txt" "$CURSOR_REVIEW_MODEL" "$CURSOR_EASY_MODEL" "$CURSOR_MEDIUM_MODEL" "$CURSOR_OPUS_MODEL")"
    line="cursor : ok; review model $CURSOR_REVIEW_MODEL"
    [ -n "$miss" ] && line="$line; NOT LISTED:$miss (route that seat to its next runner and tell the owner; never substitute)"
    if [ -n "$LIVE" ]; then
      if timeout 300 "$CURSOR" -p --mode ask --model "$CURSOR_REVIEW_MODEL" --trust --output-format text \
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
  timeout 90 "$AGY" models >"$T/agy.txt" 2>&1
  if ! grep -qE "^(gemini|claude|gpt)" "$T/agy.txt"; then
    echo "agy    : NO MODEL LIST ($(tail -c 200 "$T/agy.txt" | tr '\n' ' ')). The owner opens agy once and signs in"
  else
    miss="$(listed "$T/agy.txt" "$CARBON_REVIEW_MODEL" "$AGY_OPUS_MODEL" "$AGY_CARBON_MODEL" "$AGY_EASY_MODEL")"
    line="agy    : ok, $("$AGY" --version 2>/dev/null | head -1); review model $CARBON_REVIEW_MODEL"
    [ -n "$miss" ] && line="$line; NOT LISTED:$miss (route that seat to its next runner and tell the owner; never substitute)"
    if [ -n "$LIVE" ]; then
      mkdir -p "$T/agyws" && (cd "$T/agyws" && timeout 300 "$AGY" -p "Reply with the single word READY. Do not use any tools." \
           --model "$CARBON_REVIEW_MODEL" --sandbox --print-timeout 240s --output-format text) >"$T/agy-live.txt" 2>&1
      if grep -qi ready "$T/agy-live.txt"; then line="$line; answered"
      else line="$line; DID NOT ANSWER: $(tail -c 300 "$T/agy-live.txt" | tr '\n' ' ')"; fi
    fi
    echo "$line"
  fi
else
  echo "agy    : NOT FOUND at $AGY"
fi

command -v timeout >/dev/null 2>&1 && echo "timeout: available" || echo "timeout: MISSING - runners will have no deadline"
