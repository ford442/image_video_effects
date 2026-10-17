#!/usr/bin/env node
/**
 * Generate the two files the WASM backend reads its contracts from:
 *
 *   src/wasm/bridge/_generated.ts     typed ccall wrappers, one per export in
 *                                     wasm_exports.json `exports` (async-aware;
 *                                     see src/wasm/bridge/call.ts)
 *   src/wasm/bridge/_contracts.ts     import-free constants (usage bits, dispatch
 *                                     fallback) shared with src/renderer
 *   wasm_renderer/generated/contracts.h  limits, binding table, slot ceiling,
 *                                     uniforms layout and usage bits for C++
 *
 * Inputs: src/contracts/{wasm_exports,webgpu_limits,webgpu_optional_features,
 * binding_table,slot_limits,uniforms_layout,workgroup_dispatch}.json.
 *
 * Usage: node scripts/emit-wasm-contracts.mjs [--check]
 *   --check  exit 1 when either committed file differs from a fresh emit.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CONTRACTS = path.join(ROOT, 'src', 'contracts');
export const GENERATED_TS = path.join(ROOT, 'src', 'wasm', 'bridge', '_generated.ts');
export const GENERATED_CONSTANTS_TS = path.join(ROOT, 'src', 'wasm', 'bridge', '_contracts.ts');
export const GENERATED_H = path.join(ROOT, 'wasm_renderer', 'generated', 'contracts.h');

const readContract = (name) => JSON.parse(fs.readFileSync(path.join(CONTRACTS, name), 'utf8'));

const ARG_TYPES = new Set(['number', 'string', 'pointer']);
const RETURN_TYPES = new Set(['void', 'number', 'string']);
const POLICIES = new Set(['call', 'queue', 'skip']);

/** Parse and validate wasm_exports.json `exports`; throws on a malformed entry. */
export function loadExportSignatures(json = readContract('wasm_exports.json')) {
  const runtimeOnly = new Set(json.runtimeOnlyExports ?? []);
  const listed = json.exportedFunctions.filter((n) => !runtimeOnly.has(n)).map((n) => n.slice(1));
  const names = Object.keys(json.exports ?? {});
  if (JSON.stringify(names) !== JSON.stringify(listed)) {
    const missing = listed.filter((n) => !names.includes(n));
    const extra = names.filter((n) => !listed.includes(n));
    throw new Error(
      `wasm_exports.json exports must list exportedFunctions (minus runtimeOnlyExports) in order; ` +
        `missing [${missing.join(', ')}], extra [${extra.join(', ')}]`,
    );
  }
  return names.map((name) => {
    const e = json.exports[name];
    if (!RETURN_TYPES.has(e.returns)) throw new Error(`${name}: returns must be void|number|string`);
    const args = (e.args ?? []).map((spec) => {
      const [argName, type] = String(spec).split(':');
      if (!/^[A-Za-z_]\w*$/.test(argName ?? '') || !ARG_TYPES.has(type)) {
        throw new Error(`${name}: arg "${spec}" must be "name:number|string|pointer"`);
      }
      return { name: argName, type };
    });
    const isAsync = e.async === true;
    if (isAsync && e.whileSuspended) throw new Error(`${name}: async exports take no whileSuspended`);
    if (!isAsync && !POLICIES.has(e.whileSuspended)) {
      throw new Error(`${name}: sync exports need whileSuspended call|queue|skip`);
    }
    if (e.whileSuspended === 'queue') {
      if (e.returns !== 'void') throw new Error(`${name}: a queued export runs later, so it must return void`);
      if (args.some((a) => a.type === 'pointer')) {
        throw new Error(`${name}: a queued export runs later, so it cannot take a caller-owned pointer`);
      }
    }
    return { name, returns: e.returns, args, isAsync, whileSuspended: e.whileSuspended ?? null, optional: e.optional === true };
  });
}

const ccallType = (t) => (t === 'string' ? "'string'" : "'number'");
const tsType = (t) => (t === 'string' ? 'string' : 'number');

function wrapper(sig) {
  const params = ['mod: EmscriptenModule', ...sig.args.map((a) => `${a.name}: ${tsType(a.type)}`)].join(', ');
  const argTypes = `[${sig.args.map((a) => ccallType(a.type)).join(', ')}]`;
  const argList = `[${sig.args.map((a) => a.name).join(', ')}]`;
  const ret = sig.returns === 'void' ? 'null' : `'${sig.returns}'`;
  const value = sig.returns === 'void' ? 'void' : sig.returns;
  const convert =
    sig.returns === 'number' ? (v) => `Number(${v} ?? 0)` : sig.returns === 'string' ? (v) => `String(${v} ?? '')` : null;
  const fallback = sig.returns === 'number' ? '0' : sig.returns === 'string' ? "''" : 'undefined';
  const doc = [`/** ${sig.name}(${sig.args.map((a) => `${a.name}: ${a.type}`).join(', ')}) → ${sig.returns}`];
  if (sig.isAsync) doc.push(' * async: can suspend in wgpuInstanceWaitAny; serialized per module.');
  else doc.push(` * whileSuspended: ${sig.whileSuspended}`);
  if (sig.optional) doc.push(' * optional: null when the loaded artifact predates the export.');
  doc.push(' */');

  let body;
  let returnType;
  if (sig.isAsync) {
    returnType = `Promise<${value}>`;
    const call = `callAsync(mod, '${sig.name}', ${ret}, ${argTypes}, ${argList})`;
    body = convert ? `return ${call}.then((r) => ${convert('r')});` : `return ${call}.then(() => undefined);`;
  } else {
    returnType = value;
    const call = `callSync(mod, '${sig.name}', ${ret}, ${argTypes}, ${argList}, '${sig.whileSuspended}', ${fallback})`;
    body = convert ? `const r = ${call};\n  return ${convert('r')};` : `${call};`;
  }
  if (sig.optional) {
    returnType = `${returnType} | null`;
    body = `if (!hasExport(mod, '${sig.name}')) return null;\n  ${body}`;
  }
  return `${doc.join('\n')}\nexport function ${sig.name}(${params}): ${returnType} {\n  ${body}\n}\n`;
}

export function renderTs(sigs) {
  const lines = [
    '// GENERATED by scripts/emit-wasm-contracts.mjs from src/contracts/wasm_exports.json.',
    '// Do not edit: npm run wasm:contracts.',
    '/* eslint-disable */',
    "import { callAsync, callSync, hasExport } from './call.js';",
    "import type { EmscriptenModule } from './state.js';",
    '',
    '/** Exports that can suspend in wgpuInstanceWaitAny (called with { async: true }). */',
    `export const ASYNC_EXPORTS = [${sigs.filter((s) => s.isAsync).map((s) => `'${s.name}'`).join(', ')}] as const;`,
    '',
  ];
  for (const sig of sigs) lines.push(wrapper(sig));
  return `${lines.join('\n').trimEnd()}\n`;
}

/** Constants with no imports, so src/renderer can share them without the bridge. */
export function renderConstantsTs(bindingTable, workgroup) {
  const flags = bindingTable.shaderUsageFlags.flags;
  return [
    '// GENERATED by scripts/emit-wasm-contracts.mjs from src/contracts/binding_table.json',
    '// and workgroup_dispatch.json. Do not edit: npm run wasm:contracts.',
    '',
    '/** loadShader bindingUsage bits (binding_table.json shaderUsageFlags). */',
    'export const SHADER_USAGE_BITS = {',
    ...flags.map((f) => `  ${f.name}: ${f.bit},`),
    '} as const;',
    '',
    '/** @binding of each usage flag (binding_table.json shaderUsageFlags). */',
    'export const SHADER_USAGE_BINDINGS = {',
    ...flags.map((f) => `  ${f.name}: ${f.binding},`),
    '} as const;',
    '',
    '/** Dispatch size when @workgroup_size cannot be resolved (workgroup_dispatch.json). */',
    `export const WORKGROUP_UNPARSED_FALLBACK = { x: ${workgroup.unparsedFallback.x}, y: ${workgroup.unparsedFallback.y} } as const;`,
    '',
  ].join('\n');
}

const pascal = (s) => s.charAt(0).toUpperCase() + s.slice(1);

/** Per-stage resource counts the binding table implies (the WebGPU limit each one is checked against). */
export function bindingStageCounts(bindingTable) {
  const count = (kinds) => bindingTable.bindings.filter((b) => kinds.includes(b.kind)).length;
  return {
    maxBindingsPerBindGroup: bindingTable.bindings.length,
    maxSampledTexturesPerShaderStage: count(['sampledRgba', 'sampledRgbaArray', 'sampledR32']),
    maxSamplersPerShaderStage: count(['filteringSampler', 'nonFilteringSampler', 'comparisonSampler']),
    maxStorageTexturesPerShaderStage: count(['storageRgba', 'storageR32']),
    maxStorageBuffersPerShaderStage: count(['storageBuffer', 'readOnlyStorageBuffer']),
    maxUniformBuffersPerShaderStage: count(['uniformBuffer']),
  };
}

/** Throws when the binding table needs more than webgpu_limits.json requests. */
export function checkLimitsCoverBindings(limits, bindingTable) {
  const counts = bindingStageCounts(bindingTable);
  const short = Object.entries(counts).filter(([k, n]) => (limits.minimumComputeLimits[k] ?? 0) < n);
  if (short.length) {
    throw new Error(
      'webgpu_limits.json minimumComputeLimits is below what binding_table.json declares: ' +
        short.map(([k, n]) => `${k} ${limits.minimumComputeLimits[k]} < ${n}`).join(', '),
    );
  }
  bindingTable.bindings.forEach((b, i) => {
    if (b.binding !== i) throw new Error(`binding_table.json bindings must be dense 0..N in order (index ${i} is ${b.binding})`);
    if (!bindingTable.kinds[b.kind]) throw new Error(`binding_table.json binding ${b.binding}: unknown kind ${b.kind}`);
  });
  return counts;
}

export function renderHeader({ limits, features, bindingTable, slots, uniforms, workgroup }) {
  const counts = checkLimitsCoverBindings(limits, bindingTable);
  const resources = [...new Set(bindingTable.bindings.map((b) => b.resource))];
  const kinds = Object.keys(bindingTable.kinds);
  const xList = (macro, entries) =>
    [`#define ${macro}(X) \\`, ...entries.map((e, i) => `    X(${e})${i < entries.length - 1 ? ' \\' : ''}`)].join('\n');
  const featureOrder = features.requestOrder.map((name) => {
    const cppName = name === 'subgroups' ? features.subgroupPreference.find((v) => v === 'subgroups') : name;
    const en = features.cppEnums[cppName];
    if (!en) throw new Error(`webgpu_optional_features.json cppEnums has no entry for ${cppName}`);
    return `${en}, "${name}"`;
  });
  const minLimits = Object.entries(limits.minimumComputeLimits);
  const deep = Object.entries(limits.deepWorkgroupLimits);
  const L = [
    '// GENERATED by scripts/emit-wasm-contracts.mjs from src/contracts/*.json.',
    '// Do not edit: change the JSON and run `npm run wasm:contracts` (CI diffs this file).',
    '#pragma once',
    '',
    '#include <webgpu/webgpu.h>',
    '#include <cstddef>',
    '#include <cstdint>',
    '',
    'namespace pixelocity::contracts {',
    '',
    '// ── webgpu_limits.json minimumComputeLimits ── X(WGPULimits field, floor)',
    '// Checked on the adapter, requested on the device, re-checked on the device.',
    xList('PIXELOCITY_MIN_COMPUTE_LIMITS', minLimits.map(([k, v]) => `${k}, ${v}u`)),
    '',
    '// ── webgpu_limits.json deepWorkgroupLimits ── requested only when the adapter offers all of them.',
    xList('PIXELOCITY_DEEP_WORKGROUP_LIMITS', deep.map(([k, v]) => `${k}, ${v}u`)),
    '',
    '// ── webgpu_optional_features.json requestOrder ── X(WGPUFeatureName, name), in request order.',
    xList('PIXELOCITY_OPTIONAL_FEATURES', featureOrder),
    `constexpr size_t kOptionalFeatureCount = ${featureOrder.length};`,
    '',
    '// ── slot_limits.json ──',
    `constexpr int kMaxPhysicalSlots = ${slots.maxPhysicalSlots};`,
    '',
    '// ── uniforms_layout.json ──',
    `constexpr size_t kUniformsSizeBytes = ${uniforms.totalSizeBytes};`,
    `constexpr int kMaxRipples = ${uniforms.maxRipples};`,
    ...uniforms.fields.map((f) => `constexpr size_t kUniformsOffset_${f.name} = ${f.offset};`),
    '',
    '// ── workgroup_dispatch.json ── dispatch size the bridge sends when @workgroup_size is unresolved.',
    `constexpr uint32_t kWorkgroupFallbackX = ${workgroup.unparsedFallback.x}u;`,
    `constexpr uint32_t kWorkgroupFallbackY = ${workgroup.unparsedFallback.y}u;`,
    '',
    '// ── binding_table.json ── the @group(0) compute bind group.',
    'enum class BindingKind : uint8_t {',
    ...kinds.map((k) => `    ${pascal(k)},  // ${bindingTable.kinds[k]}`),
    '};',
    '',
    '// Which renderer object fills the binding. Input/Output are per pass (the',
    "// slot's read/write textures); everything else is a shared global.",
    'enum class BindingResource : uint8_t {',
    ...resources.map((r) => `    ${pascal(r)},`),
    '};',
    '',
    'struct ComputeBinding {',
    '    uint32_t binding;',
    '    BindingKind kind;',
    '    BindingResource resource;',
    '};',
    '',
    'constexpr ComputeBinding kComputeBindings[] = {',
    ...bindingTable.bindings.map(
      (b) => `    { ${String(b.binding).padStart(2)}, BindingKind::${pascal(b.kind)}, BindingResource::${pascal(b.resource)} },  // ${b.wgslName}`,
    ),
    '};',
    `constexpr size_t kComputeBindingCount = ${bindingTable.bindings.length};`,
    '',
    '// Per-stage counts the table implies; the generator fails when a limit floor is lower.',
    ...Object.entries(counts).map(([k, n]) => `constexpr uint32_t kBindings_${k} = ${n}u;`),
    '',
    '// ── binding_table.json shaderUsageFlags ── loadShader bindingUsage bits.',
    ...bindingTable.shaderUsageFlags.flags.map((f) => `constexpr uint32_t kUsage${pascal(f.name)} = ${f.bit}u;  // binding ${f.binding}`),
    '',
    '}  // namespace pixelocity::contracts',
  ];
  return `${L.join('\n')}\n`;
}

export function emitAll() {
  const sigs = loadExportSignatures();
  const bindingTable = readContract('binding_table.json');
  const workgroup = readContract('workgroup_dispatch.json');
  return {
    [GENERATED_TS]: renderTs(sigs),
    [GENERATED_CONSTANTS_TS]: renderConstantsTs(bindingTable, workgroup),
    [GENERATED_H]: renderHeader({
      limits: readContract('webgpu_limits.json'),
      features: readContract('webgpu_optional_features.json'),
      bindingTable,
      slots: readContract('slot_limits.json'),
      uniforms: readContract('uniforms_layout.json'),
      workgroup,
    }),
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const check = process.argv.includes('--check');
  const files = emitAll();
  let stale = 0;
  for (const [file, content] of Object.entries(files)) {
    const rel = path.relative(ROOT, file);
    const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
    if (current === content) continue;
    if (check) {
      console.error(`❌ ${rel} is stale; run npm run wasm:contracts`);
      stale++;
    } else {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, content);
      console.log(`✅ wrote ${rel}`);
    }
  }
  if (stale) process.exit(1);
  if (check) console.log('✅ WASM generated contracts are current');
}
