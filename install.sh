#!/usr/bin/env bash
# Make this skill available to Codex, Cursor and agy as well as Claude Code. The one real copy is
# ~/.claude/skills/build-with-agents: edit it there, never in another tool's folder.
#
#   Codex   ~/.codex/skills/build-with-agents          directory junction: an edit shows at once
#   Cursor  ~/.cursor/skills/build-with-agents         directory junction: an edit shows at once
#   agy     ~/.gemini/config/skills/build-with-agents  a COPY. agy skips linked folders and ignores
#           ~/.gemini/config/skills.json (both tested 2026-10-18), so run this again after an edit.
#
#   bash ~/.claude/skills/build-with-agents/install.sh            install, or refresh agy's copy
#   bash ~/.claude/skills/build-with-agents/install.sh --remove   take it out of those three tools
#
# Claude Code needs nothing: it reads ~/.claude/skills directly. The source folder is never
# deleted or changed by this script.

set -uo pipefail
NAME=build-with-agents
SRC="$HOME/.claude/skills/$NAME"
[ -f "$SRC/SKILL.md" ] || { echo "no skill at $SRC" >&2; exit 2; }

win() { cygpath -w "$1"; }
link_type() { powershell.exe -NoProfile -Command "(Get-Item -LiteralPath '$(win "$1")' -Force).LinkType" 2>/dev/null | tr -d '\r'; }
make_junction() { powershell.exe -NoProfile -Command "New-Item -ItemType Junction -Path '$(win "$1")' -Target '$(win "$SRC")' | Out-Null"; }
# Removes only the link itself. A recursive delete through a junction would empty the source.
drop_junction() { powershell.exe -NoProfile -Command "[System.IO.Directory]::Delete('$(win "$1")', \$false)"; }

remove_entry() {  # remove_entry <path>: a junction is unlinked, a real copy is deleted
  local p="$1"
  [ -e "$p" ] || return 0
  if [ "$(link_type "$p")" = "Junction" ]; then drop_junction "$p"
  else rm -rf -- "$p"; fi
}

MODE="${1:-install}"
for tool in codex cursor agy; do
  case "$tool" in
    codex)  dir="$HOME/.codex/skills" ;;
    cursor) dir="$HOME/.cursor/skills" ;;
    agy)    dir="$HOME/.gemini/config/skills" ;;
  esac
  dest="$dir/$NAME"
  if [ "$MODE" = "--remove" ]; then
    remove_entry "$dest"; echo "$tool: removed $dest"; continue
  fi
  if [ ! -d "$dir" ]; then echo "$tool: skipped, $dir does not exist (is $tool installed?)"; continue; fi
  if [ "$tool" = agy ]; then
    remove_entry "$dest"; cp -r "$SRC" "$dest" && rm -rf -- "$dest/.git" \
      && echo "agy: copied to $dest (rerun after editing the skill)"
  elif [ "$(link_type "$dest")" = "Junction" ]; then
    echo "$tool: already linked at $dest"
  else
    remove_entry "$dest"; make_junction "$dest" && echo "$tool: linked $dest -> $SRC"
  fi
done
