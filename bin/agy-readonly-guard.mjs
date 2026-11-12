// PreToolUse guard for an agy (Antigravity CLI) review run: reading is allowed; changing files,
// going online, running shell commands, starting subagents or calling MCP tools is not. review.sh
// copies it to a temp folder, points the review checkout's .agents/hooks.json at it, and passes a
// log path as the first argument.
//
// Hook contract (agy-customizations/docs/hooks.md): the tool call arrives on stdin as
// {"toolCall":{"name":..., "args":{...}}, ...}; we answer {"decision":"allow"|"deny", ...}.
import { appendFileSync } from 'node:fs';

const LOG = process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : '';

const WRITE_TOOL = /write|edit|replace|create|delete|remove|move|rename|patch|browser|read_url|search_web|web_|http|fetch|send|mcp/i;

// The only tools a review may use. Everything else is refused, including a tool name this guard
// has never seen: agy also has a "swarm" tool that starts workers, and a list of names to refuse
// would miss the next one (Carbon review, 2026-11-11).
const READ_TOOLS = new Set(['read_file', 'view_file', 'list_dir', 'list_directory', 'grep_search', 'find_by_name']);

function verdict(call) {
  const name = String(call?.name ?? '');
  // A Carbon review once started a subagent (invoke_subagent), read for 45 minutes and was
  // stopped before it wrote anything (2026-11-10). Whether the guard reaches a subagent's tools
  // is untested, so the reviewer reads for itself.
  if (/subagent|invoke_agent|swarm/i.test(name)) return { decision: 'deny', reason: 'Subagents are off in this review. Read the files yourself, in the order the brief gives.' };
  if (WRITE_TOOL.test(name)) return { decision: 'deny', reason: `tool ${name} is not allowed: this review is read-only and offline` };
  // agy headless mode ends the whole run, with no output, when a tool needs the "command"
  // permission and nothing granted it, and a hook's own "allow" does not grant it (tested
  // 2026-10-18). Every shell command is refused here with a reason the model can act on, and the
  // run carries on with its file tools.
  if (name === 'run_command') return { decision: 'deny', reason: 'Shell commands are off in this review. Use your file reading, listing and search tools instead; the diff and commit list are in the review packet.' };
  return READ_TOOLS.has(name)
    ? { decision: 'allow' }
    : { decision: 'deny', reason: `tool ${name} is not on the read-only list. Use read_file, view_file, list_dir, grep_search or find_by_name.` };
}

let input = '';
process.stdin.on('data', (d) => { input += d; }).on('end', () => {
  let payload = {};
  try { payload = JSON.parse(input); } catch { /* deny below */ }
  const out = payload.toolCall ? verdict(payload.toolCall) : { decision: 'deny', reason: 'unreadable tool call' };
  if (LOG) {
    try {
      appendFileSync(LOG, JSON.stringify({
        at: new Date().toISOString(),
        tool: payload.toolCall?.name,
        args: JSON.stringify(payload.toolCall?.args ?? {}).slice(0, 300),
        decision: out.decision,
      }) + '\n');
    } catch { /* logging must never block the decision */ }
  }
  process.stdout.write(JSON.stringify(out));
});
