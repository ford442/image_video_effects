#!/usr/bin/env node
/**
 * Print toolchain pin / compile flags from src/contracts/wasm_compile_flags.json.
 * Usage: node scripts/format-wasm-compile-flags.js [args|emsdk|output|variants] [--variant=asyncify|jspi]
 *   args     — one em++ argument per line (std, opt, use-port, -s flags [, -sJSPI_EXPORTS])
 *   emsdk    — pinned emsdk/emcc version
 *   output   — Emscripten JS output file name for the variant
 *   variants — build variant names, one per line (build.sh loops over these)
 *
 * The top-level graph is the ASYNCIFY fallback (variant "asyncify", default).
 * The `jspi` graph is the JSPI primary. build.sh / CMake / CI must never
 * spell -sASYNCIFY or -sJSPI themselves (verify:wasm-invariants).
 */
const fs = require('fs');
const path = require('path');

const CONTRACT_PATH = path.join(__dirname, '..', 'src', 'contracts', 'wasm_compile_flags.json');
const VARIANTS = ['asyncify', 'jspi'];

function loadContract(file = CONTRACT_PATH) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** Resolved { sFlags, jsOutputName, jspiExports } for one variant. */
function variantGraph(contract, variant) {
  if (variant === 'asyncify') {
    return { sFlags: contract.sFlags, jsOutputName: contract.jsOutputName, jspiExports: [] };
  }
  if (variant === 'jspi') {
    const j = contract.jspi;
    if (!j) throw new Error('wasm_compile_flags.json has no `jspi` graph');
    return { sFlags: j.sFlags, jsOutputName: j.jsOutputName, jspiExports: j.jspiExports };
  }
  throw new Error(`unknown variant "${variant}" (expected ${VARIANTS.join('|')})`);
}

function emccArgs(contract, variant) {
  const g = variantGraph(contract, variant);
  const args = [
    `-std=${contract.std}`,
    contract.opt,
    `--use-port=${contract.usePort}`,
    ...g.sFlags.map((f) => `-s${f}`),
  ];
  if (g.jspiExports.length > 0) {
    args.push(`-sJSPI_EXPORTS=${g.jspiExports.join(',')}`);
  }
  return args;
}

module.exports = { CONTRACT_PATH, VARIANTS, loadContract, variantGraph, emccArgs };

if (require.main === module) {
  const kind = process.argv[2] || 'args';
  const variantArg = process.argv.find((a) => a.startsWith('--variant='));
  const variant = variantArg ? variantArg.slice('--variant='.length) : 'asyncify';
  const contract = loadContract();
  try {
    if (kind === 'args') {
      process.stdout.write(`${emccArgs(contract, variant).join('\n')}\n`);
    } else if (kind === 'emsdk') {
      process.stdout.write(contract.emsdkVersion);
    } else if (kind === 'output') {
      process.stdout.write(variantGraph(contract, variant).jsOutputName);
    } else if (kind === 'variants') {
      process.stdout.write(`${VARIANTS.join('\n')}\n`);
    } else {
      console.error('Usage: format-wasm-compile-flags.js [args|emsdk|output|variants] [--variant=asyncify|jspi]');
      process.exit(1);
    }
  } catch (err) {
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }
}
