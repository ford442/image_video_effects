#!/usr/bin/env node
/**
 * Print toolchain pin / compile flags from src/contracts/wasm_compile_flags.json.
 * Usage: node scripts/format-wasm-compile-flags.js [args|emsdk|output|sources|compdb]
 *   args    — one em++ argument per line (std, opt, use-port, -s flags, extraFlags)
 *   emsdk   — pinned emsdk/emcc version
 *   output  — Emscripten JS output file name
 *   sources — translation units (relative to wasm_renderer/), one per line
 *   compdb  — write wasm_renderer/compile_commands.json for clangd (gitignored;
 *             needs em++ on PATH). IDE index only: build.sh stays the one build.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const CONTRACT_PATH = path.join(ROOT, 'src', 'contracts', 'wasm_compile_flags.json');
const RENDERER_DIR = path.join(ROOT, 'wasm_renderer');
const COMPDB_PATH = path.join(RENDERER_DIR, 'compile_commands.json');
// Same default as build.sh (export EM_CACHE=/tmp/emscripten_cache).
const DEFAULT_EM_CACHE = '/tmp/emscripten_cache';

function loadContract(file = CONTRACT_PATH) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** The exact em++ flag list build.sh passes (before sources, -I and exports). */
function emccArgs(contract) {
  return [
    `-std=${contract.std}`,
    contract.opt,
    `--use-port=${contract.usePort}`,
    ...contract.sFlags.map((f) => `-s${f}`),
    ...(contract.extraFlags || []),
  ];
}

/** Header dir of the emdawnwebgpu port inside EM_CACHE (populated by the first wasm:build). */
function portIncludeDir(contract, emCache) {
  return path.join(emCache, 'ports', contract.usePort, `${contract.usePort}_pkg`, 'webgpu', 'include');
}

/**
 * `em++ --cflags` is what em++ adds when it drives clang: the wasm32 target, the
 * EM_CACHE sysroot and the compat include. clangd does not run em++, so without
 * these it indexes the TUs as host code. -mllvm pairs are codegen-only.
 */
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

/**
 * One entry per TU with build.sh's full flag list. The --use-port / -s settings
 * mean nothing to clang; wasm_renderer/.clangd removes them before indexing.
 */
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
  // em++ may print sanity-check INFO lines first; the flags are the last line.
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
  loadContract,
  emccArgs,
  parseEmccCflags,
  compileCommands,
};

if (require.main === module) {
  const kind = process.argv[2] || 'args';
  const contract = loadContract();
  if (kind === 'args') {
    process.stdout.write(`${emccArgs(contract).join('\n')}\n`);
  } else if (kind === 'emsdk') {
    process.stdout.write(contract.emsdkVersion);
  } else if (kind === 'output') {
    process.stdout.write(contract.jsOutputName);
  } else if (kind === 'sources') {
    process.stdout.write(`${contract.sources.join('\n')}\n`);
  } else if (kind === 'compdb') {
    writeCompdb(contract);
  } else {
    console.error('Usage: format-wasm-compile-flags.js [args|emsdk|output|sources|compdb]');
    process.exit(1);
  }
}
