# The owner's roster: every model ID the build uses. Sourced by review.sh and preflight.sh.
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

# Workers.
CLAUDE_WORKER_MODEL="claude-opus-5-5"            # Claude subagent (opus-high), effort high
CLAUDE_EASY_MODEL="claude-sonnet-5-5"            # Claude subagent for easy tasks, effort high
AGY_OPUS_MODEL="claude-opus-5-5-high"            # the same Opus 5.5, on the Antigravity plan
CURSOR_OPUS_MODEL="claude-opus-5-thinking-high"  # Opus 5 on Cursor's key and endpoint
AGY_CARBON_MODEL="gemini-4-carbon-medium"        # medium tasks when Claude is out: first choice
CURSOR_MEDIUM_MODEL="gpt-5.6-sol-xhigh"          # medium: third choice, after Carbon and codex
CURSOR_EASY_MODEL="cursor-grok-4.6-high-fast"
AGY_EASY_MODEL="gemini-3.8-flash-high"
CODEX_WORKER_MODEL="gpt-6.1-sol"
