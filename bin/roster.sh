# The owner's roster: every model ID the build uses. Sourced by review.sh and preflight.sh.
# Change a model here AND in the roster table in ../SKILL.md, in the same edit. Never add a model
# the owner has not named, and never fall back to "auto".

# Where the runners live. On Windows cursor-agent and agy are not on Git Bash's PATH; they are
# under %LOCALAPPDATA%. On macOS and Linux they are on PATH, or in ~/.local/bin where their
# installers put them. CURSOR_AGENT and AGY override both.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    LOCAL_APPS="$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null)"
    LOCAL_APPS="${LOCAL_APPS:-$HOME/AppData/Local}"
    CURSOR="${CURSOR_AGENT:-$LOCAL_APPS/cursor-agent/cursor-agent.cmd}"
    AGY="${AGY:-$LOCAL_APPS/agy/bin/agy.exe}" ;;
  *)
    CURSOR="${CURSOR_AGENT:-$(command -v cursor-agent 2>/dev/null || echo "$HOME/.local/bin/cursor-agent")}"
    AGY="${AGY:-$(command -v agy 2>/dev/null || echo "$HOME/.local/bin/agy")}" ;;
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

# Workers.
CLAUDE_WORKER_MODEL="claude-opus-5-5"            # Claude subagent (opus-high), effort high
CLAUDE_EASY_MODEL="claude-sonnet-5-5"            # Claude subagent for easy tasks, effort high
AGY_OPUS_MODEL="claude-opus-5-5-high"            # the same Opus 5.5, on the Antigravity plan
CURSOR_OPUS_MODEL="claude-opus-5-thinking-high"  # Opus 5 on Cursor's key and endpoint
AGY_CARBON_MODEL="gemini-4-carbon-medium"        # medium tasks when Claude is out: first choice
CURSOR_MEDIUM_MODEL="gpt-5.6-sol-xhigh"          # medium: third choice, after Carbon and codex
CURSOR_EASY_MODEL="cursor-grok-4.6-high-fast"
AGY_EASY_MODEL="gemini-4-hydrogen-high"   # easy second fallback; Hydrogen replaced Flash (owner, 2026-11-12)
CODEX_WORKER_MODEL="gpt-6.1-sol"
