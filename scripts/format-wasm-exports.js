#!/usr/bin/env node
/**
 * Print comma-joined WASM export lists from src/contracts/wasm_exports.json.
 * Usage: node scripts/format-wasm-exports.js [functions|runtime]
 */
const fs = require('fs');
const path = require('path');

const contract = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', 'src', 'contracts', 'wasm_exports.json'), 'utf8'),
);
const kind = process.argv[2] || 'functions';
if (kind === 'runtime') {
  process.stdout.write(contract.exportedRuntimeMethods.join(','));
} else if (kind === 'functions') {
  process.stdout.write(contract.exportedFunctions.join(','));
} else {
  console.error('Usage: format-wasm-exports.js [functions|runtime]');
  process.exit(1);
}
