// node --test scripts/verify-shaders.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { GATES, commandFor } from './verify-shaders.mjs';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const CI = fs.readFileSync(path.join(ROOT, '.github/workflows/ci.yml'), 'utf8');

test('every local gate is a step in ci.yml, with the same arguments', () => {
  for (const gate of GATES) {
    const cmd = commandFor(gate, { base: 'origin/main', fix: false });
    assert.ok(CI.includes(`run: ${cmd}\n`), `ci.yml has no step \`run: ${cmd}\` (${gate.name})`);
  }
});

test('every gate script exists', () => {
  for (const gate of GATES) {
    const script = gate.ci.split(' ')[1];
    assert.ok(fs.existsSync(path.join(ROOT, script)), `${script} is missing`);
  }
});

test('--fix is only added to gates that declare a fixer, and CI never runs it', () => {
  const fixed = GATES.filter((g) => commandFor(g, { base: 'origin/main', fix: true }).endsWith(' --fix'));
  assert.deepEqual(fixed.map((g) => g.ci.split(' ')[1]), [
    'scripts/check_prelude_migration.py',
    'scripts/verify-naga-wasm.mjs',
  ]);
  assert.equal(/run: .*(check_prelude_migration|verify-naga-wasm).* --fix/.test(CI), false);
});
