// PreToolUse guard for an agy (Antigravity CLI) review run: reading is allowed; changing files,
// going online, starting subagents or calling MCP tools is not. review.sh installs it into the throwaway review
// checkout as .agents/hooks.json and passes a log path as the first argument.
//
// Hook contract (agy-customizations/docs/hooks.md): the tool call arrives on stdin as
// {"toolCall":{"name":..., "args":{...}}, ...}; we answer {"decision":"allow"|"deny", ...}.
// With --allow-read-commands, a read-only shell command is allowed and carries a one-off
// permissionOverrides grant for that exact line; every other command is refused.
import { appendFileSync } from 'node:fs';

const LOG = process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : '';
const ALLOW_READ_COMMANDS = process.argv.includes('--allow-read-commands');

const READ_PROGRAMS = new Set([
  'git', 'rg', 'grep', 'findstr', 'ls', 'dir', 'cat', 'type', 'head', 'tail', 'wc', 'find', 'echo',
  'sort', 'uniq', 'tree', 'more', 'cd', 'pwd', 'diff',
  'get-content', 'gc', 'get-childitem', 'gci', 'select-string', 'sls', 'measure-object',
  'sort-object', 'select-object', 'where-object', 'format-table', 'format-list', 'out-string',
  'get-item', 'test-path', 'resolve-path', 'split-path', 'set-location', 'get-location',
  'foreach-object', '%', '?', 'select', 'where',
]);
const GIT_READ = new Set([
  'log', 'show', 'ls-files', 'blame', 'diff', 'status', 'rev-parse', 'cat-file', 'ls-tree', 'grep',
  'shortlog', 'rev-list', 'describe', 'branch', 'merge-base',
]);
const WRITE_TOOL = /write|edit|replace|create|delete|remove|move|rename|patch|browser|read_url|search_web|web_|http|fetch|send|mcp/i;
const WRITE_LINE = /(^|[^>])>{1,2}(?!&)|\bout-file\b|\bset-content\b|\badd-content\b|\bremove-item\b|\bnew-item\b|\bcopy-item\b|\bmove-item\b|\brename-item\b|\bdel\b|\brm\b|\bmv\b|\bcp\b|\bcurl\b|\bwget\b|invoke-webrequest|invoke-restmethod|-delete\b|-exec\b|\btee\b/i;

function verdict(call) {
  const name = String(call?.name ?? '');
  // A Carbon review once started a subagent (invoke_subagent), read for 45 minutes and was
  // stopped before it wrote anything (2026-11-10). Whether the guard reaches a subagent's tools
  // is untested, so the reviewer reads for itself.
  if (/subagent|invoke_agent/i.test(name)) return { decision: 'deny', reason: 'Subagents are off in this review. Read the files yourself, in the order the brief gives.' };
  if (WRITE_TOOL.test(name)) return { decision: 'deny', reason: `tool ${name} is not allowed: this review is read-only and offline` };
  if (name !== 'run_command') return { decision: 'allow' };
  // agy headless mode ends the whole run, with no output, when a tool needs the "command"
  // permission and nothing granted it. A hook's own "allow" does not grant it (tested
  // 2026-10-18), so unless the caller passes --allow-read-commands (only useful when the run
  // has --dangerously-skip-permissions), every shell command is refused here with a reason the
  // model can act on, and the run carries on with its file tools.
  if (!ALLOW_READ_COMMANDS) return { decision: 'deny', reason: 'Shell commands are off in this review. Use your file reading, listing and search tools instead; the diff and commit list are in the review packet.' };
  const line = String(call?.args?.CommandLine ?? call?.args?.commandLine ?? '');
  if (WRITE_LINE.test(line)) return { decision: 'deny', reason: 'commands that write, delete or go online are not allowed in a review' };
  for (const seg of line.split(/\|\||&&|;|\|/)) {
    const words = seg.trim().replace(/^[&.]\s*/, '').split(/\s+/).filter(Boolean);
    if (!words.length) continue;
    const prog = words[0].replace(/^["']|["']$/g, '').replace(/\.exe$/i, '').split(/[\\/]/).pop().toLowerCase();
    if (!READ_PROGRAMS.has(prog)) return { decision: 'deny', reason: `program ${prog} is not on the read-only list` };
    if (prog === 'git') {
      const sub = words.slice(1).find((w) => !w.startsWith('-'));
      if (!sub || !GIT_READ.has(sub.toLowerCase())) return { decision: 'deny', reason: `git ${sub ?? ''} is not a read-only git command` };
    }
  }
  return { decision: 'allow', permissionOverrides: [`command(${line})`] };
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
