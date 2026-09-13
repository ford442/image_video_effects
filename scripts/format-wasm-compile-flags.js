#!/usr/bin/env node
/**
 * Print toolchain pin / compile flags from src/contracts/wasm_compile_flags.json.
 * Usage: node scripts/format-wasm-compile-flags.js [args|emsdk|output]
 *   args   — one em++ argument per line (std, opt, use-port, -s flags)
 *   emsdk  — pinned emsdk/emcc version
 *   output — Emscripten JS output file name
 */
const fs = require('fs');
const path = require('path');

const contract = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', 'src', 'contracts', 'wasm_compile_flags.json'), 'utf8'),
);
const kind = process.argv[2] || 'args';
if (kind === 'args') {
  const args = [
    `-std=${contract.std}`,
    contract.opt,
    `--use-port=${contract.usePort}`,
    ...contract.sFlags.map((f) => `-s${f}`),
  ];
  process.stdout.write(`${args.join('\n')}\n`);
} else if (kind === 'emsdk') {
  process.stdout.write(contract.emsdkVersion);
} else if (kind === 'output') {
  process.stdout.write(contract.jsOutputName);
} else {
  console.error('Usage: format-wasm-compile-flags.js [args|emsdk|output]');
  process.exit(1);
}
