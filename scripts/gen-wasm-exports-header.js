#!/usr/bin/env node
/**
 * Generate both sides of the WASM export ABI from src/contracts/wasm_exports.json
 * `exports` (one entry per C export: signature + suspension policy):
 *
 *   wasm_renderer/wasm_exports.h     extern "C" prototypes main.cpp includes, so a
 *                                    definition that drifts from the contract is a
 *                                    compile error (conflicting C declaration)
 *   src/wasm/bridge/_generated.ts    typed ccall wrappers, one per export; they go
 *                                    through the call seam in src/wasm/bridge/call.ts
 *                                    (async exports awaited with { async: true },
 *                                    sync ones follow their whileSuspended policy)
 *
 * Usage: node scripts/gen-wasm-exports-header.js [--check]
 *   (none)  — write both files (committed; `npm run gen:wasm-exports`)
 *   --check — exit 1 if either committed file differs from the contract, or a
 *             main.cpp EMSCRIPTEN_KEEPALIVE signature differs from it
 *             (also run by verify:device-policy)
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const CONTRACT_PATH = path.join(ROOT, 'src', 'contracts', 'wasm_exports.json');
const COMPILE_FLAGS_PATH = path.join(ROOT, 'src', 'contracts', 'wasm_compile_flags.json');
const HEADER_REL = 'wasm_renderer/wasm_exports.h';
const TS_REL = 'src/wasm/bridge/_generated.ts';
const MAIN_CPP_REL = 'wasm_renderer/main.cpp';

const RETURN_TYPES = new Set(['void', 'int', 'float', 'string']);
const VALUE_TYPES = new Set(['int', 'float', 'string']);
const POLICIES = new Set(['call', 'queue', 'skip']);

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function loadContract(file = CONTRACT_PATH) {
  return readJson(file);
}

/** `const uint8_t *` → `const uint8_t*`; collapses whitespace. */
function normalizeCType(t) {
  return String(t).replace(/\s+/g, ' ').replace(/\s*\*\s*/g, '*').trim();
}

const isPointer = (t) => t.endsWith('*');

/** C spelling of a contract type. */
function cType(t) {
  if (t === 'string') return 'const char*';
  return t;
}

/**
 * Parse and validate `exports`. Throws on a malformed entry, on keys that are not
 * exportedFunctions minus runtimeOnlyExports, or when the async set differs from
 * wasm_compile_flags.json jspi.jspiExports (the JSPI build wraps exactly those).
 */
function loadSignatures(contract = loadContract(), compileFlags = readJson(COMPILE_FLAGS_PATH)) {
  const runtimeOnly = new Set(contract.runtimeOnlyExports || []);
  const listed = contract.exportedFunctions.filter((n) => !runtimeOnly.has(n)).map((n) => n.slice(1));
  const entries = contract.exports || {};
  const names = Object.keys(entries);
  const missing = listed.filter((n) => !names.includes(n));
  const extra = names.filter((n) => !listed.includes(n));
  if (missing.length || extra.length) {
    throw new Error(
      'wasm_exports.json `exports` must have one entry per exportedFunctions name (minus runtimeOnlyExports); ' +
        `missing [${missing.join(', ')}], extra [${extra.join(', ')}]`,
    );
  }

  const sigs = names.map((name) => {
    const e = entries[name];
    if (!RETURN_TYPES.has(e.returns)) throw new Error(`exports.${name}: returns must be void|int|float|string`);
    const seen = new Set();
    const args = (e.args || []).map((spec) => {
      const at = String(spec).indexOf(':');
      const argName = at > 0 ? String(spec).slice(0, at) : '';
      const type = at > 0 ? normalizeCType(String(spec).slice(at + 1)) : '';
      if (!/^[A-Za-z_]\w*$/.test(argName)) throw new Error(`exports.${name}: arg "${spec}" must be "name:type"`);
      if (seen.has(argName)) throw new Error(`exports.${name}: duplicate arg ${argName}`);
      seen.add(argName);
      if (!VALUE_TYPES.has(type) && !(isPointer(type) && /^(const )?[A-Za-z_]\w*\*$/.test(type))) {
        throw new Error(`exports.${name}: arg ${argName} type "${type}" must be int|float|string or a C pointer type`);
      }
      return { name: argName, type };
    });
    const isAsync = e.async === true;
    if (isAsync && e.whileSuspended !== undefined) throw new Error(`exports.${name}: async exports take no whileSuspended`);
    if (!isAsync && !POLICIES.has(e.whileSuspended)) {
      throw new Error(`exports.${name}: sync exports need whileSuspended call|queue|skip`);
    }
    if (isAsync && e.optional) throw new Error(`exports.${name}: an async export cannot be optional`);
    if (e.optional && args.some((a) => a.type === 'string')) {
      throw new Error(`exports.${name}: an optional export is called directly (no ccall marshalling), so it cannot take a string`);
    }
    if (e.whileSuspended === 'queue') {
      if (e.returns !== 'void') throw new Error(`exports.${name}: a queued export may run later, so it must return void`);
      if (args.some((a) => isPointer(a.type))) {
        throw new Error(`exports.${name}: a queued export may run later, so it cannot take a caller-owned pointer`);
      }
    }
    return {
      name,
      returns: e.returns,
      args,
      isAsync,
      whileSuspended: isAsync ? null : e.whileSuspended,
      optional: e.optional === true,
      note: e.note || null,
    };
  });

  const asyncNames = sigs.filter((s) => s.isAsync).map((s) => s.name).sort();
  const jspi = [...((compileFlags.jspi && compileFlags.jspi.jspiExports) || [])].sort();
  if (JSON.stringify(asyncNames) !== JSON.stringify(jspi)) {
    throw new Error(
      `wasm_exports.json async exports ${JSON.stringify(asyncNames)} must equal ` +
        `wasm_compile_flags.json jspi.jspiExports ${JSON.stringify(jspi)}`,
    );
  }
  return sigs;
}

// ─── C++ ──────────────────────────────────────────────────────────────────────

function cPrototype(sig) {
  const params = sig.args.length ? sig.args.map((a) => `${cType(a.type)} ${a.name}`).join(', ') : '';
  return `${cType(sig.returns)} ${sig.name}(${params});`;
}

function policyTag(sig) {
  if (sig.isAsync) return 'async';
  return `${sig.whileSuspended}${sig.optional ? ', optional' : ''}`;
}

function renderHeader(sigs) {
  const pascal = (s) => s[0].toUpperCase() + s.slice(1);
  const width = Math.max(...sigs.map((s) => s.name.length));
  return [
    '// GENERATED by scripts/gen-wasm-exports-header.js from',
    '// src/contracts/wasm_exports.json `exports`. Do not edit: change the JSON and',
    '// run `npm run gen:wasm-exports`. verify:device-policy fails when this is stale',
    '// or when a main.cpp EMSCRIPTEN_KEEPALIVE signature differs from the contract.',
    '//',
    '// main.cpp includes this before it defines the exports, so a definition whose',
    '// parameter or return types drift is a compile error (conflicting declaration',
    '// of a C function). The TS twin is src/wasm/bridge/_generated.ts.',
    '#pragma once',
    '',
    '#include <cstddef>',
    '#include <cstdint>',
    '',
    'extern "C" {',
    '',
    ...sigs.map((s) => `${cPrototype(s)}  // ${policyTag(s)}`),
    '',
    '}  // extern "C"',
    '',
    'namespace wasm_exports {',
    '',
    '// What the bridge does when the export is called while an async export of',
    '// the same module is suspended in wgpuInstanceWaitAny (src/wasm/bridge/call.ts).',
    'enum class WhileSuspended : uint8_t {',
    '    Async,  // the export itself suspends; calls are serialized',
    '    Call,   // runs now (plain CPU state)',
    '    Queue,  // runs after the in-flight async work, in call order',
    '    Skip,   // dropped; the next frame redoes it',
    '};',
    '',
    'struct ExportInfo {',
    '    const char* name;',
    '    WhileSuspended whileSuspended;',
    '    bool optional;  // older artifacts lack it; the bridge feature-tests first',
    '};',
    '',
    'inline constexpr ExportInfo kExports[] = {',
    ...sigs.map((s) => {
      const p = s.isAsync ? 'Async' : pascal(s.whileSuspended);
      return `    { ${`"${s.name}",`.padEnd(width + 3)} WhileSuspended::${`${p},`.padEnd(6)} ${s.optional} },`;
    }),
    '};',
    `inline constexpr size_t kExportCount = ${sigs.length};`,
    `inline constexpr size_t kAsyncExportCount = ${sigs.filter((s) => s.isAsync).length};`,
    '',
    '}  // namespace wasm_exports',
    '',
  ].join('\n');
}

// ─── TypeScript ───────────────────────────────────────────────────────────────

const ccallType = (t) => (t === 'string' ? "'string'" : "'number'");
const tsArgType = (t) => (t === 'string' ? 'string' : isPointer(t) ? 'WasmPtr' : 'number');
const tsValue = (r) => (r === 'void' ? 'void' : r === 'string' ? 'string' : 'number');
const ccallReturn = (r) => (r === 'void' ? 'null' : r === 'string' ? "'string'" : "'number'");

function tsWrapper(sig) {
  const params = ['mod: EmscriptenModule', ...sig.args.map((a) => `${a.name}: ${tsArgType(a.type)}`)].join(', ');
  const argTypes = `[${sig.args.map((a) => ccallType(a.type)).join(', ')}]`;
  const argList = `[${sig.args.map((a) => a.name).join(', ')}]`;
  const ret = ccallReturn(sig.returns);
  const value = tsValue(sig.returns);
  const convert =
    value === 'number' ? (v) => `Number(${v} ?? 0)` : value === 'string' ? (v) => `String(${v} ?? '')` : null;
  const fallback = value === 'number' ? '0' : value === 'string' ? "''" : 'undefined';

  const doc = [`/**`, ` * C: \`${cPrototype(sig).slice(0, -1)}\``];
  if (sig.isAsync) doc.push(' * async: can suspend in wgpuInstanceWaitAny; serialized per module.');
  else doc.push(` * whileSuspended: ${sig.whileSuspended}`);
  if (sig.optional) doc.push(' * optional: null when the loaded artifact predates the export (called directly, not via ccall).');
  if (sig.note) doc.push(` * ${sig.note}`);
  doc.push(' */');

  let returnType;
  let body;
  if (sig.isAsync) {
    returnType = `Promise<${value}>`;
    const call = `callAsync(mod, '${sig.name}', ${ret}, ${argTypes}, ${argList})`;
    body = convert ? `return ${call}.then((r) => ${convert('r')});` : `return ${call}.then(() => undefined);`;
  } else {
    returnType = value;
    const call = sig.optional
      ? `callDirect(mod, '${sig.name}', ${ret}, ${argList}, '${sig.whileSuspended}', ${fallback})`
      : `callSync(mod, '${sig.name}', ${ret}, ${argTypes}, ${argList}, '${sig.whileSuspended}', ${fallback})`;
    body = convert ? `return ${convert(call)};` : `${call};`;
  }
  if (sig.optional) {
    returnType = `${returnType} | null`;
    body = `if (!hasExport(mod, '${sig.name}')) return null;\n  ${body}`;
  }
  return `${doc.join('\n')}\nexport function ${sig.name}(${params}): ${returnType} {\n  ${body}\n}\n`;
}

function renderTs(sigs) {
  const asyncList = sigs.filter((s) => s.isAsync).map((s) => `'${s.name}'`);
  const all = sigs.map((s) => `'${s.name}'`);
  return [
    '// GENERATED by scripts/gen-wasm-exports-header.js from',
    '// src/contracts/wasm_exports.json `exports`. Do not edit: change the JSON and',
    '// run `npm run gen:wasm-exports`. The C twin is wasm_renderer/wasm_exports.h.',
    '//',
    '// One typed wrapper per C export. They are the only callers of ccall in the',
    '// bridge: everything goes through the call seam (./call.ts), which awaits',
    '// async exports with { async: true } (both the JSPI and the ASYNCIFY build',
    '// return a Promise from them) and applies each sync export\'s whileSuspended',
    '// policy while one is in flight.',
    "import { callAsync, callDirect, callSync, hasExport } from './call.js';",
    "import type { EmscriptenModule } from './state.js';",
    '',
    '/** A caller-owned address in the module heap (_malloc). */',
    'export type WasmPtr = number;',
    '',
    '/** Exports whose call graph reaches wgpuInstanceWaitAny (= wasm_compile_flags.json jspi.jspiExports). */',
    `export const ASYNC_EXPORTS = [${asyncList.join(', ')}] as const;`,
    '',
    'export type AsyncExport = (typeof ASYNC_EXPORTS)[number];',
    '',
    '/** Every C export the bridge may call (wasm_exports.json `exports`). */',
    'export const EXPORT_NAMES = [',
    ...all.map((n) => `  ${n},`),
    '] as const;',
    '',
    'export type ExportName = (typeof EXPORT_NAMES)[number];',
    '',
    ...sigs.map(tsWrapper),
  ]
    .join('\n')
    .replace(/\n+$/, '\n');
}

// ─── main.cpp parity (no emcc needed) ─────────────────────────────────────────

const C_TYPE_WORDS = new Set(['int', 'float', 'double', 'char', 'bool', 'void', 'long', 'short', 'unsigned', 'signed', 'size_t', 'int8_t', 'uint8_t', 'int16_t', 'uint16_t', 'int32_t', 'uint32_t', 'int64_t', 'uint64_t']);

function stripCppComments(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

/** Map of export name → { returns, args: [cType] } for every EMSCRIPTEN_KEEPALIVE definition. */
function parseKeepaliveSignatures(cppSource) {
  const src = stripCppComments(cppSource);
  const out = new Map();
  const re = /EMSCRIPTEN_KEEPALIVE\s+([A-Za-z_][\w\s\*]*?)\b([A-Za-z_]\w*)\s*\(([^)]*)\)/g;
  let m;
  while ((m = re.exec(src))) {
    const returns = normalizeCType(m[1]);
    const params = m[3].trim();
    const args =
      params === '' || params === 'void'
        ? []
        : params.split(',').map((p) => {
            const t = normalizeCType(p);
            // Drop the parameter name: a trailing identifier that is not part of the type.
            const named = t.match(/^(.*[\s*])([A-Za-z_]\w*)$/);
            return named && !C_TYPE_WORDS.has(named[2]) ? normalizeCType(named[1]) : t;
          });
    out.set(m[2], { returns, args });
  }
  return out;
}

/** Problems between the contract and main.cpp's EMSCRIPTEN_KEEPALIVE definitions. */
function checkCppSignatures(sigs, cppSource) {
  const defs = parseKeepaliveSignatures(cppSource);
  const problems = [];
  for (const sig of sigs) {
    const def = defs.get(sig.name);
    if (!def) {
      problems.push(`${MAIN_CPP_REL} has no EMSCRIPTEN_KEEPALIVE ${sig.name}`);
      continue;
    }
    const want = `${cType(sig.returns)}(${sig.args.map((a) => cType(a.type)).join(', ')})`;
    const have = `${def.returns}(${def.args.join(', ')})`;
    if (want !== have) problems.push(`${MAIN_CPP_REL} ${sig.name} is ${have}; wasm_exports.json says ${want}`);
  }
  for (const name of defs.keys()) {
    if (!sigs.some((s) => s.name === name)) problems.push(`${MAIN_CPP_REL} KEEPALIVE ${name} has no wasm_exports.json exports entry`);
  }
  if (!/#include\s+"wasm_exports\.h"/.test(cppSource)) problems.push(`${MAIN_CPP_REL} must #include "wasm_exports.h"`);
  return problems;
}

function emitAll(contract = loadContract()) {
  const sigs = loadSignatures(contract);
  return { sigs, files: { [HEADER_REL]: renderHeader(sigs), [TS_REL]: renderTs(sigs) } };
}

/** Every problem `--check` reports (stale outputs + main.cpp drift); [] when in sync. */
function collectProblems() {
  let emitted;
  try {
    emitted = emitAll();
  } catch (e) {
    return [e.message];
  }
  const problems = [];
  for (const [rel, want] of Object.entries(emitted.files)) {
    const file = path.join(ROOT, rel);
    const have = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
    if (have !== want) problems.push(`${rel} is stale or missing; run: npm run gen:wasm-exports`);
  }
  const mainCpp = fs.readFileSync(path.join(ROOT, MAIN_CPP_REL), 'utf8');
  problems.push(...checkCppSignatures(emitted.sigs, mainCpp));
  return problems;
}

module.exports = {
  HEADER_REL,
  TS_REL,
  loadContract,
  loadSignatures,
  renderHeader,
  renderTs,
  parseKeepaliveSignatures,
  checkCppSignatures,
  emitAll,
  collectProblems,
};

if (require.main === module) {
  if (process.argv.includes('--check')) {
    const problems = collectProblems();
    if (problems.length) {
      for (const p of problems) console.error(`❌ ${p}`);
      process.exit(1);
    }
    console.log('✅ wasm_exports.h + bridge/_generated.ts match wasm_exports.json; main.cpp signatures agree');
  } else {
    const { files } = emitAll();
    for (const [rel, content] of Object.entries(files)) {
      const file = path.join(ROOT, rel);
      const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
      if (current === content) continue;
      fs.writeFileSync(file, content);
      console.log(`✅ wrote ${rel}`);
    }
  }
}
