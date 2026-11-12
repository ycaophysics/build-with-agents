#!/usr/bin/env bash
# Make this skill available to Codex, Cursor and agy as well as Claude Code. The one real copy is
# ~/.claude/skills/build-with-agents: edit it there, never in another tool's folder.
#
#   Codex   ~/.codex/skills/build-with-agents          a link: an edit shows at once
#   Cursor  ~/.cursor/skills/build-with-agents         a link: an edit shows at once
#   agy     ~/.gemini/config/skills/build-with-agents  a COPY. agy skips linked folders and ignores
#           ~/.gemini/config/skills.json (both tested 2026-10-18), so run this again after an edit.
#
# The link is a directory junction on Windows, where this runs from Git Bash, and a symbolic link
# on macOS and Linux.
#
#   bash ~/.claude/skills/build-with-agents/install.sh            install, or refresh agy's copy
#   bash ~/.claude/skills/build-with-agents/install.sh --remove   take it out of those three tools
#
# A tool whose own folder (~/.codex, ~/.cursor, ~/.gemini/config) is missing is skipped; when only
# its skills folder is missing, that folder is made. The exit code is 1 when any tool failed, even
# if a later one worked.
#
# Claude Code needs nothing: it reads ~/.claude/skills directly. The source folder is never
# deleted or changed by this script.

set -uo pipefail
NAME=build-with-agents
SRC="$HOME/.claude/skills/$NAME"
[ -f "$SRC/SKILL.md" ] || { echo "no skill at $SRC" >&2; exit 2; }

# probe <path> prints "none", "dir", "file", or "link <kind>". It looks at the path itself and
# never follows a link, so a broken link (its target was moved, and [ -e ] is false for it) still
# shows as a link.
# unlink_path <path> removes only the link itself, never what it points to: a recursive delete
# through a link would empty the source. It prints "ok" or "failed: <why>".
# make_link <path> links <path> to the source, and prints "ok" or "failed: <why>".
# LINK is what probe prints for the kind of link make_link makes.
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*)
  LINK="link Junction"
  win() { cygpath -w "$1"; }
  psq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"; }   # a PowerShell string literal
  pwsh() { powershell.exe -NoProfile -NonInteractive -Command "$1" 2>/dev/null | tr -d '\r'; }

  probe() {
    pwsh "\$p = $(psq "$(win "$1")"); try { \$a = [System.IO.File]::GetAttributes(\$p) } catch { 'none'; exit 0 }; if (\$a -band [System.IO.FileAttributes]::ReparsePoint) { 'link ' + (Get-Item -LiteralPath \$p -Force -ErrorAction SilentlyContinue).LinkType } elseif (\$a -band [System.IO.FileAttributes]::Directory) { 'dir' } else { 'file' }"
  }

  unlink_path() {
    pwsh "\$p = $(psq "$(win "$1")"); try { if ([System.IO.File]::GetAttributes(\$p) -band [System.IO.FileAttributes]::Directory) { [System.IO.Directory]::Delete(\$p, \$false) } else { [System.IO.File]::Delete(\$p) }; 'ok' } catch { 'failed: ' + \$_.Exception.Message }"
  }

  make_link() {
    pwsh "try { New-Item -ItemType Junction -Path $(psq "$(win "$1")") -Target $(psq "$(win "$SRC")") -ErrorAction Stop | Out-Null; 'ok' } catch { 'failed: ' + \$_.Exception.Message }"
  }
  ;;
*)
  LINK="link symlink"
  probe() {
    if [ -L "$1" ]; then echo "link symlink"
    elif [ -d "$1" ]; then echo dir
    elif [ -e "$1" ]; then echo file
    else echo none; fi
  }

  # rm without -r, on a path with no trailing slash, removes the link and not the folder it names.
  unlink_path() {
    local err
    if err="$(rm -f -- "$1" 2>&1)"; then echo ok; else echo "failed: $err"; fi
  }

  make_link() {
    local err
    if err="$(ln -s -- "$SRC" "$1" 2>&1)"; then echo ok; else echo "failed: $err"; fi
  }
  ;;
esac

remove_entry() {  # remove_entry <path>: a link is unlinked, a real copy is deleted; 1 if it is still there
  local p="$1" kind out
  kind="$(probe "$p")"
  case "$kind" in
    none) return 0 ;;
    link*) out="$(unlink_path "$p")"; [ "$out" = ok ] || echo "  could not unlink $p: $out" >&2 ;;
    *) rm -rf -- "$p" ;;
  esac
  [ "$(probe "$p")" = none ]
}

linked_here() {  # linked_here <path>: a link that reaches this skill's source
  [ "$(probe "$1")" = "$LINK" ] && [ "$1" -ef "$SRC" ]
}

MODE="${1:-install}"
FAILED=""
fail() { echo "$1: FAILED, $2" >&2; FAILED="$FAILED $1"; }

for tool in codex cursor agy; do
  case "$tool" in
    codex)  conf="$HOME/.codex" ;;
    cursor) conf="$HOME/.cursor" ;;
    agy)    conf="$HOME/.gemini/config" ;;
  esac
  dir="$conf/skills"
  dest="$dir/$NAME"
  # If $dir is itself a link to ~/.claude/skills, then $dest IS the source, and removing it would
  # delete the real skill (tested 2026-11-11). `-ef` is true when both names reach the same folder.
  # (A correct link at $dest also reaches the source, so only the parent folders are compared.)
  if [ "$dir" -ef "$(dirname "$SRC")" ]; then
    echo "$tool: skipped, $dir is the same folder as $(dirname "$SRC")"; continue
  fi
  if [ "$MODE" = "--remove" ]; then
    if [ "$(probe "$dest")" = none ]; then echo "$tool: nothing to remove at $dest"
    elif remove_entry "$dest"; then echo "$tool: removed $dest"
    else fail "$tool" "could not remove $dest"; fi
    continue
  fi
  if [ ! -d "$conf" ]; then echo "$tool: skipped, $conf does not exist (is $tool installed?)"; continue; fi
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" || { fail "$tool" "could not make $dir"; continue; }
    echo "$tool: made $dir"
  fi
  if [ "$tool" = agy ]; then
    remove_entry "$dest" || { fail "$tool" "could not remove the old $dest"; continue; }
    # -H copies the folder a linked source names, not the link. GNU cp -r would copy a link, and
    # removing .git through it would delete the real repository's history.
    if cp -RH "$SRC" "$dest" && [ ! -L "$dest" ] && rm -rf -- "$dest/.git" && [ -f "$dest/SKILL.md" ]; then
      echo "agy: copied to $dest (rerun after editing the skill)"
    else
      fail "$tool" "could not copy the skill to $dest"
    fi
  elif linked_here "$dest"; then
    echo "$tool: already linked at $dest"
  else
    remove_entry "$dest" || { fail "$tool" "could not remove the old $dest"; continue; }
    out="$(make_link "$dest")"
    if [ "$out" = ok ] && linked_here "$dest"; then
      echo "$tool: linked $dest -> $SRC"
    else
      fail "$tool" "could not link $dest -> $SRC ($out)"
    fi
  fi
done

if [ -n "$FAILED" ]; then
  echo "failed for:$FAILED" >&2
  exit 1
fi
