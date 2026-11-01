#!/usr/bin/env node
/**
 * upgrade-worker.mjs — API worker for shader upgrade batches.
 *
 * Fills the gap run-upgrade-swarm.js leaves at `--dispatch` ("needs a subagent
 * worker implementation"). One Claude API call per shader, under the live
 * contract in docs/SHADER_UPGRADE_BATCH.md:
 *
 *   1. Context: the contract docs + a shipped golden upgrade go in a cached
 *      system prefix (identical for every shader); the shader's WGSL, JSON,
 *      ledger history and the batch's already-used formulas go in the user turn.
 *   2. Output: structured JSON — the Idea Card fields come before the WGSL in
 *      the schema, so the card is literally written first (§2).
 *   3. Gates (script, never the model): naga-wasm, wgsl_precommit_gate
 *      (prelude / bindgroup / workgroup / extraBuffer), audit_dead_sliders, and
 *      contract checks — 2–4 ideas, `// ── Idea n:` markers, header Ideas/Upgraded
 *      lines, entry point + workgroup size unchanged, not a rewrite, not
 *      boilerplate-only, feature tags truthful, batch formula de-dup (§12.4).
 *   4. Repair: gate errors go back to the same conversation (thinking blocks
 *      round-tripped unchanged). After --repairs failures it escalates once to
 *      --escalate-model with a fresh conversation that carries the error history.
 *   5. Result: passing WGSL stays in public/shaders/; failures are restored and the
 *      rejected candidate saved. BRIEFS.md / NOTES.md / results.json go to
 *      agents/swarm-outputs/<run>/. Saved `params` are never touched.
 *
 * It does not commit and does not record the ledger — review the diff (the
 * Opus reviewer pass / COORDINATOR_REVIEW.md), then run the printed
 * `npm run upgrades:record` command.
 *
 * Usage:
 *   ANTHROPIC_API_KEY=… node scripts/upgrade-worker.mjs --ids=pp-sharpen,vhs-tracking
 *   node scripts/upgrade-worker.mjs --pick=10 --category=retro-glitch
 *   node scripts/upgrade-worker.mjs --ids=foo --dry-run          # assemble + save the request, no API call
 *
 * Flags:
 *   --ids=a,b,c             Shader ids to upgrade (catalog ids, not pass files)
 *   --pick=N                Auto-pick N: never-upgraded first, then oldest upgrade (skips
 *                           multipass, `_` libraries, files without the prelude include)
 *   --category=NAME         Restrict --pick to one shader_definitions/<category>
 *   --model=ID              Worker model (default claude-sonnet-5-5)
 *   --effort=LEVEL          low|medium|high|xhigh|max (default high)
 *   --escalate-model=ID     Model for the last-chance attempt (default claude-opus-5-5;
 *                           --escalate-model=none disables escalation)
 *   --escalate-effort=LEVEL Effort for escalation (default high)
 *   --repairs=N             Repair turns before escalating (default 2)
 *   --batch=NAME            Run name used in the output folder (default api-batch)
 *   --max-tokens=N          Per-request output cap incl. thinking (default 64000)
 *   --migrate-prelude       Run migrate_to_prelude.py first on files that paste the header
 *                           (infrastructure, no Upgraded: bump — allowed by AGENTS.md)
 *   --dry-run               Write the assembled request(s) to the run folder; no API call
 *   --mock-dir=DIR          Read <DIR>/<id>.json (and <id>.repair1.json …) instead of calling
 *                           the API — for offline tests of the gate/repair path
 *
 * Env: ANTHROPIC_API_KEY (required unless --dry-run / --mock-dir).
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SHADER_DIR = path.join(ROOT, 'public', 'shaders');
const DEF_DIR = path.join(ROOT, 'shader_definitions');
const LEDGER_PATH = path.join(ROOT, 'reports', 'shader-upgrade-ledger.json');
const API_URL = 'https://api.anthropic.com/v1/messages';
const API_VERSION = '2026-10-21';

// Static prefix, in order. Identical bytes for every shader → one cache write, then reads.
const PREFIX_DOCS = [
  ['docs/SHADER_UPGRADE_BATCH.md', 'The live upgrade contract. §0–§11 are law; §12 is the idea toolkit.'],
  ['docs/agents/WGSL_BUILTINS_GENERATIVE.md', 'Bindings, uniforms, extraBuffer map, naga-safe builtins.'],
  ['docs/CREATIVE_VISION.md', 'Artistic direction for the catalog.'],
  ['public/shaders/_prelude.wgsl', 'What `#include "_prelude.wgsl"` expands to. Never paste it.'],
];
const GOLDEN = ['analog-film-degrade']; // shipped upgrades with a correct header/ideas/packing

// Local calendar date: Upgraded: lines follow the maintainer's day, not UTC.
const today = () => new Date().toLocaleDateString('en-CA');

const FEATURE_TAGS = ['upgraded-rgba', 'audio-reactive', 'mouse-driven', 'temporal', 'depth-aware', 'semantic-alpha'];

// ─────────────────────────────────────────────────────────────── args ──
function parseArgs(argv) {
  const o = {
    ids: [], pick: 0, category: null,
    model: 'claude-sonnet-5-5', effort: 'high',
    escalateModel: 'claude-opus-5-5', escalateEffort: 'high',
    repairs: 2, batch: 'api-batch', maxTokens: 64000,
    migratePrelude: false, dryRun: false, mockDir: null,
  };
  for (const a of argv) {
    const [k, ...rest] = a.replace(/^--/, '').split('=');
    const v = rest.join('=');
    switch (k) {
      case 'ids': o.ids = v.split(',').map((s) => s.trim()).filter(Boolean); break;
      case 'pick': o.pick = Number(v); break;
      case 'category': o.category = v; break;
      case 'model': o.model = v; break;
      case 'effort': o.effort = v; break;
      case 'escalate-model': o.escalateModel = v === 'none' ? null : v; break;
      case 'escalate-effort': o.escalateEffort = v; break;
      case 'repairs': o.repairs = Number(v); break;
      case 'batch': o.batch = v; break;
      case 'max-tokens': o.maxTokens = Number(v); break;
      case 'migrate-prelude': o.migratePrelude = true; break;
      case 'dry-run': o.dryRun = true; break;
      case 'mock-dir': o.mockDir = path.resolve(v); break;
      case 'help': case 'h': o.help = true; break;
      default: throw new Error(`unknown flag --${k}`);
    }
  }
  return o;
}

// ──────────────────────────────────────────────────────────── catalog ──
const read = (p) => fs.readFileSync(p, 'utf8');
const rel = (p) => path.relative(ROOT, p);

function findDefinition(id) {
  for (const cat of fs.readdirSync(DEF_DIR)) {
    const p = path.join(DEF_DIR, cat, `${id}.json`);
    if (fs.existsSync(p)) return { path: p, category: cat };
  }
  return null;
}

function loadLedger() {
  return fs.existsSync(LEDGER_PATH) ? JSON.parse(read(LEDGER_PATH)) : { shaders: {} };
}

function eligibility(id) {
  if (id.startsWith('_')) return 'library file';
  const wgsl = path.join(SHADER_DIR, `${id}.wgsl`);
  if (!fs.existsSync(wgsl)) return 'no public/shaders/<id>.wgsl';
  const def = findDefinition(id);
  if (!def) return 'no shader_definitions/*/<id>.json';
  const json = JSON.parse(read(def.path));
  if (json.multipass) return 'multipass graph (upgrade by hand: passes share packing)';
  if (!/@compute/.test(read(wgsl))) return 'not a compute shader';
  return null;
}

function pickIds(n, category) {
  const ledger = loadLedger();
  const cats = category ? [category] : fs.readdirSync(DEF_DIR);
  const cands = [];
  for (const cat of cats) {
    const dir = path.join(DEF_DIR, cat);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith('.json')) continue;
      const id = f.slice(0, -5);
      if (eligibility(id)) continue;
      if (!read(path.join(SHADER_DIR, `${id}.wgsl`)).includes('#include "_prelude.wgsl"')) continue;
      const hist = (ledger.shaders[id]?.history || []).filter((h) => h.event === 'upgraded');
      const last = hist.length ? hist[hist.length - 1].date : '';
      cands.push({ id, cat, last });
    }
  }
  // never-upgraded first, then oldest; interleave categories so a batch isn't one family by accident
  cands.sort((a, b) => a.last.localeCompare(b.last) || a.id.localeCompare(b.id));
  const byCat = new Map();
  for (const c of cands) (byCat.get(c.cat) || byCat.set(c.cat, []).get(c.cat)).push(c);
  const out = [];
  while (out.length < n && [...byCat.values()].some((l) => l.length)) {
    for (const l of byCat.values()) if (l.length && out.length < n) out.push(l.shift().id);
  }
  return out;
}

// ────────────────────────────────────────────────────────────── prompt ──
const INSTRUCTIONS = `You are the worker in an automated shader-upgrade pipeline for Pixelocity, a WebGPU app with ~1,400 WGSL compute-shader effects. You receive ONE existing catalog shader per request and return its upgraded WGSL plus the Idea Card that justifies it.

What an upgrade is here is defined by the attached docs/SHADER_UPGRADE_BATCH.md. It wins over anything else, including your own taste. The short version:
- Add 2–4 named visual ideas that are native to THIS effect — extensions of the mechanism the file already has, phrased with its own nouns. Two is the default.
- Keep the algorithm, the look, the modes, the kernel family and every saved param's role. A viewer must recognize the original effect in the first second.
- Plumbing (prelude include, 16×16×1, ACES, semantic alpha, exact C loads, live sliders) is the floor, never the upgrade. Spring cursors, ripple shockwaves, IQ palettes, holographic scanlines and oil-slick chroma are overlays unless this file's identity already is one of them.
- Quieter ideas for post-processing / photographic filters; bolder is allowed for generative, liquid and glitch.

How you work:
1. Read the current WGSL and JSON. Fill the Idea Card fields first — identity, keep_verbatim, ideas, forbid, a_packing — from the file as it is now. Then write the WGSL that implements exactly that card.
2. Implement each idea inside the existing main path. Put a comment \`// ── Idea n: <name>\` at the place each idea acts (n = 1..k, in card order), so a reviewer can point at it in the diff.
3. Update the header banner: \`Upgraded: <today>\`, an \`Ideas:\` line naming the ideas (with the §12.2 formula ref when you used one), and an \`A packing:\` line that tells the truth about what dataTextureA holds. Copy the banner shape from the golden example.
4. Saved params are fixed: u.zoom_params.xyzw keep their meanings and ranges. New tuning values are literals or derive from an existing param's existing role. You cannot edit the JSON params; only the feature tags listed in the schema.
5. Keep \`#include "_prelude.wgsl"\`; never declare bindings 0–12 or struct Uniforms. Keep the entry-point name and @workgroup_size. No reserved identifiers (target, array, …), no fwidth/dpdx in compute, no pow with a possibly negative base, no unbounded loops. Persistent state only in extraBuffer[133..138], single writer at (0,0).
6. Return the complete WGSL file, not a diff.

The script that receives your output runs naga, the bind-group/workgroup/prelude/extraBuffer gate, a dead-slider audit and contract checks (idea markers, header lines, not-a-rewrite, not-boilerplate-only, truthful feature tags). If anything fails you get the errors back and fix them.`;

function prefixBlocks() {
  const blocks = [{ type: 'text', text: INSTRUCTIONS }];
  for (const [p, why] of PREFIX_DOCS) {
    blocks.push({ type: 'text', text: `<document path="${p}" role="${why}">\n${read(path.join(ROOT, p))}\n</document>` });
  }
  for (const id of GOLDEN) {
    const def = findDefinition(id);
    blocks.push({
      type: 'text',
      text:
        `<golden_example id="${id}" note="A shipped, accepted upgrade. Copy its banner shape, idea naming and packing honesty — not its ideas.">\n` +
        `<wgsl>\n${read(path.join(SHADER_DIR, `${id}.wgsl`))}\n</wgsl>\n<json>\n${def ? read(def.path) : ''}\n</json>\n</golden_example>`,
    });
  }
  // One breakpoint on the last static block caches everything above it.
  blocks[blocks.length - 1].cache_control = { type: 'ephemeral', ttl: '1h' };
  return blocks;
}

const OUTPUT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['idea_card', 'wgsl', 'features_add', 'features_remove', 'notes'],
  properties: {
    idea_card: {
      type: 'object',
      additionalProperties: false,
      required: ['identity', 'keep_verbatim', 'ideas', 'forbid', 'a_packing'],
      properties: {
        identity: { type: 'string', description: 'One sentence: what a viewer must still recognize.' },
        keep_verbatim: { type: 'array', items: { type: 'string' }, description: 'Kernel, modes, param roles, packing that ARE the effect, by name.' },
        ideas: {
          type: 'array',
          minItems: 1,
          description: '2–4 native ideas, in the order of the // ── Idea n: markers.',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['name', 'why_native', 'formula_ref'],
            properties: {
              name: { type: 'string' },
              why_native: { type: 'string', description: 'One sentence: why it belongs on THIS effect.' },
              formula_ref: { type: 'string', description: 'The §12.2 row used (e.g. "12.2A halation"), or "original" if none.' },
            },
          },
        },
        forbid: { type: 'array', items: { type: 'string' }, description: 'Overlays/motifs that would erase identity on this file.' },
        a_packing: { type: 'string', description: 'What dataTextureA holds and how C is read back.' },
      },
    },
    wgsl: { type: 'string', description: 'The complete upgraded .wgsl file.' },
    features_add: { type: 'array', items: { type: 'string', enum: FEATURE_TAGS } },
    features_remove: { type: 'array', items: { type: 'string', enum: FEATURE_TAGS } },
    notes: {
      type: 'object',
      additionalProperties: false,
      required: ['kept_verbatim', 'where_ideas_act', 'risks'],
      properties: {
        kept_verbatim: { type: 'string', description: 'What was deliberately left byte-identical.' },
        where_ideas_act: { type: 'string', description: 'Per idea: the function/lines where it acts.' },
        risks: { type: 'string', description: 'Anything a reviewer with a real GPU should look at.' },
      },
    },
  },
};

function shaderContext(id, batchState) {
  const wgslPath = path.join(SHADER_DIR, `${id}.wgsl`);
  const def = findDefinition(id);
  const hist = loadLedger().shaders[id]?.history || [];
  const used = [...batchState.formulaUse.entries()].filter(([, ids]) => ids.length);
    return [
    `Upgrade this shader. Today is ${today()}.`,
    `<shader id="${id}" category="${def.category}" wgsl_path="${rel(wgslPath)}" json_path="${rel(def.path)}">`,
    `<current_wgsl>\n${read(wgslPath)}\n</current_wgsl>`,
    `<definition_json>\n${read(def.path)}\n</definition_json>`,
    '</shader>',
    hist.length
      ? `<upgrade_history note="Earlier passes on this file. Do not repeat their ideas; build on them.">\n${hist.map((h) => `- ${h.date.slice(0, 10)} ${h.event}: ${h.note || '(no note)'}`).join('\n')}\n</upgrade_history>`
      : '<upgrade_history>No recorded upgrade passes on this file.</upgrade_history>',
    used.length
      ? `<batch_so_far note="§12.4: a formula row may appear on at most two files per batch. Rows already used:">\n${used.map(([f, ids]) => `- ${f}: ${ids.join(', ')}`).join('\n')}\n</batch_so_far>`
      : '',
  ].filter(Boolean).join('\n\n');
}

function buildRequest({ model, effort, maxTokens, messages }) {
  return {
    model,
    max_tokens: maxTokens,
    stream: true,
    system: prefixBlocks(),
    output_config: { effort, format: { type: 'json_schema', schema: OUTPUT_SCHEMA } },
    messages,
  };
}

// ───────────────────────────────────────────────────────────────── API ──
async function callApi(body, { attempts = 5 } = {}) {
  for (let i = 0; ; i++) {
    const res = await fetch(API_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': API_VERSION,
      },
      body: JSON.stringify(body),
    });
    if (res.ok) return readStream(res);
    const text = await res.text();
    const retryable = res.status === 429 || res.status === 529 || res.status >= 500;
    if (!retryable || i + 1 >= attempts) throw new Error(`API ${res.status}: ${text.slice(0, 500)}`);
    const wait = Number(res.headers.get('retry-after')) * 1000 || 2000 * 2 ** i;
    console.warn(`  … API ${res.status}, retrying in ${Math.round(wait / 1000)}s`);
    await new Promise((r) => setTimeout(r, wait));
  }
}

/** Minimal SSE accumulator → a Message object (content blocks kept exactly, signatures included). */
async function readStream(res) {
  const msg = { content: [], stop_reason: null, usage: {} };
  const decoder = new TextDecoder();
  let buf = '';
  const handle = (evt) => {
    switch (evt.type) {
      case 'message_start': Object.assign(msg, evt.message, { content: [] }); break;
      case 'content_block_start': msg.content[evt.index] = structuredClone(evt.content_block); break;
      case 'content_block_delta': {
        const b = msg.content[evt.index], d = evt.delta;
        if (d.type === 'text_delta') b.text += d.text;
        else if (d.type === 'thinking_delta') b.thinking += d.thinking;
        else if (d.type === 'signature_delta') b.signature = (b.signature || '') + d.signature;
        else if (d.type === 'input_json_delta') b._json = (b._json || '') + d.partial_json;
        break;
      }
      case 'message_delta':
        Object.assign(msg, evt.delta);
        msg.usage = { ...msg.usage, ...evt.usage };
        break;
      case 'error': throw new Error(`stream error: ${JSON.stringify(evt.error)}`);
      default: break;
    }
  };
  for await (const chunk of res.body) {
    buf += decoder.decode(chunk, { stream: true });
    let i;
    while ((i = buf.indexOf('\n\n')) >= 0) {
      const frame = buf.slice(0, i);
      buf = buf.slice(i + 2);
      const data = frame.split('\n').filter((l) => l.startsWith('data:')).map((l) => l.slice(5).trim()).join('');
      if (data) handle(JSON.parse(data));
    }
  }
  return msg;
}

function parseOutput(msg) {
  if (msg.stop_reason === 'refusal') throw new Error('model refused (stop_reason: refusal)');
  if (msg.stop_reason === 'max_tokens') throw new Error('hit max_tokens before finishing — raise --max-tokens or lower --effort');
  const text = msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('');
  return JSON.parse(text);
}

// ─────────────────────────────────────────────────────────────── gates ──
let nagaValidator;
async function nagaValidate(file) {
  if (!nagaValidator) {
    const contract = JSON.parse(read(path.join(ROOT, 'src/contracts/wgsl_validation.json')));
    const { createNagaValidator } = await import(pathToFileURL(path.join(ROOT, contract.loader)).href);
    const { validate } = await createNagaValidator({ bytes: fs.readFileSync(path.join(ROOT, contract.artifact)) });
    const { expandWgslIncludes, hasWgslInclude } = await import(pathToFileURL(path.join(ROOT, 'public/wasm/bridge/wgslInclude.js')).href);
    const readLib = async (n) => (fs.existsSync(path.join(SHADER_DIR, n)) ? read(path.join(SHADER_DIR, n)) : null);
    nagaValidator = async (raw, name) => validate(hasWgslInclude(raw) ? await expandWgslIncludes(raw, readLib, name) : raw);
  }
  const r = await nagaValidator(read(file), path.basename(file));
  return r.ok ? [] : [`naga ${r.kind || 'error'}: ${String(r.message).trim().slice(0, 1500)}`];
}

function runJson(cmd, args) {
  const r = spawnSync(cmd, args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 32 << 20 });
  const start = r.stdout.indexOf('{'), end = r.stdout.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error(`${args[0]} produced no JSON: ${r.stderr.slice(0, 500)}`);
  return JSON.parse(r.stdout.slice(start, end + 1)); // scripts print a verdict line after the JSON
}

// The gate scripts always rewrite their whole-catalog reports; a per-file run would leave
// them describing one shader. Snapshot and restore so the worker's diff is only shaders.
const GATE_REPORTS = ['reports/wgsl_precommit_report.json', 'reports/dead_sliders_audit.json', 'reports/dead_sliders_audit.md'];

function repoGates(id, file) {
  const saved = GATE_REPORTS.map((p) => [p, fs.existsSync(path.join(ROOT, p)) ? read(path.join(ROOT, p)) : null]);
  try {
    return runRepoGates(id, file);
  } finally {
    for (const [p, text] of saved) {
      if (text === null) fs.rmSync(path.join(ROOT, p), { force: true });
      else fs.writeFileSync(path.join(ROOT, p), text);
    }
  }
}

function runRepoGates(id, file) {
  const errs = [];
  const g = runJson('python3', ['scripts/wgsl_precommit_gate.py', '--files', rel(file), '--json']).results?.[0];
  if (g && !g.ok) {
    for (const k of ['bindgroup_errors', 'workgroup_errors', 'extrabuffer_violations', 'prelude_errors']) {
      for (const e of g[k] || []) errs.push(`${k.replace(/_/g, ' ')}: ${typeof e === 'string' ? e : JSON.stringify(e)}`);
    }
    if (!errs.length) errs.push(`precommit gate failed: ${JSON.stringify(g).slice(0, 800)}`);
  }
  const d = runJson('python3', ['scripts/audit_dead_sliders.py', '--files', id, '--json']);
  for (const s of d.new_dead_sliders || []) errs.push(`dead slider (a saved param no longer changes the picture): ${JSON.stringify(s)}`);
  for (const e of d.errors || []) errs.push(`dead-slider audit: ${JSON.stringify(e)}`);
  return errs;
}

const entryName = (src) => src.match(/@compute[\s\S]*?fn\s+(\w+)/)?.[1];
const workgroup = (src) => src.match(/@workgroup_size\(([^)]*)\)/)?.[1].replace(/\s+/g, '');
const codeLines = (src) => src.split('\n').map((l) => l.replace(/\/\/.*$/, '').trim()).filter(Boolean);

/** Line-level LCS-free diff stats via git (handles reordering sensibly). */
function diffStats(before, after) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'upw-'));
  const a = path.join(dir, 'a.wgsl'), b = path.join(dir, 'b.wgsl');
  fs.writeFileSync(a, before); fs.writeFileSync(b, after);
  const r = spawnSync('git', ['diff', '--no-index', '--unified=0', a, b], { encoding: 'utf8' });
  fs.rmSync(dir, { recursive: true, force: true });
  const added = [], removed = [];
  for (const l of r.stdout.split('\n')) {
    if (l.startsWith('+') && !l.startsWith('+++')) added.push(l.slice(1));
    else if (l.startsWith('-') && !l.startsWith('---')) removed.push(l.slice(1));
  }
  return { added, removed };
}

const BOILERPLATE = /aces|tonemap|tone_map|^\s*\/\/|extraBuffer\s*\[\s*13[3-8]|ripples\s*\[|spring|^\s*$|^\s*[{}]\s*$/i;

function contractChecks(out, before, after, json, batchState, id) {
  const errs = [];
  const ideas = out.idea_card?.ideas || [];
  if (ideas.length < 2 || ideas.length > 4) errs.push(`idea_card.ideas has ${ideas.length} entries; the contract requires 2–4.`);
  ideas.forEach((idea, i) => {
    const re = new RegExp(`//\\s*──\\s*Idea\\s*${i + 1}\\s*:`);
    if (!re.test(after)) errs.push(`No "// ── Idea ${i + 1}: …" marker in the WGSL for "${idea.name}".`);
  });
  if (!after.includes('#include "_prelude.wgsl"')) errs.push('Missing `#include "_prelude.wgsl"`.');
  if (entryName(before) !== entryName(after)) errs.push(`Entry point changed (${entryName(before)} → ${entryName(after)}).`);
  if (workgroup(before) !== workgroup(after)) errs.push(`@workgroup_size changed (${workgroup(before)} → ${workgroup(after)}).`);
    if (!new RegExp(`Upgraded:\\s*${today()}`).test(after)) errs.push(`Header must say "Upgraded: ${today()}".`);
  if (!/^\s*\/\/\s*Ideas:/m.test(after)) errs.push('Header is missing an "Ideas:" line.');
  if (!/^\s*\/\/\s*A packing:/m.test(after)) errs.push('Header is missing an "A packing:" line.');
  for (let i = 0; i < 4; i++) {
    const axis = 'xyzw'[i];
    if (new RegExp(`zoom_params\\.${axis}`).test(before) && !new RegExp(`zoom_params\\.${axis}`).test(after)) {
      errs.push(`u.zoom_params.${axis} (saved param ${i + 1}) is no longer read.`);
    }
  }

  const { added, removed } = diffStats(before, after);
  const origCode = codeLines(before).length || 1;
  const removedCode = removed.filter((l) => l.trim() && !l.trim().startsWith('//')).length;
  if (removedCode / origCode > 0.6) {
    errs.push(`Rewrite, not an upgrade: ${removedCode}/${origCode} original code lines removed or changed (limit 60%). Keep the existing main path and add to it.`);
  }
  const addedCode = added.filter((l) => !BOILERPLATE.test(l));
  if (addedCode.length < 8) errs.push(`Only ${addedCode.length} substantive added lines — the diff is header/ACES/boilerplate. Implement the ideas.`);
  else if (added.length && 1 - addedCode.length / added.length > 0.7) {
    errs.push(`${Math.round((1 - addedCode.length / added.length) * 100)}% of added lines are header/ACES/spring/ripple boilerplate (limit 70%).`);
  }

  // Tag truth is checked for tags the model adds, and for existing tags whose evidence it removed.
  const had = (re) => re.test(before);
  const claims = [
    ['upgraded-rgba', /aces/i, 'ACES on display RGB'],
    ['audio-reactive', /plasmaBuffer\s*\[\s*0\s*\]/, 'plasmaBuffer[0] to modulate something'],
    ['mouse-driven', /zoom_config\s*\.\s*(y|z|w|yz)/, 'the pointer (u.zoom_config.yz) to change the picture'],
  ];
  for (const [tag, re, need] of claims) {
    const adding = (out.features_add || []).includes(tag);
    const keeping = (json.features || []).includes(tag) && !(out.features_remove || []).includes(tag);
    if ((adding || (keeping && had(re))) && !re.test(after)) errs.push(`"${tag}" requires ${need}.`);
  }

  for (const idea of ideas) {
    const ref = (idea.formula_ref || '').trim().toLowerCase();
    if (!ref || ref === 'original') continue;
    const users = (batchState.formulaUse.get(ref) || []).filter((x) => x !== id);
    if (users.length >= 2) errs.push(`Formula "${idea.formula_ref}" is already on ${users.join(', ')} in this batch (§12.4 allows two). Pick a different native idea.`);
  }
  return errs;
}

// ───────────────────────────────────────────────────────────── worker ──
async function getResponse(opts, id, request, tag) {
  if (opts.mockDir) {
    const p = path.join(opts.mockDir, `${id}${tag ? `.${tag}` : ''}.json`);
    if (!fs.existsSync(p)) throw new Error(`mock missing: ${p}`);
    const out = read(p);
    return { content: [{ type: 'text', text: out }], stop_reason: 'end_turn', usage: {}, model: request.model };
  }
  return callApi(request);
}

async function upgradeOne(id, opts, batchState, runDir) {
  const wgslPath = path.join(SHADER_DIR, `${id}.wgsl`);
  const def = findDefinition(id);
  const original = read(wgslPath);
  const originalJson = read(def.path);
  const json = JSON.parse(originalJson);
  const log = { id, attempts: [], usage: [] };
  const errorHistory = [];

  const evaluate = async (out) => {
    if (typeof out.wgsl !== 'string' || !out.wgsl.trim()) return ['Output has no wgsl.'];
    fs.writeFileSync(wgslPath, out.wgsl.endsWith('\n') ? out.wgsl : `${out.wgsl}\n`);
    const errs = [...(await nagaValidate(wgslPath))];
    if (!errs.length) errs.push(...repoGates(id, wgslPath));
    errs.push(...contractChecks(out, original, read(wgslPath), json, batchState, id));
    return errs;
  };

  const plan = [{ model: opts.model, effort: opts.effort, turns: 1 + opts.repairs, fresh: true }];
  if (opts.escalateModel) plan.push({ model: opts.escalateModel, effort: opts.escalateEffort, turns: 1, fresh: true, escalation: true });

  let attemptNo = 0;
  for (const stage of plan) {
    const firstUser = stage.escalation
      ? `${shaderContext(id, batchState)}\n\n<previous_attempts note="A faster model tried this shader and its output failed the gates. Start from the CURRENT file above, not from its attempt.">\n${errorHistory.map((e, i) => `Attempt ${i + 1}:\n${e.join('\n')}`).join('\n\n')}\n</previous_attempts>`
      : shaderContext(id, batchState);
    const messages = [{ role: 'user', content: firstUser }];

    for (let turn = 0; turn < stage.turns; turn++) {
      attemptNo++;
      const request = buildRequest({ model: stage.model, effort: stage.effort, maxTokens: opts.maxTokens, messages });
      const tag = stage.escalation ? 'escalate' : turn ? `repair${turn}` : '';
      let msg, out, errs;
      try {
        msg = await getResponse(opts, id, request, tag);
        log.usage.push({ model: stage.model, ...msg.usage });
        out = parseOutput(msg);
        errs = await evaluate(out);
      } catch (e) {
        errs = [`${e.message}`];
      }
      log.attempts.push({ n: attemptNo, model: stage.model, effort: stage.effort, errors: errs });
      const cr = msg?.usage?.cache_read_input_tokens;
      console.log(`  ${errs.length ? '✗' : '✓'} attempt ${attemptNo} (${stage.model}${cr ? `, cache read ${cr}` : ''})${errs.length ? `: ${errs.length} problem(s)` : ''}`);
      if (!errs.length) {
        applyFeatures(def.path, originalJson, out, log);
        recordFormulas(batchState, id, out);
        return { ok: true, out, log };
      }
      for (const e of errs) console.log(`      - ${e.split('\n')[0].slice(0, 160)}`);
      errorHistory.push(errs);
      if (out?.wgsl) fs.writeFileSync(path.join(runDir, 'rejected', `${id}.attempt${attemptNo}.wgsl`), out.wgsl);
      fs.writeFileSync(wgslPath, original); // never leave a failing file in the tree
      if (!msg) break; // transport/parse failure: a repair turn has nothing to build on
      messages.push({ role: 'assistant', content: msg.content.filter((b) => b.type !== 'text' || b.text) });
      messages.push({
        role: 'user',
        content: `The pipeline rejected that output. Fix every problem below and return the full output again (same schema, complete WGSL):\n${errs.map((e) => `- ${e}`).join('\n')}`,
      });
    }
  }
  fs.writeFileSync(wgslPath, original);
  return { ok: false, log };
}

/** Feature tags only; params stay byte-exact. Skips files whose formatting a round-trip would change. */
function applyFeatures(defPath, originalJson, out, log) {
  const add = out.features_add || [], remove = out.features_remove || [];
  if (!add.length && !remove.length) return;
  const json = JSON.parse(originalJson);
  if (`${JSON.stringify(json, null, 2)}\n` !== originalJson) {
    log.featureNote = `features not written (JSON formatting would change): +${add.join(',')} -${remove.join(',')}`;
    return;
  }
  const feats = (json.features || []).filter((f) => !remove.includes(f));
  for (const f of add) if (!feats.includes(f)) feats.push(f);
  json.features = feats;
  fs.writeFileSync(defPath, `${JSON.stringify(json, null, 2)}\n`);
}

function recordFormulas(batchState, id, out) {
  for (const idea of out.idea_card.ideas) {
    const ref = (idea.formula_ref || '').trim().toLowerCase();
    if (!ref || ref === 'original') continue;
    batchState.formulaUse.set(ref, [...(batchState.formulaUse.get(ref) || []), id]);
  }
}

// ───────────────────────────────────────────────────────────── output ──
function cardMd(id, c) {
  return [
    `### ${id}`, '```',
    `SHADER: ${id}`,
    `IDENTITY: ${c.identity}`,
    `KEEP VERBATIM: ${c.keep_verbatim.join('; ')}`,
    'ADD:',
    ...c.ideas.map((x, i) => `  ${i + 1}. ${x.name} — ${x.why_native}${x.formula_ref && x.formula_ref !== 'original' ? ` (${x.formula_ref})` : ''}`),
    `FORBID: ${c.forbid.join('; ')}`,
    `A PACKING: ${c.a_packing}`,
    '```', '',
  ].join('\n');
}

function writeRunFiles(runDir, results, opts) {
  const ok = results.filter((r) => r.ok);
  fs.writeFileSync(path.join(runDir, 'BRIEFS.md'),
    `# Idea Cards — ${opts.batch}\n\nWorker: ${opts.model} (effort ${opts.effort}); escalation: ${opts.escalateModel || 'off'}.\nCards are emitted ahead of the WGSL in each structured response.\n\n${ok.map((r) => cardMd(r.log.id, r.out.idea_card)).join('\n')}`);
  fs.writeFileSync(path.join(runDir, 'NOTES.md'), [
    `# Notes — ${opts.batch}`, '',
    ...results.map((r) => r.ok
      ? `## ${r.log.id} — passed on attempt ${r.log.attempts.length} (${r.log.attempts.at(-1).model})\n- Ideas: ${r.out.idea_card.ideas.map((x) => x.name).join('; ')}\n- Kept verbatim: ${r.out.notes.kept_verbatim}\n- Where ideas act: ${r.out.notes.where_ideas_act}\n- A packing: ${r.out.idea_card.a_packing}\n- Risks for GPU QA: ${r.out.notes.risks}${r.log.featureNote ? `\n- ${r.log.featureNote}` : ''}\n`
      : `## ${r.log.id} — NOT UPGRADED (file restored)\n${r.log.attempts.map((a) => `- attempt ${a.n} (${a.model}): ${a.errors.map((e) => e.split('\n')[0]).join(' | ')}`).join('\n')}\n`),
    '', 'Gates run per file: naga-wasm, wgsl_precommit_gate (prelude/bindgroup/workgroup/extraBuffer), audit_dead_sliders, contract checks. Real-GPU visual QA: external.',
  ].join('\n'));
  fs.writeFileSync(path.join(runDir, 'results.json'), JSON.stringify(results.map((r) => r.log), null, 2));
}

// ─────────────────────────────────────────────────────────────── main ──
async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help || (!opts.ids.length && !opts.pick)) {
    console.log(read(fileURLToPath(import.meta.url)).split('\n').slice(1, 58).join('\n'));
    return;
  }
  if (!opts.dryRun && !opts.mockDir && !process.env.ANTHROPIC_API_KEY) throw new Error('ANTHROPIC_API_KEY is not set');

  const ids = opts.ids.length ? opts.ids : pickIds(opts.pick, opts.category);
  if (ids.length > 12) throw new Error(`${ids.length} shaders requested; the contract's hard ceiling is 12 per batch.`);

  const date = today();
  const runDir = path.join(ROOT, 'agents', 'swarm-outputs', `${opts.batch}-${date}`);
  fs.mkdirSync(path.join(runDir, 'rejected'), { recursive: true });

  const todo = [];
  for (const id of ids) {
    const why = eligibility(id);
    if (why) { console.log(`skip ${id}: ${why}`); continue; }
    const file = path.join(SHADER_DIR, `${id}.wgsl`);
    if (!read(file).includes('#include "_prelude.wgsl"')) {
      if (!opts.migratePrelude) { console.log(`skip ${id}: pastes the binding header — rerun with --migrate-prelude (header-only, no Upgraded: bump)`); continue; }
      execFileSync('python3', ['scripts/migrate_to_prelude.py', '--files', rel(file)], { cwd: ROOT, stdio: 'inherit' });
    }
    todo.push(id);
  }
  console.log(`Batch ${opts.batch}: ${todo.join(', ') || '(nothing)'}`);

  const batchState = { formulaUse: new Map() };
  if (opts.dryRun) {
    for (const id of todo) {
      const req = buildRequest({ model: opts.model, effort: opts.effort, maxTokens: opts.maxTokens, messages: [{ role: 'user', content: shaderContext(id, batchState) }] });
      fs.writeFileSync(path.join(runDir, `${id}.request.json`), JSON.stringify(req, null, 2));
      const prefixChars = req.system.reduce((n, b) => n + b.text.length, 0);
      console.log(`  ${id}: request saved (cached prefix ≈${Math.round(prefixChars / 3.6 / 1000)}k tok, shader turn ≈${Math.round(req.messages[0].content.length / 3.6 / 1000)}k tok)`);
    }
    return;
  }

  // Sequential on purpose: §12.4 de-dup needs each card before the next shader starts,
  // and the cached prefix is written once and then read by every later call.
  const results = [];
  for (const id of todo) {
    console.log(`\n▶ ${id}`);
    results.push(await upgradeOne(id, opts, batchState, runDir));
    writeRunFiles(runDir, results, opts);
  }

  const ok = results.filter((r) => r.ok).map((r) => r.log.id);
  const inTok = results.flatMap((r) => r.log.usage).reduce((a, u) => ({
    input: a.input + (u.input_tokens || 0), cacheRead: a.cacheRead + (u.cache_read_input_tokens || 0),
    cacheWrite: a.cacheWrite + (u.cache_creation_input_tokens || 0), output: a.output + (u.output_tokens || 0),
  }), { input: 0, cacheRead: 0, cacheWrite: 0, output: 0 });
  console.log(`\n${ok.length}/${todo.length} upgraded. Tokens: ${JSON.stringify(inTok)}`);
  console.log(`Notes: ${rel(runDir)}/`);
  if (ok.length) {
    console.log('\nNext: review the diff (reviewer pass → COORDINATOR_REVIEW.md), then:');
    console.log(`  npm run upgrades:record -- --ids=${ok.join(',')} --note="${date} ${opts.batch} (${opts.model}) — ${rel(runDir)}/NOTES.md"`);
    console.log('  node scripts/generate_shader_lists.js && npm run test:ci && npm run build');
  }
}

main().catch((e) => { console.error(`upgrade-worker: ${e.message}`); process.exit(1); });
