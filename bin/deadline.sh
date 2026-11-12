# run_deadline <seconds> <command...>: run a command, and stop it and everything it started when
# the deadline passes. Sourced by dispatch.sh and review.sh.
#
# Returns the command's own exit code, or 124 when the deadline stopped it. It returns only after
# the command has exited, so a caller that cleans up afterwards (dispatch.sh removes the task
# lock) never does so while a worker is still writing.
#
# GNU timeout is not used: on Windows it often stops only the wrapper and leaves agy, Node or
# Codex running. Here the command runs in the background, and at the deadline its whole process
# tree is killed: with taskkill under Git Bash (the Windows pid comes from /proc/<pid>/winpid;
# Git Bash needs taskkill's slashes doubled), and by process group elsewhere.

_deadline_msys_tree() {  # prints "<pid> <winpid>" for a Git Bash pid and every descendant
  # Git Bash processes do not carry their Windows parent, so taskkill //T alone misses the ones a
  # Git Bash child started (tested 2026-11-12). Their parents are read from Git Bash's own ps.
  ps 2>/dev/null | awk -v root="$1" '
    NR > 1 { o = ($1 ~ /^[0-9]+$/) ? 0 : 1; par[$(1+o)] = $(2+o); wp[$(1+o)] = $(4+o) }
    END {
      keep[root] = 1; grew = 1
      while (grew) { grew = 0; for (p in par) if (!(p in keep) && (par[p] in keep)) { keep[p] = 1; grew = 1 } }
      for (p in keep) if (p in wp) print p, wp[p]
    }'
}

_deadline_kill_tree() {  # _deadline_kill_tree <pid> <own-process-group: yes|no>
  local pid="$1" own_group="$2" p w
  if [ -r "/proc/$pid/winpid" ]; then
    # Every Git Bash process in the tree is listed first, then each is killed together with the
    # Windows programs it started (agy, Node, Codex), which taskkill //T does follow.
    _deadline_msys_tree "$pid" | while read -r p w; do
      [ -n "$w" ] && taskkill //PID "$w" //T //F >/dev/null 2>&1
      kill -KILL "$p" 2>/dev/null
    done
    kill -KILL "$pid" 2>/dev/null
  elif [ "$own_group" = yes ]; then
    kill -TERM -- "-$pid" 2>/dev/null
    sleep 5
    kill -KILL -- "-$pid" 2>/dev/null
  else
    pkill -KILL -P "$pid" 2>/dev/null
    kill -KILL "$pid" 2>/dev/null
  fi
}

run_deadline() {
  local secs="$1"; shift
  local own_group=no pid start
  # `<&0` keeps the caller's stdin (a pipe or a file): a background command would otherwise read
  # /dev/null.
  # Off Windows, setsid puts the command in its own process group, so the whole group can be
  # killed without killing this script.
  if [ ! -r /proc/self/winpid ] && command -v setsid >/dev/null 2>&1; then
    setsid "$@" <&0 & pid=$!; own_group=yes
  else
    "$@" <&0 & pid=$!
  fi
  start=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$secs" ]; then
      _deadline_kill_tree "$pid" "$own_group"
      # Wait for the child itself to be gone before returning.
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 1
  done
  wait "$pid"
}
