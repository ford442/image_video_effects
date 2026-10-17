#!/usr/bin/env node
/**
 * The exports that can suspend must be exactly the `async` exports in
 * src/contracts/wasm_exports.json. Emscripten decides that, not the contract:
 * the release build links with -sASYNCIFY_ADVISE (it does not change the
 * binary), and this reads its report.
 *
 * An export suspends when a chain of direct calls reaches wgpuInstanceWaitAny
 * (emdawn's emwgpuWaitAny import). Functions that ADVISE flags only because they
 * contain an indirect call ("due to initial scan") are not suspend points: no
 * callback or virtual call in this renderer reaches WaitAny.
 *
 * Usage: node scripts/check-asyncify-exports.mjs <advise-output.txt> [--write-only-list <file>]
 *   --write-only-list  also write those functions, one per line, for
 *                      -sASYNCIFY_ONLY=@<file> (build.sh's second link pass).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadExportSignatures } from './emit-wasm-contracts.mjs';

const WAIT_IMPORTS = ['wgpuInstanceWaitAny', 'emwgpuWaitAny'];

/** Functions with a direct-call path to a WaitAny import, from ASYNCIFY_ADVISE output. */
export function suspendingFunctions(adviseText) {
  const callers = new Map();
  for (const part of adviseText.split(/\[asyncify\]\s*/)) {
    const m = /^([\s\S]*?) can change the state due to ([\s\S]*?)\s*$/.exec(part.trim());
    if (!m || m[2] === 'initial scan') continue;
    const [, caller, callee] = m;
    if (!callers.has(callee)) callers.set(callee, new Set());
    callers.get(callee).add(caller.trim());
  }
  const seen = new Set(WAIT_IMPORTS);
  const queue = [...WAIT_IMPORTS];
  while (queue.length) {
    for (const caller of callers.get(queue.pop()) ?? []) {
      if (!seen.has(caller)) {
        seen.add(caller);
        queue.push(caller);
      }
    }
  }
  return seen;
}

export function checkAsyncifyExports(adviseText, signatures = loadExportSignatures()) {
  if (!/emwgpuWaitAny is an import that can change the state/.test(adviseText)) {
    return ['ASYNCIFY_ADVISE output does not mention emwgpuWaitAny; was the build linked with -sASYNCIFY_ADVISE?'];
  }
  const suspending = suspendingFunctions(adviseText);
  const errors = [];
  for (const sig of signatures) {
    const reaches = suspending.has(sig.name);
    if (reaches && !sig.isAsync) {
      errors.push(`${sig.name} can suspend in wgpuInstanceWaitAny but wasm_exports.json does not mark it async`);
    } else if (!reaches && sig.isAsync) {
      errors.push(`${sig.name} is async in wasm_exports.json but no longer reaches wgpuInstanceWaitAny (drop async)`);
    }
  }
  return errors;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const file = process.argv[2];
  if (!file) {
    console.error('Usage: node scripts/check-asyncify-exports.mjs <advise-output.txt>');
    process.exit(2);
  }
  const advise = fs.readFileSync(file, 'utf8');
  const errors = checkAsyncifyExports(advise);
  if (errors.length) {
    console.error('❌ Suspending exports drifted from wasm_exports.json:');
    for (const e of errors) console.error(`   ${e}`);
    process.exit(1);
  }
  const listIdx = process.argv.indexOf('--write-only-list');
  if (listIdx > 0) {
    const out = process.argv[listIdx + 1];
    const names = [...suspendingFunctions(advise)].filter((n) => n !== 'emwgpuWaitAny').sort();
    fs.writeFileSync(out, `${names.join('\n')}\n`);
    console.log(`   ASYNCIFY_ONLY list: ${names.length} functions → ${path.relative(process.cwd(), out)}`);
  }
  const n = loadExportSignatures().filter((s) => s.isAsync).length;
  console.log(`✅ ASYNCIFY: exactly the ${n} async exports in wasm_exports.json can suspend`);
}
