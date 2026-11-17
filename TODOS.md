# Follow-up list

The follow-ups the Codex and Carbon reviews of commit 6aba0fb found (2026-11-11) are fixed, except
the one below.

## From the Fable 5.2 and GPT-6 Astra reviews of the roster (2026-11-12)
- Allowance is tracked per runner, not per billing pool. Cursor bills its own models (Grok)
  separately from Claude and OpenAI models, so a single `cursor` LOW line can mark down models that
  still have allowance. Tracking pools would let one fallback list hold two Cursor models. Blocked
  on quota-cli: 0.4.0 reports one `Plan` window for Cursor, with no split by pool (checked
  2026-11-17).
- `DISPATCH_TIMEOUT` (60 minutes) is untested for hard tasks on Astra at xhigh or Carbon medium.
- GPT-6.1 Terra at high now has the highest bug recall on MacroscopeBench; worth a side-by-side
  review trial before it takes any seat.
