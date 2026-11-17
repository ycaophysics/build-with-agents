# The owner's roster: every model ID the build uses. Sourced by dispatch.sh, review.sh and preflight.sh.
# Change a model here AND in the roster table in ../SKILL.md, in the same edit. Never add a model
# the owner has not named, and never fall back to "auto".

# Where the runners live. On Windows cursor-agent and agy are usually not on Git Bash's PATH;
# their installers put them under %LOCALAPPDATA%. On macOS and Linux they are on PATH, or in
# ~/.local/bin. CURSOR_AGENT and AGY override every place below. Otherwise the first place that
# exists wins; when none does, the first one is kept, so preflight's "NOT FOUND at <path>" names
# where the installer would have put it.
_first_found() {  # _first_found <candidate>...  (an empty candidate is skipped)
  local c
  for c in "$@"; do [ -n "$c" ] && [ -e "$c" ] && { printf '%s' "$c"; return; }; done
  for c in "$@"; do [ -n "$c" ] && { printf '%s' "$c"; return; }; done
}
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    LOCAL_APPS="$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null)"
    LOCAL_APPS="${LOCAL_APPS:-$HOME/AppData/Local}"
    CURSOR="${CURSOR_AGENT:-$(_first_found "$LOCAL_APPS/cursor-agent/cursor-agent.cmd" \
      "$(command -v cursor-agent.cmd 2>/dev/null)" "$(command -v cursor-agent 2>/dev/null)")}"
    AGY="${AGY:-$(_first_found "$LOCAL_APPS/agy/bin/agy.exe" "$(command -v agy 2>/dev/null)")}" ;;
  *)
    CURSOR="${CURSOR_AGENT:-$(_first_found "$(command -v cursor-agent 2>/dev/null)" \
      "$HOME/.local/bin/cursor-agent" /opt/homebrew/bin/cursor-agent /usr/local/bin/cursor-agent)}"
    AGY="${AGY:-$(_first_found "$(command -v agy 2>/dev/null)" "$HOME/.local/bin/agy" \
      /opt/homebrew/bin/agy /usr/local/bin/agy)}" ;;
esac

# Reviewers, run at the same time on every milestone.
CODEX_REVIEW_MODEL="${CODEX_REVIEW_MODEL:-gpt-6.1-sol}"        # never astra (owner, 2026-10-03)
CODEX_REVIEW_EFFORT="${CODEX_REVIEW_EFFORT:-xhigh}"
CURSOR_REVIEW_MODEL="${CURSOR_REVIEW_MODEL:-grok-4.7-xhigh}"   # owner's Cursor review choice
CARBON_REVIEW_MODEL="${CARBON_REVIEW_MODEL:-gemini-4-carbon-high}"    # agy's reviewer; high for reviews, medium for work; Argon no longer used (owner, 2026-11-10)

# An override of "auto", or of a model with "astra" in its name (any case), is ignored and the
# default above is kept. Other overrides stand.
_never_a_reviewer() { case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in auto|*astra*) return 0 ;; esac; return 1; }
if _never_a_reviewer "$CODEX_REVIEW_MODEL"; then CODEX_REVIEW_MODEL="gpt-6.1-sol"; fi
if _never_a_reviewer "$CURSOR_REVIEW_MODEL"; then CURSOR_REVIEW_MODEL="grok-4.7-xhigh"; fi
if _never_a_reviewer "$CARBON_REVIEW_MODEL"; then CARBON_REVIEW_MODEL="gemini-4-carbon-high"; fi
if [ "$(printf '%s' "$CODEX_REVIEW_EFFORT" | tr '[:upper:]' '[:lower:]')" = auto ]; then CODEX_REVIEW_EFFORT="xhigh"; fi

# Workers (owner, 2026-11-12). No fallback list holds two models on the same usage.py line: a line
# that is rate limited or LOW is marked down as a whole, so a second model on it would never be
# tried (agy has two lines, agy-claude and agy-gemini). "Never astra" above is a reviewer rule;
# Astra is a hard task's last fallback.
CLAUDE_WORKER_MODEL="claude-opus-5-5"            # Claude subagent (opus-high), effort high: hard and medium
CLAUDE_EASY_MODEL="claude-sonnet-5-5"            # Claude subagent for easy tasks, effort high
CLAUDE_STEPUP_MODEL="claude-fable-5-2"           # a hard task still blocked after its follow-up, effort high
CURSOR_FABLE_MODEL="claude-fable-5-2-high"       # that step-up when Claude is out
AGY_OPUS_MODEL="claude-opus-5-5-high"            # hard: 1st fallback, the same Opus 5.5 on the Antigravity plan
CURSOR_OPUS_MODEL="claude-opus-5-5-high"         # hard: 2nd fallback; medium: 3rd. Opus 5.5 on Cursor's plan
AGY_CARBON_MODEL="gemini-4-carbon-medium"        # medium: 1st fallback; hard: 3rd. High is too slow for work
CODEX_HARD_MODEL="gpt-6-astra"                   # hard: 4th fallback
CODEX_WORKER_MODEL="gpt-6.1-sol"                 # medium: 2nd fallback; easy: 3rd
CODEX_WORKER_EFFORT="xhigh"                      # every codex worker; dispatch.sh passes it
CURSOR_EASY_MODEL="cursor-grok-4.6-high-fast"    # easy: 1st fallback
AGY_EASY_MODEL="gemini-4-hydrogen-high"   # easy: 2nd fallback; Hydrogen replaced Flash (owner, 2026-11-12)

# Local models: Ollama, LM Studio and Lemonade, each driven by a harness (LOCAL_HARNESS): Codex CLI
# against the server's OpenAI-compatible Responses endpoint, or Qwen Code against its Chat
# Completions endpoint. Off unless the owner turns them on (LOCAL_WORKERS=on), and only for easy
# tasks: dispatch.sh refuses a local runner for a brief whose tier is not easy. The owner names
# each model; a runner with no model set is left out. Each setting comes from the environment
# first, then from local.env next to SKILL.md (git ignores it), then the default.
ROSTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_local_env() {  # _local_env KEY -> its value in local.env (UTF-8, or the UTF-16 PowerShell writes)
  local f="$ROSTER_DIR/../local.env"
  [ -f "$f" ] || return 0
  tr -d '\000\r' < "$f" | LC_ALL=C sed '1s/^[^A-Za-z#]*//' \
    | grep -E "^[[:space:]]*$1[[:space:]]*=" | tail -1 \
    | sed -E "s/^[^=]*=[[:space:]]*//; s/[[:space:]]+$//; s/^[\"']//; s/[\"']$//"
}
_setting() {  # _setting KEY DEFAULT
  local v; eval "v=\${$1:-}"
  [ -n "$v" ] || v="$(_local_env "$1")"
  printf '%s' "${v:-$2}"
}
LOCAL_WORKERS="$(_setting LOCAL_WORKERS off)"
LOCAL_HARNESS="$(_setting LOCAL_HARNESS codex | tr '[:upper:]' '[:lower:]')"  # codex or qwen, for every server
OLLAMA_MODEL="$(_setting OLLAMA_MODEL "")"        # for example qwen3.8:27b
LMSTUDIO_MODEL="$(_setting LMSTUDIO_MODEL "")"
LEMONADE_MODEL="$(_setting LEMONADE_MODEL "")"
OLLAMA_URL="$(_setting OLLAMA_URL http://localhost:11434/v1)"     # Ollama's default port
LMSTUDIO_URL="$(_setting LMSTUDIO_URL http://localhost:1234/v1)"  # LM Studio's default port
LEMONADE_URL="$(_setting LEMONADE_URL http://localhost:13305/api/v1)"  # Lemonade's default; check with: lemonade status
LOCAL_RUNNERS="ollama lmstudio lemonade"          # the order a task tries them in
local_on() { case "$(printf '%s' "$LOCAL_WORKERS" | tr '[:upper:]' '[:lower:]')" in on|yes|true|1) return 0 ;; esac; return 1; }
local_harness_ok() { case "$LOCAL_HARNESS" in codex|qwen) return 0 ;; esac; return 1; }
local_url() {  # local_url <ollama|lmstudio|lemonade>
  case "$1" in ollama) echo "$OLLAMA_URL" ;; lmstudio) echo "$LMSTUDIO_URL" ;; lemonade) echo "$LEMONADE_URL" ;; esac
}
local_up() {  # local_up <runner>: its server answers and lists the model the owner named
  local m; m="$(worker_models "$1")"; [ -n "$m" ] || return 1
  curl -s -m 5 "$(local_url "$1")/models" 2>/dev/null | grep -qF "\"$m\""
}

# The worker models each runner may be given. dispatch.sh refuses any other (NOTINROSTER), so the
# roster is checked, not only written down. Built from the names above: change a model there.
worker_models() {  # worker_models <claude|agy|cursor|codex|ollama|lmstudio|lemonade>
  case "$1" in
    claude) echo "$CLAUDE_WORKER_MODEL $CLAUDE_EASY_MODEL $CLAUDE_STEPUP_MODEL" ;;
    agy)    echo "$AGY_OPUS_MODEL $AGY_CARBON_MODEL $AGY_EASY_MODEL" ;;
    cursor) echo "$CURSOR_OPUS_MODEL $CURSOR_FABLE_MODEL $CURSOR_EASY_MODEL" ;;
    codex)  echo "$CODEX_HARD_MODEL $CODEX_WORKER_MODEL" ;;
    ollama)   echo "$OLLAMA_MODEL" ;;
    lmstudio) echo "$LMSTUDIO_MODEL" ;;
    lemonade) echo "$LEMONADE_MODEL" ;;
  esac
}
