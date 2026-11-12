# Build with agents

A Claude Code skill that runs an implementation build from a plan. The session you start is the lead. Workers write the code in a git worktree, and the lead does not write the feature code itself.

Claude subagents do the work by default. When Claude is out, or when you have allowed outside workers, the lead can send a task to Cursor, Antigravity agy (Opus, Gemini 4 Carbon, or Gemini 4 Hydrogen), or Codex. It checks how much allowance each runner has left and skips one that is nearly out.

At the end of each milestone, Codex, Cursor, and agy Gemini 4 Carbon review the change at the same time. Those reviews are read-only.

The build runs from setup through the final report without waiting for an answer. Saying "stop" or "wait" in the conversation is what pauses it.

Start one with a plan file, or paste the plan:

```
/build-with-agents path/to/plan.md
```

Pick up a build that stopped:

```
/build-with-agents resume <build folder>
```

This skill builds. If you only want a plan or a prompt written down, it will hand the prompt back and stop.

## Install

The install script is for Windows. Run it from Git Bash. It uses directory junctions, and it will not change the folder it is installing from.

Claude Code reads `~/.claude/skills/build-with-agents` on its own. Clone the repo to that path:

```
git clone https://github.com/ycaophysics/build-with-agents.git ~/.claude/skills/build-with-agents
```

Codex, Cursor, and agy need the installer:

```
bash ~/.claude/skills/build-with-agents/install.sh
```

Codex gets a junction at `~/.codex/skills/build-with-agents`, and Cursor gets one at `~/.cursor/skills/build-with-agents`. An edit in the Claude Code folder shows up in those two immediately. agy skips linked folders, so the script copies the skill to `~/.gemini/config/skills/build-with-agents`. After you edit the skill, run the installer again or agy keeps the old copy.

A tool that is not installed is skipped. If the tool is installed and only its `skills` folder is missing, the script creates that folder. Edit the skill in `~/.claude/skills/build-with-agents`, not in the other tools' folders.

To remove it from Codex, Cursor, and agy, and leave the Claude Code copy where it is:

```
bash ~/.claude/skills/build-with-agents/install.sh --remove
```

## Sign-in

You log each runner in yourself: `codex login`, `cursor-agent login`, and opening `agy` once. The skill does not handle those credentials.

Reviews need no extra permission. Outside workers do. cursor-agent, agy, codex, and `claude -p` editing files on their own are refused by Claude Code's auto mode unless you allow `bin/dispatch.sh` in `~/.claude/settings.json` or the repo's `.claude/settings*.json`. Without that rule, every task stays with a Claude subagent.

The full runbook, including the model roster, is `SKILL.md`.
