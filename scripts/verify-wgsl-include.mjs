#!/usr/bin/env node
/**
 * verify-wgsl-include.mjs
 *
 * Holds the two `#include` expanders byte-identical:
 *   src/wasm/bridge/wgslInclude.ts  (source of truth, via its emitted bridge copy)
 *   scripts/wgsl_include.py         (mirror, for scripts/bindgroup_checker.py)
 *
 * Runs both over scripts/fixtures/wgsl_include/ and requires that, for every
 * case, they produce the same output or both reject it. The TS side is exercised
 * through public/wasm/bridge/wgslInclude.js — the artifact that actually ships —
 * which verify:wasm-bridge-sync separately proves matches the TypeScript.
 *
 * Also asserts the directive pattern in src/contracts/wgsl_include.json matches
 * what both implementations use, and that the load paths call the expander.
 *
 * Usage: node scripts/verify-wgsl-include.mjs [--update]
 *   --update rewrites the committed .expected files.
 */

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const CONTRACT = JSON.parse(fs.readFileSync(path.join(ROOT, 'src/contracts/wgsl_include.json'), 'utf8'));
const FIXTURES = path.join(ROOT, 'scripts/fixtures/wgsl_include');
const EXPECTED_DIR = path.join(FIXTURES, 'expected');
const UPDATE = process.argv.includes('--update');

let failed = false;
const fail = (msg) => {
  console.error(msg);
  failed = true;
};

const readFixture = (name) => {
  const p = path.join(FIXTURES, name);
  return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null;
};

async function expandWithTs(entry) {
  const mod = await import(pathToFileURL(path.join(ROOT, 'public/wasm/bridge/wgslInclude.js')).href);
  try {
    const out = await mod.expandWgslIncludes(readFixture(entry), async (name) => readFixture(name), entry);
    return { ok: true, out };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

function expandWithPython(entry) {
  const script = `
import json, sys
sys.path.insert(0, ${JSON.stringify(path.join(ROOT, 'scripts'))})
from pathlib import Path
from wgsl_include import expand_wgsl_includes, WgslIncludeError
root = Path(${JSON.stringify(FIXTURES)})
def resolve(name):
    p = root / name
    return p.read_text(encoding="utf-8") if p.is_file() else None
entry = ${JSON.stringify(entry)}
try:
    out = expand_wgsl_includes((root / entry).read_text(encoding="utf-8"), resolve, entry)
    print(json.dumps({"ok": True, "out": out}))
except WgslIncludeError as exc:
    print(json.dumps({"ok": False, "error": str(exc)}))
`;
  const stdout = execFileSync('python3', ['-c', script], { encoding: 'utf8' });
  return JSON.parse(stdout);
}

function verifyContractPattern() {
  const tsSource = fs.readFileSync(path.join(ROOT, 'src/wasm/bridge/wgslInclude.ts'), 'utf8');
  const pySource = fs.readFileSync(path.join(ROOT, 'scripts/wgsl_include.py'), 'utf8');

  // The contract stores the pattern JSON-escaped; both implementations must use it verbatim.
  const pattern = CONTRACT.directive.pattern;
  const tsLiteral = pattern.replace(/\\\\/g, '\\');
  if (!tsSource.includes(tsLiteral)) {
    fail(`❌ src/wasm/bridge/wgslInclude.ts does not use the contract directive pattern: ${tsLiteral}`);
  }
  if (!pySource.includes(tsLiteral)) {
    fail(`❌ scripts/wgsl_include.py does not use the contract directive pattern: ${tsLiteral}`);
  }

  for (const [impl, source] of [
    ['src/wasm/bridge/wgslInclude.ts', tsSource],
    ['scripts/wgsl_include.py', pySource],
  ]) {
    if (!new RegExp(`\\b${CONTRACT.maxDepth}\\b`).test(source)) {
      fail(`❌ ${impl} does not carry maxDepth ${CONTRACT.maxDepth} from the contract`);
    }
  }
}

/** The load paths must actually call the expander, or it is decorative. */
function verifyCallSites() {
  const checks = [
    ['src/utils/fetchShaderWgsl.ts', /expandWgslIncludes\s*\(/, 'the WebGPU fetch path'],
    ['src/wasm/bridge/shader.ts', /expandWgslIncludes\s*\(/, 'the WASM load path'],
    ['scripts/verify-naga-wasm.mjs', /expandWgslIncludes\s*\(/, 'the naga gate'],
    ['scripts/bindgroup_checker.py', /expand_wgsl_includes\s*\(|expand_file\s*\(/, 'the bindgroup checker'],
  ];
  for (const [file, re, what] of checks) {
    const p = path.join(ROOT, file);
    if (!fs.existsSync(p)) {
      fail(`❌ ${file} is missing (${what} must expand includes)`);
      continue;
    }
    if (!re.test(fs.readFileSync(p, 'utf8'))) {
      fail(`❌ ${file} does not call the include expander — ${what} would see raw #include directives`);
    }
  }

  // C++ must reject a surviving directive rather than grow a second parser.
  const pipeline = path.join(ROOT, 'wasm_renderer/pipeline.cpp');
  if (fs.existsSync(pipeline)) {
    const src = fs.readFileSync(pipeline, 'utf8');
    if (!/ContainsWgslIncludeDirective\s*\(\s*wgslCode\s*\)/.test(src)) {
      fail(
        '❌ wasm_renderer/pipeline.cpp LoadShader must call ContainsWgslIncludeDirective(wgslCode) and ' +
          'refuse source that still holds a directive (see wgsl_include.json consumers.cppNote)',
      );
    }
  }
  const internal = path.join(ROOT, 'wasm_renderer/wasm_internal.cpp');
  if (fs.existsSync(internal) && !/bool\s+ContainsWgslIncludeDirective/.test(fs.readFileSync(internal, 'utf8'))) {
    fail('❌ wasm_renderer/wasm_internal.cpp must define ContainsWgslIncludeDirective');
  }
}

/** The generated libraries must match their sources. */
function verifyGeneratedLibraries() {
  try {
    const out = execFileSync('python3', [path.join(ROOT, 'scripts/generate_shader_libs.py'), '--check'], {
      cwd: ROOT,
      encoding: 'utf8',
      stdio: 'pipe',
    });
    process.stdout.write(out);
  } catch (err) {
    fail(`${err.stdout ?? ''}${err.stderr ?? ''}`.trimEnd());
  }
}

async function main() {
  verifyContractPattern();
  verifyCallSites();
  verifyGeneratedLibraries();

  if (!fs.existsSync(path.join(ROOT, 'public/wasm/bridge/wgslInclude.js'))) {
    fail('❌ public/wasm/bridge/wgslInclude.js missing — run: node scripts/emit-wasm-bridge.mjs');
    process.exit(1);
  }

  fs.mkdirSync(EXPECTED_DIR, { recursive: true });
  const cases = fs
    .readdirSync(FIXTURES)
    .filter((f) => f.startsWith('case_') && f.endsWith('.wgsl'))
    .sort();

  if (cases.length === 0) {
    fail('❌ no fixtures found under scripts/fixtures/wgsl_include/');
    process.exit(1);
  }

  let compared = 0;
  for (const entry of cases) {
    const ts = await expandWithTs(entry);
    const py = expandWithPython(entry);

    if (ts.ok !== py.ok) {
      fail(
        `❌ ${entry}: TS ${ts.ok ? 'accepted' : 'rejected'} but Python ${py.ok ? 'accepted' : 'rejected'}\n` +
          `   TS:     ${ts.ok ? '(expanded)' : ts.error}\n   Python: ${py.ok ? '(expanded)' : py.error}`,
      );
      continue;
    }

    if (ts.ok) {
      if (ts.out !== py.out) {
        fail(`❌ ${entry}: expanders disagree.\n--- TS ---\n${ts.out}\n--- Python ---\n${py.out}`);
        continue;
      }
    } else if (ts.error !== py.error) {
      fail(`❌ ${entry}: error messages differ.\n   TS:     ${ts.error}\n   Python: ${py.error}`);
      continue;
    }

    // Both agree — lock the agreed result in so behaviour cannot drift silently.
    const expectedPath = path.join(EXPECTED_DIR, `${entry.replace(/\.wgsl$/, '')}.expected`);
    const actual = ts.ok ? ts.out : `ERROR: ${ts.error}\n`;
    if (UPDATE || !fs.existsSync(expectedPath)) {
      fs.writeFileSync(expectedPath, actual);
    } else {
      const expected = fs.readFileSync(expectedPath, 'utf8');
      if (expected !== actual) {
        fail(
          `❌ ${entry}: output changed from the committed expectation.\n` +
            `--- expected ---\n${expected}\n--- actual ---\n${actual}\n` +
            `(run: node scripts/verify-wgsl-include.mjs --update if this is intended)`,
        );
        continue;
      }
    }
    compared += 1;
  }

  // A shader with no directive must come back byte-identical, not merely equal.
  const plain = readFixture('case_plain.wgsl');
  const plainOut = (await expandWithTs('case_plain.wgsl')).out;
  if (plain !== plainOut) {
    fail('❌ a shader with no #include must be returned byte-identical');
  }

  if (failed) {
    console.error('\n❌ WGSL include verification failed');
    process.exit(1);
  }
  console.log(
    `✅ WGSL include expanders agree on ${compared}/${cases.length} fixtures ` +
      `(TS ↔ Python, contract pattern, call sites)`,
  );
}

main().catch((err) => {
  console.error(`❌ ${err.message}`);
  process.exit(1);
});
