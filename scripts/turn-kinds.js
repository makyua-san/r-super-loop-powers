// Classify orchestrator turns by what they did, and split user-side text by origin.
const fs = require('fs');
const file = process.argv[2];
const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
const kinds = {}; const userKinds = {};
function bump(o, k, n) { o[k] = (o[k] || 0) + (n === undefined ? 1 : n); }
function blen(x) { return Buffer.byteLength(typeof x === 'string' ? x : JSON.stringify(x), 'utf8'); }
let turns = 0;
for (const line of lines) {
  let o; try { o = JSON.parse(line); } catch { continue; }
  const m = o.message; if (!m) continue;
  if (o.type === 'assistant' && m.usage && (m.usage.cache_read_input_tokens || m.usage.input_tokens)) {
    turns++;
    const tus = (Array.isArray(m.content) ? m.content : []).filter(b => b.type === 'tool_use');
    if (tus.length === 0) { bump(kinds, 'text-only (reply to human)'); continue; }
    for (const b of tus) {
      const s = JSON.stringify(b.input);
      let k = b.name;
      if (b.name === 'Bash' || b.name === 'PowerShell') {
        if (/call-log/.test(s)) k = 'bookkeeping: call-log append';
        else if (/state\.md/.test(s)) k = 'bookkeeping: state.md';
        else if (/impl-check\.ps1/.test(s)) k = 'impl-check (snapshot/judge)';
        else if (/codex-status\.ps1/.test(s)) k = 'codex-status poll';
        else if (/codex-run\.ps1/.test(s)) k = 'codex-run launch';
        else if (/git (rev-parse|status|add|commit|log|diff)/.test(s)) k = 'git';
        else if (/hook-log|\.report\.md|\.prompt\.md|cat >|Set-Content|Out-File|<<'?EOF/.test(s)) k = 'shell: write doc/prompt/report';
        else k = 'shell: other';
      } else if (b.name === 'Write' || b.name === 'Edit') {
        const p = String(b.input.file_path || '');
        if (/state\.md/.test(p)) k = 'bookkeeping: state.md';
        else if (/call-log/.test(p)) k = 'bookkeeping: call-log append';
        else if (/\.prompt\.md|codex-runs.*prompt/.test(p)) k = 'write delegation prompt';
        else if (/\.report\.md/.test(p)) k = 'write report copy';
        else if (/docs\/r-super-loop-powers/.test(p)) k = 'write loop doc (submission/report/retro/...)';
        else k = 'write other';
      }
      bump(kinds, k);
    }
  } else if (o.type === 'user') {
    const c = m.content;
    const blocks = typeof c === 'string' ? [{ type: 'text', text: c }] : (Array.isArray(c) ? c : []);
    for (const b of blocks) {
      if (b.type !== 'text') continue;
      const t = b.text || ''; const n = blen(t);
      if (/^<system-reminder>/.test(t.trim())) {
        if (/superpowers/.test(t)) bump(userKinds, 'system-reminder: superpowers/skills boot', n);
        else if (/memory|MEMORY\.md/.test(t)) bump(userKinds, 'system-reminder: memory', n);
        else bump(userKinds, 'system-reminder: other', n);
      } else if (/^\[r-super-loop-powers\]/.test(t.trim()) || /Stop hook/.test(t)) bump(userKinds, 'stop-hook block', n);
      else if (/task-notification|SYSTEM NOTIFICATION/.test(t)) bump(userKinds, 'task notifications', n);
      else if (/<local-command|<command-name>/.test(t)) bump(userKinds, 'local commands', n);
      else if (/<task-notification|<bridge|SendMessage|message from/.test(t)) bump(userKinds, 'agent messages', n);
      else bump(userKinds, 'human text', n);
    }
  }
}
console.log(`turns=${turns}`);
console.log('--- tool_use by kind ---');
Object.entries(kinds).sort((a, b) => b[1] - a[1]).forEach(([k, v]) => console.log(`  ${String(v).padStart(4)}  ${k}`));
console.log('--- user-side text bytes by origin ---');
Object.entries(userKinds).sort((a, b) => b[1] - a[1]).forEach(([k, v]) => console.log(`  ${String(v).padStart(8)} B  ${k}`));
