#!/usr/bin/env node
/**
 * Tests for scripts/verify-naga-wasm.mjs and the naga_wasm ABI.
 *
 * Run: node --test scripts/verify-naga-wasm.test.mjs
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const CONTRACT = JSON.parse(fs.readFileSync(path.join(ROOT, 'src/contracts/wgsl_validation.json'), 'utf8'));
const SCRIPT = path.join(ROOT, 'scripts/verify-naga-wasm.mjs');

const VALID_WGSL = `
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(1.0, 0.0, 0.0, 1.0));
}
`;

/** Runs the gate and returns { status, stdout } without throwing on exit 1. */
function runGate(args) {
  try {
    const stdout = execFileSync('node', [SCRIPT, ...args], { cwd: ROOT, encoding: 'utf8', stdio: 'pipe' });
    return { status: 0, stdout };
  } catch (err) {
    return { status: err.status, stdout: `${err.stdout ?? ''}${err.stderr ?? ''}` };
  }
}

function withTempDir(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'naga-wasm-test-'));
  try {
    return fn(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

/** A copy of the real contract with knownFailures swapped out. */
function contractWith(dir, ids) {
  const clone = { ...CONTRACT, knownFailures: { ...CONTRACT.knownFailures, ids, ratchet: ids.length } };
  const file = path.join(dir, 'contract.json');
  fs.writeFileSync(file, JSON.stringify(clone, null, 2));
  return file;
}

test('the committed artifact exists and is a real wasm module', () => {
  const wasm = fs.readFileSync(path.join(ROOT, CONTRACT.artifact));
  assert.ok(wasm.length > 400 * 1024, `artifact is only ${wasm.length} bytes — looks like a stub`);
  assert.deepEqual([...wasm.subarray(0, 4)], [0x00, 0x61, 0x73, 0x6d], 'missing \\0asm magic');
});

test('Cargo.toml naga pin matches the contract', () => {
  const toml = fs.readFileSync(path.join(ROOT, CONTRACT.crate, 'Cargo.toml'), 'utf8');
  const pinned = toml.match(/naga\s*=\s*\{\s*version\s*=\s*"([^"]+)"/);
  assert.ok(pinned, 'no pinned naga dependency in Cargo.toml');
  assert.equal(pinned[1], CONTRACT.nagaCratePin);
});

test('knownFailures.ratchet equals the number of listed ids', () => {
  assert.equal(CONTRACT.knownFailures.ratchet, CONTRACT.knownFailures.ids.length);
});

test('knownFailures ids are sorted and unique', () => {
  const ids = CONTRACT.knownFailures.ids;
  assert.deepEqual(ids, [...new Set(ids)], 'duplicate ids');
  assert.deepEqual(ids, [...ids].sort(), 'ids must be sorted so diffs stay readable');
});

test('every knownFailure id names a file that exists', () => {
  for (const id of CONTRACT.knownFailures.ids) {
    const file = path.join(ROOT, 'public/shaders', `${id}.wgsl`);
    assert.ok(fs.existsSync(file), `knownFailures lists ${id} but ${file} does not exist`);
  }
});

test('ABI: valid WGSL returns ok, invalid returns a placed diagnostic', async () => {
  const { createNagaValidator } = await import(pathToFileURL(path.join(ROOT, CONTRACT.loader)).href);
  const { validate } = await createNagaValidator({
    bytes: fs.readFileSync(path.join(ROOT, CONTRACT.artifact)),
  });

  assert.deepEqual(validate(VALID_WGSL), { ok: true });

  const bad = validate('@compute @workgroup_size(1,1,1) fn main() { let x: i32 = 1.5; }');
  assert.equal(bad.ok, false);
  assert.equal(bad.kind, 'parse');
  assert.match(bad.message, /expected to be `i32`/);
  assert.equal(bad.line, 1);
  assert.ok(bad.pos > 0, 'expected a column position');
});

test('ABI: the result buffer is not reused across calls', async () => {
  const { createNagaValidator } = await import(pathToFileURL(path.join(ROOT, CONTRACT.loader)).href);
  const { validate } = await createNagaValidator({
    bytes: fs.readFileSync(path.join(ROOT, CONTRACT.artifact)),
  });
  const first = validate('fn main() { let a: i32 = 1.5; }');
  const second = validate(VALID_WGSL);
  // `first` must still hold its own message after a second call overwrote the buffer.
  assert.equal(first.ok, false);
  assert.match(first.message, /i32/);
  assert.deepEqual(second, { ok: true });
});

test('ABI: survives a source large enough to grow the heap', async () => {
  const { createNagaValidator } = await import(pathToFileURL(path.join(ROOT, CONTRACT.loader)).href);
  const { validate } = await createNagaValidator({
    bytes: fs.readFileSync(path.join(ROOT, CONTRACT.artifact)),
  });
  const padding = `// ${'x'.repeat(64)}\n`.repeat(20000); // ~1.3 MB of comments
  assert.deepEqual(validate(padding + VALID_WGSL), { ok: true });
});

test('ABI: non-ASCII source is measured in bytes, not UTF-16 units', async () => {
  const { createNagaValidator } = await import(pathToFileURL(path.join(ROOT, CONTRACT.loader)).href);
  const { validate } = await createNagaValidator({
    bytes: fs.readFileSync(path.join(ROOT, CONTRACT.artifact)),
  });
  // The catalog's banner comments are full of box-drawing characters.
  assert.deepEqual(validate(`// ═══ emoji 🎨 ═══\n${VALID_WGSL}`), { ok: true });
});

test('gate passes on a valid shader', () => {
  withTempDir((dir) => {
    const file = path.join(dir, 'zz-good.wgsl');
    fs.writeFileSync(file, VALID_WGSL);
    const { status, stdout } = runGate(['--contract', contractWith(dir, []), '--files', file]);
    assert.equal(status, 0, stdout);
    assert.match(stdout, /naga-wasm validation passed/);
  });
});

test('gate fails on an unlisted invalid shader', () => {
  withTempDir((dir) => {
    const file = path.join(dir, 'zz-bad.wgsl');
    fs.writeFileSync(file, '@compute @workgroup_size(1,1,1) fn main() { let x: i32 = 1.5; }');
    const { status, stdout } = runGate(['--contract', contractWith(dir, []), '--files', file]);
    assert.equal(status, 1, stdout);
    assert.match(stdout, /1 new/);
  });
});

test('gate tolerates a listed invalid shader but reports it', () => {
  withTempDir((dir) => {
    const file = path.join(dir, 'zz-bad.wgsl');
    fs.writeFileSync(file, '@compute @workgroup_size(1,1,1) fn main() { let x: i32 = 1.5; }');
    const { status, stdout } = runGate(['--contract', contractWith(dir, ['zz-bad']), '--files', file]);
    assert.equal(status, 0, stdout);
    assert.match(stdout, /1 known/);
    assert.match(stdout, /ratcheted, not blocking/);
  });
});

test('gate fails when a listed shader starts passing (ratchet must tighten)', () => {
  withTempDir((dir) => {
    const file = path.join(dir, 'zz-good.wgsl');
    fs.writeFileSync(file, VALID_WGSL);
    const { status, stdout } = runGate(['--contract', contractWith(dir, ['zz-good']), '--files', file]);
    assert.equal(status, 1, stdout);
    assert.match(stdout, /now pass naga but are still listed/);
    assert.match(stdout, /lower ratchet to 0/);
  });
});

test('gate fails when ratchet disagrees with the id list', () => {
  withTempDir((dir) => {
    const contract = JSON.parse(fs.readFileSync(contractWith(dir, []), 'utf8'));
    contract.knownFailures.ratchet = 7;
    const file = path.join(dir, 'mismatch.json');
    fs.writeFileSync(file, JSON.stringify(contract));
    const good = path.join(dir, 'zz-good.wgsl');
    fs.writeFileSync(good, VALID_WGSL);
    const { status, stdout } = runGate(['--contract', file, '--files', good]);
    assert.equal(status, 1, stdout);
    assert.match(stdout, /ratchet is 7 but ids lists 0/);
  });
});

test('the whole catalog matches the recorded ratchet exactly', () => {
  const { status, stdout } = runGate(['--all']);
  assert.equal(status, 0, stdout);
  const m = stdout.match(/(\d+) valid, (\d+) invalid \((\d+) known, (\d+) new\)/);
  assert.ok(m, `could not parse the summary line from:\n${stdout}`);
  assert.equal(Number(m[4]), 0, 'new naga failures in the catalog');
  assert.equal(
    Number(m[3]),
    CONTRACT.knownFailures.ratchet,
    'known-failure count drifted from the contract ratchet',
  );
});
