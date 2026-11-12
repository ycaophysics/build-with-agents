# Follow-up list

The follow-ups the Codex and Carbon reviews of commit 6aba0fb found (2026-11-11) are fixed, except
the one below.

## Paths and checks (`bin/roster.sh`)
- `roster.sh` does not check that `cursor-agent` or `agy` exist before falling back to the default
  folders.
