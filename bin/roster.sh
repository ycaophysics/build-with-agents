# The owner's roster: every model ID the build uses. Sourced by dispatch.sh, review.sh and preflight.sh.
# Change a model here AND in the roster table in ../SKILL.md, in the same edit. Never add a model
# the owner has not named, and never fall back to "auto".

# Where the runners live. cursor-agent and agy are not on Git Bash's PATH.
LOCAL_APPS="$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null)"
LOCAL_APPS="${LOCAL_APPS:-$HOME/AppData/Local}"
CURSOR="${CURSOR_AGENT:-$LOCAL_APPS/cursor-agent/cursor-agent.cmd}"
AGY="${AGY:-$LOCAL_APPS/agy/bin/agy.exe}"

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

# Workers (owner, 2026-11-12). Each fallback list uses one model per runner: a runner that is rate
# limited or LOW is marked down as a whole, so a second model on the same runner would never be
# tried. "Never astra" above is a reviewer rule; Astra may take hard tasks as the last fallback.
CLAUDE_WORKER_MODEL="claude-opus-5-5"            # Claude subagent (opus-high), effort high: hard and medium
CLAUDE_EASY_MODEL="claude-sonnet-5-5"            # Claude subagent for easy tasks, effort high
CLAUDE_STEPUP_MODEL="claude-fable-5-2"           # a hard task still blocked after its follow-up, effort high
CURSOR_FABLE_MODEL="claude-fable-5-2-high"       # that step-up when Claude is out
AGY_OPUS_MODEL="claude-opus-5-5-high"            # hard: 1st fallback, the same Opus 5.5 on the Antigravity plan
CURSOR_OPUS_MODEL="claude-opus-5-5-high"         # hard: 2nd fallback; medium: 3rd. Opus 5.5 on Cursor's plan
AGY_CARBON_MODEL="gemini-4-carbon-medium"        # medium: 1st fallback; hard: 3rd. High is too slow for work
CODEX_HARD_MODEL="gpt-6-astra"                   # hard: 4th fallback
CODEX_WORKER_MODEL="gpt-6.1-sol"                 # medium: 2nd fallback; last resort for any task
CODEX_WORKER_EFFORT="xhigh"                      # every codex worker; dispatch.sh passes it
CURSOR_EASY_MODEL="cursor-grok-4.6-high-fast"    # easy: 1st fallback
AGY_EASY_MODEL="gemini-4-hydrogen-high"   # easy: 2nd fallback; Hydrogen replaced Flash (owner, 2026-11-12)
