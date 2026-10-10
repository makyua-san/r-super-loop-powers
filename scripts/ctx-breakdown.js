// Break down what fills the orchestrator's context in one Claude Code transcript.
// usage: node ctx-breakdown.js <transcript.jsonl>
const fs = require('fs');
const file = process.argv[2];
const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);

const toolById = {};            // tool_use_id -> {name, inputBytes}
const resultBytesByTool = {};   // tool name -> bytes of tool_result content
const resultCountByTool = {};
const inputBytesByTool = {};    // tool name -> bytes of tool_use input (what Opus wrote)
let assistantTextBytes = 0, thinkingBytes = 0;
let userTextBytes = 0;
let turns = 0, maxCtx = 0, totalOutput = 0, totalUncachedInput = 0, totalCacheRead = 0, totalCacheCreate = 0;
const traj = [];
let compactions = 0;
const agentPrompts = [];        // {bytes, desc, subagent}
const bigResults = [];          // {tool, bytes, snippet}

function blen(x) { return Buffer.byteLength(typeof x === 'string' ? x : JSON.stringify(x), 'utf8'); }

for (const line of lines) {
  let o; try { o = JSON.parse(line); } catch { continue; }
  if (o.isCompactSummary) compactions++;
  const m = o.message; if (!m) continue;
  if (o.type === 'assistant') {
    const u = m.usage || {};
    const ctx = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
    if (ctx > 0) { turns++; if (ctx > maxCtx) maxCtx = ctx; traj.push([turns, ctx, o.timestamp]); }
    totalOutput += u.output_tokens || 0; totalUncachedInput += u.input_tokens || 0;
    totalCacheRead += u.cache_read_input_tokens || 0; totalCacheCreate += u.cache_creation_input_tokens || 0;
    for (const b of (Array.isArray(m.content) ? m.content : [])) {
      if (b.type === 'text') assistantTextBytes += blen(b.text);
      else if (b.type === 'thinking') thinkingBytes += blen(b.thinking || '');
      else if (b.type === 'tool_use') {
        const ib = blen(b.input);
        toolById[b.id] = { name: b.name, inputBytes: ib };
        inputBytesByTool[b.name] = (inputBytesByTool[b.name] || 0) + ib;
        if (b.name === 'Agent') agentPrompts.push({ bytes: blen(b.input.prompt || ''), desc: b.input.description, sub: b.input.subagent_type || b.input.model || '' });
        if (b.name === 'SendMessage') agentPrompts.push({ bytes: blen(b.input.message || ''), desc: 'SendMessage->' + (b.input.to || ''), sub: 'send' });
      }
    }
  } else if (o.type === 'user') {
    const c = m.content;
    if (typeof c === 'string') { userTextBytes += blen(c); continue; }
    for (const b of (Array.isArray(c) ? c : [])) {
      if (b.type === 'text') userTextBytes += blen(b.text);
      else if (b.type === 'tool_result') {
        const t = toolById[b.tool_use_id] || { name: '?' };
        const bytes = blen(b.content || '');
        resultBytesByTool[t.name] = (resultBytesByTool[t.name] || 0) + bytes;
        resultCountByTool[t.name] = (resultCountByTool[t.name] || 0) + 1;
        if (bytes > 20000) bigResults.push({ tool: t.name, bytes, snippet: (typeof b.content === 'string' ? b.content : JSON.stringify(b.content)).slice(0, 90).replace(/\s+/g, ' ') });
      }
    }
  }
}

console.log(`file=${file.split(/[\\/]/).pop()} turns=${turns} maxCtx=${maxCtx} compactions=${compactions}`);
console.log(`tokens: output=${totalOutput} uncachedInput=${totalUncachedInput} cacheCreate=${totalCacheCreate} cacheRead=${totalCacheRead}`);
console.log(`bytes: assistantText=${assistantTextBytes} thinking=${thinkingBytes} userText=${userTextBytes}`);
console.log('--- tool_result bytes by tool (what flows INTO the context) ---');
Object.entries(resultBytesByTool).sort((a, b) => b[1] - a[1]).forEach(([k, v]) => console.log(`  ${k.padEnd(22)} ${String(v).padStart(9)} B  in ${resultCountByTool[k]} calls`));
console.log('--- tool_use input bytes by tool (what Opus WROTE as tool args) ---');
Object.entries(inputBytesByTool).sort((a, b) => b[1] - a[1]).slice(0, 12).forEach(([k, v]) => console.log(`  ${k.padEnd(22)} ${String(v).padStart(9)} B`));
console.log('--- Agent / SendMessage prompts (bytes written by Opus) ---');
agentPrompts.forEach(p => console.log(`  ${String(p.bytes).padStart(7)} B  ${p.sub.padEnd(28)} ${p.desc || ''}`));
console.log('--- context trajectory (every 50th turn) ---');
traj.filter((t, i) => i % 50 === 0 || i === traj.length - 1).forEach(t => console.log(`  turn ${String(t[0]).padStart(4)}  ctx=${String(t[1]).padStart(7)}  ${t[2]}`));
console.log('--- tool results > 20KB ---');
bigResults.sort((a, b) => b.bytes - a.bytes).slice(0, 15).forEach(r => console.log(`  ${String(r.bytes).padStart(7)} B  ${r.tool.padEnd(12)} ${r.snippet}`));
