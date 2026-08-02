#!/usr/bin/env node
/**
 * Self-test for verify-uniforms-layout.js: the gate must actually FAIL on drift.
 * Builds throwaway copies of the tracked files, mutates one thing at a time, and
 * asserts the checker exits non-zero with the expected complaint.
 *
 * Run: node scripts/test_verify_uniforms_layout.js
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const SCRIPT = path.join(__dirname, 'verify-uniforms-layout.js');

const contract = JSON.parse(fs.readFileSync(path.join(ROOT, 'src/contracts/uniforms_layout.json'), 'utf8'));

const TRACKED = [
  'src/contracts/uniforms_layout.json',
  'src/renderer/UniformBuffer.ts',
  'src/renderer/types.ts',
  'wasm_renderer/renderer.h',
  'wasm_renderer/frame.cpp',
  ...contract.authoringComment.trackedFiles,
];

function makeTree() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'uniforms-contract-'));
  for (const rel of TRACKED) {
    const dest = path.join(dir, rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(path.join(ROOT, rel), dest);
  }
  return dir;
}

function run(dir) {
  return spawnSync(process.execPath, [SCRIPT], {
    env: { ...process.env, UNIFORMS_CONTRACT_ROOT: dir },
    encoding: 'utf8',
  });
}

function patch(dir, rel, from, to) {
  const p = path.join(dir, rel);
  const src = fs.readFileSync(p, 'utf8');
  if (!src.includes(from)) throw new Error(`self-test fixture stale: "${from}" not found in ${rel}`);
  fs.writeFileSync(p, src.replace(from, to));
}

let failures = 0;
function check(name, fn) {
  const dir = makeTree();
  try {
    fn(dir);
    const res = run(dir);
    if (res.status === 0) {
      console.error(`❌ ${name}: gate passed but should have failed`);
      failures++;
    } else {
      console.log(`✅ ${name}: gate failed as expected`);
    }
  } catch (err) {
    console.error(`❌ ${name}: ${err.message}`);
    failures++;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

// Baseline: the untouched tree must pass.
{
  const dir = makeTree();
  const res = run(dir);
  if (res.status !== 0) {
    console.error('❌ baseline: unmodified tree fails the gate\n' + res.stdout + res.stderr);
    failures++;
  } else {
    console.log('✅ baseline: unmodified tree passes');
  }
  fs.rmSync(dir, { recursive: true, force: true });
}

check('offset drift in UniformBuffer.ts', (dir) =>
  patch(dir, 'src/renderer/UniformBuffer.ts', 'config_rippleCount: 4,', 'config_rippleCount: 8,'),
);

check('layout drift in types.ts', (dir) =>
  patch(dir, 'src/renderer/types.ts', 'ZOOM_PARAMS_OFFSET: 32,', 'ZOOM_PARAMS_OFFSET: 36,'),
);

check('struct size drift in contract JSON', (dir) =>
  patch(dir, 'src/contracts/uniforms_layout.json', '"totalSizeBytes": 848,', '"totalSizeBytes": 864,'),
);

check('C++ comment drift', (dir) =>
  patch(
    dir,
    'wasm_renderer/renderer.h',
    'float config[4];       // time, rippleCount, resolutionX, resolutionY',
    'float config[4];       // time, deltaTime, resolutionX, resolutionY',
  ),
);

check('agent brief reintroduces config.y = delta_time', (dir) =>
  patch(
    dir,
    'agents/WGSL_BUILTINS_GENERATIVE.md',
    '.y = rippleCount (0-50 active ripples)',
    '.y = delta_time',
  ),
);

check('BINDING_CONTRACT drops a documented field', (dir) =>
  patch(dir, 'docs/BINDING_CONTRACT.md', '| `zoom_config.z` | 24 |', '| `zoomconfig.z` | 24 |'),
);

if (failures) {
  console.error(`\n❌ ${failures} self-test(s) failed`);
  process.exit(1);
}
console.log('\n✅ verify-uniforms-layout self-tests passed');
