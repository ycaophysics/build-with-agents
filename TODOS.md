# Follow-up list

The follow-ups the Codex and Carbon reviews of commit 6aba0fb found (2026-11-11) are fixed, except
the one below.

## From the Fable 5.2 and GPT-6 Astra reviews of the roster (2026-11-12)
- Allowance is tracked per runner, not per billing pool. Cursor bills its own models (Grok)
  separately from Claude and OpenAI models, so a single `cursor` LOW line can mark down models that
  still have allowance. Tracking pools would let one fallback list hold two Cursor models.
- Fallbacks share allowance with other seats: agy's Gemini quota carries the medium and easy
  fallbacks, the hard third fallback and the Carbon reviewer; Codex carries a worker, a reviewer and
  the emergency lead. Nothing reserves allowance for the reviewers or the lead.
- `dispatch.sh` accepts any model name, so the roster is a rule, not a check.
- `DISPATCH_TIMEOUT` (60 minutes) is untested for hard tasks on Astra at xhigh or Carbon medium.
- GPT-6.1 Terra at high now has the highest bug recall on MacroscopeBench; worth a side-by-side
  review trial before it takes any seat.
- SKILL.md section 7 and `templates/worker-rules.md` allow a serial pytest run when `-n` is
  rejected; the owner's global rule is to install pytest-xdist and never run a suite serially.

## Paths and checks (`bin/roster.sh`)
- `roster.sh` does not check that `cursor-agent` or `agy` exist before falling back to the default
  folders.
