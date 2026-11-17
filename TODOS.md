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

## Local models (2026-11-17)
- LM Studio and Lemonade have never run a task end to end, with either harness. Only their
  preflight lines were seen (LM Studio answered without the model; Lemonade was not running). To
  be tested on their newer versions.
- Tested only on Windows, and only with Ollama. Not run on macOS or Linux.
- Each harness ran the three easy tasks once, and one or two of them again; that is too few to
  say how often a local model's PASS is wrong. Once, the model copied its commit line as `<noreply @localhost>`.
- Qwen Code was tested at 0.27.4 only. Its flags (`--auth-type`, `--openai-base-url`,
  `--add-dir`, `QWEN_HOME`) and the settings in the throwaway home (`memory.*`) may change.
- Preflight shows the loaded context for Ollama only; LM Studio and Lemonade do not report it the
  same way.
