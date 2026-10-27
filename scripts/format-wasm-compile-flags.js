#!/usr/bin/env node
/**
 * Print toolchain pin / compile flags from src/contracts/wasm_compile_flags.json.
 * Usage: node scripts/format-wasm-compile-flags.js [args|emsdk|output|sources|outdir|variants|compdb|compile-commands] [profile] [--asan] [--variant=asyncify|jspi]
 *   args             — one em++ argument per line (std, opt, use-port, -s flags, extraFlags [, -sJSPI_EXPORTS])
 *   outdir           — build output dir of the profile, relative to wasm_renderer/
 *   emsdk            — pinned emsdk/emcc version
 *   output           — Emscripten JS output file name for --variant (default asyncify)
 *   sources          — translation units (relative to wasm_renderer/), one per line
 *   variants         — release build variant names, one per line (build.sh loops over these)
 *   compdb           — write wasm_renderer/compile_commands.json for clangd (gitignored)
 *   compile-commands — alias of compdb (older npm script name)
 *
 * The top-level graph is the ASYNCIFY fallback (variant "asyncify"). The `jspi`
 * graph swaps ASYNCIFY for JSPI and adds -sJSPI_EXPORTS. Profiles (debug / ASan)
 * layer on either variant. build.sh never spells -sASYNCIFY or -sJSPI itself.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const CONTRACT_PATH = path.join(ROOT, 'src', 'contracts', 'wasm_compile_flags.json');
const RENDERER_DIR = path.join(ROOT, 'wasm_renderer');
const COMPDB_PATH = path.join(RENDERER_DIR, 'compile_commands.json');
const DEFAULT_EM_CACHE = '/tmp/emscripten_cache';
const VARIANTS = ['asyncify', 'jspi'];

function loadContract(file = CONTRACT_PATH) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** Resolved { sFlags, jsOutputName, jspiExports } for one async-mode graph. */
function variantGraph(contract, variant) {
  if (variant === 'asyncify') {
    return { sFlags: contract.sFlags, jsOutputName: contract.jsOutputName, jspiExports: [] };
  }
  if (variant === 'jspi') {
    const j = contract.jspi;
    if (!j) throw new Error('wasm_compile_flags.json has no `jspi` graph');
    // Derived from the fallback so the two graphs cannot drift (no jspi.sFlags copy).
    const sFlags = contract.sFlags.map((f) => (f === 'ASYNCIFY' ? 'JSPI' : f));
    return { sFlags, jsOutputName: j.jsOutputName, jspiExports: j.jspiExports || [] };
  }
  throw new Error(`unknown variant "${variant}" (expected ${VARIANTS.join('|')})`);
}

/**
 * Top-level opt / sFlags / extraFlags are the release profile. A named profile
 * overrides `opt` and adds sFlags / extraFlags, minus its dropExtraFlags.
 * `asan` layers profiles.<name>.asan on top.
 */
function resolveProfile(contract, { profile = 'release', asan = false } = {}) {
  const base = {
    opt: contract.opt,
    sFlags: [...contract.sFlags],
    extraFlags: [...(contract.extraFlags || [])],
    outDir: 'build',
  };
  if (profile === 'release') {
    if (asan) throw new Error('--asan needs a profile that defines `asan` (debug)');
    return base;
  }
  const p = (contract.profiles || {})[profile];
  if (!p) {
    throw new Error(`unknown profile '${profile}' (have: release, ${Object.keys(contract.profiles || {}).join(', ')})`);
  }
  const drop = new Set(p.dropExtraFlags || []);
  const out = {
    opt: p.opt || base.opt,
    sFlags: [...base.sFlags, ...(p.sFlags || [])],
    extraFlags: [...base.extraFlags.filter((f) => !drop.has(f)), ...(p.extraFlags || [])],
    outDir: p.outDir || `build/${profile}`,
  };
  if (asan) {
    if (!p.asan) throw new Error(`profile '${profile}' defines no asan flags`);
    const dropS = new Set(p.asan.dropSFlags || []);
    out.sFlags = out.sFlags.filter((f) => !dropS.has(f));
    out.sFlags.push(...(p.asan.sFlags || []));
    out.extraFlags.push(...(p.asan.extraFlags || []));
  }
  return out;
}

function normalizeOptions(options) {
  if (typeof options === 'string') return { variant: options, profile: 'release', asan: false };
  return { variant: 'asyncify', profile: 'release', asan: false, ...(options || {}) };
}

/** The exact em++ flag list build.sh passes (before sources, -I and exports). */
function emccArgs(contract, options) {
  const opts = normalizeOptions(options);
  const g = variantGraph(contract, opts.variant);
  const p = resolveProfile(contract, opts);
  // Profile sFlags are the fallback list plus profile additions. The jspi graph
  // is that list with ASYNCIFY replaced by JSPI (verify:wasm-invariants).
  const sFlags = opts.variant === 'jspi'
    ? p.sFlags.map((f) => (f === 'ASYNCIFY' ? 'JSPI' : f))
    : p.sFlags;
  const args = [
    `-std=${contract.std}`,
    p.opt,
    `--use-port=${contract.usePort}`,
    ...sFlags.map((f) => `-s${f}`),
    ...p.extraFlags,
  ];
  if (g.jspiExports.length > 0) {
    args.push(`-sJSPI_EXPORTS=${g.jspiExports.join(',')}`);
  }
  return args;
}

function portIncludeDir(contract, emCache) {
  return path.join(emCache, 'ports', contract.usePort, `${contract.usePort}_pkg`, 'webgpu', 'include');
}

function parseEmccCflags(text) {
  const tokens = text.trim().split(/\s+/).filter(Boolean);
  const out = [];
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i] === '-mllvm') {
      i++;
      continue;
    }
    out.push(tokens[i]);
  }
  return out;
}

function compileCommands(contract, { cflags, emCache, rendererDir = RENDERER_DIR }) {
  const args = [
    ...cflags,
    ...emccArgs(contract),
    `-I${rendererDir}`,
    `-I${portIncludeDir(contract, emCache)}`,
  ];
  return contract.sources.map((src) => {
    const file = path.join(rendererDir, src);
    return { directory: rendererDir, file, arguments: ['em++', ...args, '-c', file] };
  });
}

function writeCompdb(contract) {
  const emCache = process.env.EM_CACHE || DEFAULT_EM_CACHE;
  let raw;
  try {
    raw = execFileSync('em++', ['--cflags'], {
      encoding: 'utf8',
      env: { ...process.env, EM_CACHE: emCache },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (err) {
    console.error(`❌ em++ --cflags failed (${err.code === 'ENOENT' ? 'em++ not on PATH' : err.message})`);
    console.error('   source <emsdk>/emsdk_env.sh first, then run: npm run wasm:compdb');
    process.exit(1);
  }
  const lines = raw.trim().split('\n');
  const cflags = parseEmccCflags(lines[lines.length - 1]);
  const cmds = compileCommands(contract, { cflags, emCache });
  fs.writeFileSync(COMPDB_PATH, `${JSON.stringify(cmds, null, 2)}\n`);
  console.log(`✅ ${path.relative(ROOT, COMPDB_PATH)} (${cmds.length} TUs, EM_CACHE=${emCache})`);
  const portDir = portIncludeDir(contract, emCache);
  if (!fs.existsSync(path.join(portDir, 'webgpu', 'webgpu.h'))) {
    console.warn(`⚠️  ${portDir} has no webgpu/webgpu.h yet: run \`npm run wasm:build\` once so the port is fetched.`);
  }
}

module.exports = {
  CONTRACT_PATH,
  COMPDB_PATH,
  VARIANTS,
  loadContract,
  variantGraph,
  resolveProfile,
  emccArgs,
  parseEmccCflags,
  compileCommands,
};

if (require.main === module) {
  const argv = process.argv.slice(2);
  const asan = argv.includes('--asan');
  const variantArg = argv.find((a) => a.startsWith('--variant='));
  const variant = variantArg ? variantArg.slice('--variant='.length) : 'asyncify';
  const positional = argv.filter((a) => !a.startsWith('--'));
  const kind = positional[0] || 'args';
  const profile = positional[1] || 'release';
  const contract = loadContract();
  try {
    if (kind === 'args') {
      process.stdout.write(`${emccArgs(contract, { profile, asan, variant }).join('\n')}\n`);
    } else if (kind === 'outdir') {
      process.stdout.write(resolveProfile(contract, { profile, asan }).outDir);
    } else if (kind === 'emsdk') {
      process.stdout.write(contract.emsdkVersion);
    } else if (kind === 'output') {
      process.stdout.write(variantGraph(contract, variant).jsOutputName);
    } else if (kind === 'variants') {
      process.stdout.write(`${VARIANTS.join('\n')}\n`);
    } else if (kind === 'sources') {
      process.stdout.write(`${contract.sources.join('\n')}\n`);
    } else if (kind === 'compdb' || kind === 'compile-commands') {
      writeCompdb(contract);
    } else {
      console.error('Usage: format-wasm-compile-flags.js [args|emsdk|output|sources|outdir|variants|compdb|compile-commands] [profile] [--asan] [--variant=asyncify|jspi]');
      process.exit(1);
    }
  } catch (err) {
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }
}
