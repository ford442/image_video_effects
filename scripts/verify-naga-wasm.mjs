#!/usr/bin/env node
/**
 * verify-naga-wasm.mjs
 *
 * GPU-less WGSL validation for the catalog, using the committed
 * public/wasm/naga_wasm.wasm (tools/naga_wasm) instead of a host `naga` binary.
 * Same naga minor the CLI gate used, so diagnostics are identical — but it runs
 * in-process, which makes a full-catalog scan affordable (~6 s for 1400 files)
 * where spawning `naga` per file was not.
 *
 * scripts/wgsl_precommit_gate.py keeps the workgroup / bindgroup / extraBuffer
 * checks; this script owns naga validation.
 *
 * Usage:
 *   node scripts/verify-naga-wasm.mjs                    # files changed vs origin/main
 *   node scripts/verify-naga-wasm.mjs --all              # whole catalog (ratcheted)
 *   node scripts/verify-naga-wasm.mjs --files a.wgsl b.wgsl
 *   node scripts/verify-naga-wasm.mjs --base-ref origin/develop
 *   node scripts/verify-naga-wasm.mjs --all --report     # also write reports/naga_wasm_validation.json
 */

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_CONTRACT = path.join(ROOT, 'src/contracts/wgsl_validation.json');
const SHADER_DIR = path.join(ROOT, 'public/shaders');

let failed = false;
const fail = (msg) => {
  console.error(msg);
  failed = true;
};

function parseArgs(argv) {
  const args = { all: false, report: false, baseRef: 'origin/main', files: null, contract: DEFAULT_CONTRACT };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--all') args.all = true;
    else if (a === '--report') args.report = true;
    else if (a === '--base-ref') args.baseRef = argv[++i];
    else if (a.startsWith('--base-ref=')) args.baseRef = a.slice('--base-ref='.length);
    else if (a === '--contract') args.contract = path.resolve(argv[++i]);
    else if (a.startsWith('--contract=')) args.contract = path.resolve(a.slice('--contract='.length));
    else if (a === '--files') {
      args.files = [];
      while (i + 1 < argv.length && !argv[i + 1].startsWith('--')) args.files.push(argv[++i]);
    } else if (a === '--help' || a === '-h') {
      args.help = true;
    } else {
      throw new Error(`unknown argument: ${a}`);
    }
  }
  return args;
}

/** Catalog ids, i.e. every .wgsl under public/shaders (flat, templates included). */
function allShaderFiles() {
  return fs
    .readdirSync(SHADER_DIR)
    .filter((f) => f.endsWith('.wgsl'))
    .sort()
    .map((f) => path.join(SHADER_DIR, f));
}

function changedShaderFiles(baseRef) {
  let out;
  try {
    out = execFileSync('git', ['diff', '--name-only', '--diff-filter=ACMR', `${baseRef}...HEAD`], {
      cwd: ROOT,
      encoding: 'utf8',
    });
  } catch {
    console.warn(`⚠️  could not diff against ${baseRef}; falling back to the working tree`);
    out = execFileSync('git', ['diff', '--name-only', '--diff-filter=ACMR', 'HEAD'], {
      cwd: ROOT,
      encoding: 'utf8',
    });
  }
  return out
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('public/shaders/') && l.endsWith('.wgsl'))
    .map((l) => path.join(ROOT, l))
    .filter((p) => fs.existsSync(p));
}

const shaderId = (file) => path.basename(file, '.wgsl');

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(2, 22).join('\n'));
    return;
  }

  const contract = JSON.parse(fs.readFileSync(args.contract, 'utf8'));

  const wasmPath = path.join(ROOT, contract.artifact);
  if (!fs.existsSync(wasmPath)) {
    fail(`❌ ${contract.artifact} is missing. Rebuild it with: bash ${contract.crate}/build.sh`);
    process.exit(1);
  }

  const loaderUrl = pathToFileURL(path.join(ROOT, contract.loader)).href;
  const { createNagaValidator } = await import(loaderUrl);
  const { validate } = await createNagaValidator({ bytes: fs.readFileSync(wasmPath) });

  const knownFailures = new Set(contract.knownFailures.ids);
  if (contract.knownFailures.ratchet !== contract.knownFailures.ids.length) {
    fail(
      `❌ wgsl_validation.json knownFailures.ratchet is ${contract.knownFailures.ratchet} ` +
        `but ids lists ${contract.knownFailures.ids.length} entries — they must match.`,
    );
  }

  let files;
  if (args.files) files = args.files.map((f) => path.resolve(ROOT, f));
  else if (args.all) files = allShaderFiles();
  else files = changedShaderFiles(args.baseRef);

  if (files.length === 0) {
    console.log('naga-wasm: no WGSL files to validate.');
    process.exit(failed ? 1 : 0);
  }

  const started = Date.now();
  const results = [];
  for (const file of files) {
    const source = fs.readFileSync(file, 'utf8');
    const diag = validate(source);
    results.push({ id: shaderId(file), file: path.relative(ROOT, file), ...diag });
  }
  const elapsedMs = Date.now() - started;

  const failures = results.filter((r) => !r.ok);
  const newFailures = failures.filter((r) => !knownFailures.has(r.id));
  const expectedFailures = failures.filter((r) => knownFailures.has(r.id));

  // Only a scan that covered the whole known-failure set can prove an id is fixed.
  const scanned = new Set(results.map((r) => r.id));
  const nowPassing = [...knownFailures].filter(
    (id) => scanned.has(id) && !failures.some((f) => f.id === id),
  );

  console.log(
    `naga-wasm (${contract.nagaCratePin}): ${results.length} file(s) in ${elapsedMs}ms — ` +
      `${results.length - failures.length} valid, ${failures.length} invalid ` +
      `(${expectedFailures.length} known, ${newFailures.length} new)`,
  );

  for (const r of newFailures) {
    fail(`\n❌ ${r.file}\n${r.message.trimEnd()}`);
  }

  if (nowPassing.length > 0) {
    fail(
      `\n❌ ${nowPassing.length} shader(s) now pass naga but are still listed in ` +
        `src/contracts/wgsl_validation.json knownFailures.ids. Remove them and lower ` +
        `ratchet to ${knownFailures.size - nowPassing.length}:\n  ${nowPassing.join('\n  ')}`,
    );
  }

  if (expectedFailures.length > 0 && newFailures.length === 0 && nowPassing.length === 0) {
    console.log(
      `\n⚠️  ${expectedFailures.length} known-bad shader(s) still failing (ratcheted, not blocking):`,
    );
    for (const r of expectedFailures) {
      console.log(`   ${r.id}: ${firstErrorLine(r.message)}`);
    }
  }

  if (args.report) {
    const reportPath = path.join(ROOT, 'reports/naga_wasm_validation.json');
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(
      reportPath,
      `${JSON.stringify(
        {
          nagaCratePin: contract.nagaCratePin,
          generatedAt: new Date().toISOString().slice(0, 10),
          total: results.length,
          valid: results.length - failures.length,
          invalid: failures.length,
          known: expectedFailures.length,
          new: newFailures.length,
          failures: failures.map((r) => ({ id: r.id, kind: r.kind, line: r.line, error: firstErrorLine(r.message) })),
        },
        null,
        2,
      )}\n`,
    );
    console.log(`\nWrote reports/naga_wasm_validation.json`);
  }

  if (failed) process.exit(1);
  console.log('\n✓ naga-wasm validation passed');
}

function firstErrorLine(message = '') {
  const line = message.split('\n').find((l) => l.startsWith('error:')) ?? message.split('\n')[0] ?? '';
  return line.replace(/^error:\s*/, '').trim();
}

main().catch((err) => {
  console.error(`❌ ${err.message}`);
  process.exit(1);
});
