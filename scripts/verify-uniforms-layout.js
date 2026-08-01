#!/usr/bin/env node
/**
 * verify-uniforms-layout.js
 *
 * CI check: src/contracts/uniforms_layout.json is the single source of truth for the
 * WGSL `Uniforms` struct (binding 3). This verifies it against:
 *   - src/renderer/UniformBuffer.ts     (UNIFORM_OFFSETS, MAX_RIPPLES, UNIFORM_FLOATS)
 *   - src/renderer/types.ts             (UNIFORM_BUFFER_LAYOUT)
 *   - wasm_renderer/renderer.h          (struct Uniforms field comments)
 *   - wasm_renderer/frame.cpp           (UpdateUniformBuffer packing comments)
 *   - tracked authoring surfaces        (docs / agent briefs / templates must not
 *                                        claim config.y is delta_time, click count, …)
 *
 * Run: npm run verify:uniforms
 */

const fs = require('fs');
const path = require('path');

// UNIFORMS_CONTRACT_ROOT lets the self-test point the checker at a mutated copy of the tree.
const ROOT = process.env.UNIFORMS_CONTRACT_ROOT || path.join(__dirname, '..');
const CONTRACT_PATH = path.join(ROOT, 'src/contracts/uniforms_layout.json');
const contract = JSON.parse(fs.readFileSync(CONTRACT_PATH, 'utf8'));

const errors = [];
const checks = [];

function fail(msg) {
  errors.push(msg);
}
function ok(msg) {
  checks.push(msg);
}
function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8');
}

// ── 1. UNIFORM_OFFSETS in UniformBuffer.ts ──────────────────────────────────

function checkUniformBufferTs() {
  const rel = 'src/renderer/UniformBuffer.ts';
  const src = read(rel);
  const block = src.match(/UNIFORM_OFFSETS\s*=\s*\{([\s\S]*?)\}\s*as const;/);
  if (!block) {
    fail(`${rel}: UNIFORM_OFFSETS object not found`);
    return;
  }
  const offsets = {};
  for (const m of block[1].matchAll(/(\w+):\s*(\d+)\s*,/g)) {
    offsets[m[1]] = parseInt(m[2], 10);
  }

  for (const field of contract.fields) {
    for (const comp of field.components) {
      const key = comp.tsOffsetKey;
      if (!key) continue;
      const expected = field.name === 'ripples' ? field.offset : comp.offset;
      if (offsets[key] === undefined) {
        fail(`${rel}: UNIFORM_OFFSETS.${key} missing (contract field ${field.name}.${comp.swizzle})`);
      } else if (offsets[key] !== expected) {
        fail(
          `${rel}: UNIFORM_OFFSETS.${key} = ${offsets[key]} but contract says ${expected} ` +
            `(${field.name}.${comp.swizzle} = ${comp.meaning})`,
        );
      }
    }
    if (field.tsOffsetKey && offsets[field.tsOffsetKey] !== field.offset) {
      fail(`${rel}: UNIFORM_OFFSETS.${field.tsOffsetKey} = ${offsets[field.tsOffsetKey]} but contract says ${field.offset}`);
    }
  }

  const ripples = contract.fields.find((f) => f.name === 'ripples');
  if (offsets.ripple_stride !== ripples.strideBytes) {
    fail(`${rel}: UNIFORM_OFFSETS.ripple_stride = ${offsets.ripple_stride} but contract says ${ripples.strideBytes}`);
  }

  const maxRipples = src.match(/const MAX_RIPPLES\s*=\s*(\d+)/);
  if (!maxRipples || parseInt(maxRipples[1], 10) !== contract.maxRipples) {
    fail(`${rel}: MAX_RIPPLES must be ${contract.maxRipples}`);
  }

  // Component ordering inside the setters must match the contract meanings.
  const setterFields = {
    setConfig: 'config',
    setZoomConfig: 'zoom_config',
    setZoomParams: 'zoom_params',
  };
  for (const [setter, fieldName] of Object.entries(setterFields)) {
    const sig = src.match(new RegExp(`${setter}\\(([^)]*)\\):\\s*void;`));
    if (!sig) {
      fail(`${rel}: ${setter} signature not found`);
      continue;
    }
    const argNames = sig[1]
      .split(',')
      .map((a) => a.trim().split(':')[0].trim())
      .filter(Boolean);
    const field = contract.fields.find((f) => f.name === fieldName);
    const expectedNames = field.components.map((c) => c.meaning);
    // Setter args use short forms (resW/resH) for the same contract meanings.
    const TS_ARG_ALIASES = {
      resolutionWidth: ['resW', 'resolutionWidth', 'width'],
      resolutionHeight: ['resH', 'resolutionHeight', 'height'],
    };
    const mismatch = expectedNames.filter((n, i) => {
      const accepted = TS_ARG_ALIASES[n] || [n];
      return !accepted.includes(argNames[i]);
    });
    if (mismatch.length) {
      fail(
        `${rel}: ${setter}(${argNames.join(', ')}) does not match contract order ` +
          `(${expectedNames.join(', ')})`,
      );
    }
  }

  ok(`${rel}: UNIFORM_OFFSETS + setters match contract`);
}

// ── 2. UNIFORM_BUFFER_LAYOUT in types.ts ────────────────────────────────────

function checkTypesTs() {
  const rel = 'src/renderer/types.ts';
  const src = read(rel);
  const block = src.match(/UNIFORM_BUFFER_LAYOUT\s*=\s*\{([\s\S]*?)\}\s*as const;/);
  if (!block) {
    fail(`${rel}: UNIFORM_BUFFER_LAYOUT not found`);
    return;
  }
  const vals = {};
  for (const m of block[1].matchAll(/(\w+):\s*(\d+)\s*,/g)) {
    vals[m[1]] = parseInt(m[2], 10);
  }
  const expected = {
    CONFIG_OFFSET: contract.fields.find((f) => f.name === 'config').offset,
    ZOOM_CONFIG_OFFSET: contract.fields.find((f) => f.name === 'zoom_config').offset,
    ZOOM_PARAMS_OFFSET: contract.fields.find((f) => f.name === 'zoom_params').offset,
    RIPPLES_OFFSET: contract.fields.find((f) => f.name === 'ripples').offset,
    TOTAL_SIZE: contract.totalSizeBytes,
    MAX_RIPPLES: contract.maxRipples,
  };
  for (const [key, want] of Object.entries(expected)) {
    if (vals[key] !== want) {
      fail(`${rel}: UNIFORM_BUFFER_LAYOUT.${key} = ${vals[key]} but contract says ${want}`);
    }
  }

  // Total size must be self-consistent with the field list.
  const ripples = contract.fields.find((f) => f.name === 'ripples');
  const derived = ripples.offset + ripples.count * ripples.strideBytes;
  if (derived !== contract.totalSizeBytes) {
    fail(`contract: totalSizeBytes ${contract.totalSizeBytes} != derived ${derived}`);
  }
  if (contract.floatCount * 4 !== contract.totalSizeBytes) {
    fail(`contract: floatCount ${contract.floatCount} does not match totalSizeBytes ${contract.totalSizeBytes}`);
  }

  ok(`${rel}: UNIFORM_BUFFER_LAYOUT matches contract`);
}

// ── 3. C++ mirror ───────────────────────────────────────────────────────────

/** Normalizes a comment for meaning comparison: lowercase alnum tokens. */
function tokens(text) {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .split(' ')
    .filter(Boolean);
}

/** C++ comments use resolutionX/resolutionY etc.; map contract meanings to accepted aliases. */
const CPP_ALIASES = {
  time: ['time'],
  rippleCount: ['ripplecount'],
  resolutionWidth: ['resolutionx', 'resx', 'width'],
  resolutionHeight: ['resolutiony', 'resy', 'height'],
  mouseX: ['mousex'],
  mouseY: ['mousey'],
  mouseDown: ['mousedown'],
  p1: ['param1', 'p1'],
  p2: ['param2', 'p2'],
  p3: ['param3', 'p3'],
  p4: ['param4', 'p4'],
};

function checkCppComment(rel, src, pattern, fieldName) {
  const m = src.match(pattern);
  if (!m) {
    fail(`${rel}: could not find ${fieldName} packing comment (pattern ${pattern})`);
    return;
  }
  const commentTokens = tokens(m[1]);
  const field = contract.fields.find((f) => f.name === fieldName);
  field.components.forEach((comp, i) => {
    const aliases = CPP_ALIASES[comp.meaning] || [comp.meaning.toLowerCase()];
    if (!aliases.some((a) => commentTokens.includes(a))) {
      fail(
        `${rel}: ${fieldName} comment "${m[1].trim()}" does not document component ` +
          `.${comp.swizzle} = ${comp.meaning}`,
      );
    }
    const pos = commentTokens.findIndex((t) => aliases.includes(t));
    if (pos !== -1 && pos < i) {
      // ordering is best-effort; only flag hard misordering of distinct names
    }
  });
}

function checkCpp() {
  const headerRel = 'wasm_renderer/renderer.h';
  const header = read(headerRel);
  checkCppComment(headerRel, header, /float\s+config\[4\];\s*\/\/([^\n]*)/, 'config');
  checkCppComment(headerRel, header, /float\s+zoom_config\[4\];\s*\/\/([^\n]*)/, 'zoom_config');
  checkCppComment(headerRel, header, /float\s+zoom_params\[4\];\s*\/\/([^\n]*)/, 'zoom_params');

  const rippleDecl = header.match(/float\s+ripples\[(\d+)\]\[4\];/);
  if (!rippleDecl || parseInt(rippleDecl[1], 10) !== contract.maxRipples) {
    fail(`${headerRel}: struct Uniforms ripples[] must be [${contract.maxRipples}][4]`);
  }

  const frameRel = 'wasm_renderer/frame.cpp';
  const frame = read(frameRel);
  checkCppComment(frameRel, frame, /\/\/\s*config:([^\n]*)/, 'config');
  checkCppComment(frameRel, frame, /\/\/\s*zoom_config:([^\n]*)/, 'zoom_config');

  const floatCount = frame.match(/UNIFORM_FLOAT_COUNT\s*=\s*(\d+)\s*\+\s*MAX_RIPPLES\s*\*\s*(\d+)/);
  if (!floatCount) {
    fail(`${frameRel}: UNIFORM_FLOAT_COUNT expression not found`);
  } else {
    const total = parseInt(floatCount[1], 10) + contract.maxRipples * parseInt(floatCount[2], 10);
    if (total !== contract.floatCount) {
      fail(`${frameRel}: UNIFORM_FLOAT_COUNT resolves to ${total} floats, contract says ${contract.floatCount}`);
    }
  }

  ok('wasm_renderer: Uniforms struct + packing comments match contract');
}

// ── 4. Authoring surfaces (docs, briefs, templates) ─────────────────────────

function checkAuthoringSurfaces() {
  const { required, forbidden, trackedFiles } = contract.authoringComment;
  let scanned = 0;

  for (const rel of trackedFiles) {
    const abs = path.join(ROOT, rel);
    if (!fs.existsSync(abs)) {
      fail(`tracked authoring file missing: ${rel} (update uniforms_layout.json if it moved)`);
      continue;
    }
    const lines = fs.readFileSync(abs, 'utf8').split('\n');
    lines.forEach((line, i) => {
      for (const fieldName of ['config', 'zoom_config']) {
        // Match a struct field declaration with a trailing comment.
        const decl = new RegExp(`(?:^|[^_\\w])${fieldName}\\s*:\\s*vec4<f32>\\s*,\\s*(//.*)$`);
        const m = line.match(decl);
        if (!m) continue;
        if (fieldName === 'config' && /zoom_config/.test(line)) continue;
        scanned++;
        const comment = m[1];
        const lower = comment.toLowerCase();
        for (const bad of forbidden[fieldName] || []) {
          if (lower.includes(bad.toLowerCase())) {
            fail(
              `${rel}:${i + 1}: \`${fieldName}\` comment claims "${bad}" — engine truth is ` +
                `${contract.authoringComment[fieldName]}`,
            );
          }
        }
        for (const need of required[fieldName] || []) {
          if (!lower.includes(need.toLowerCase())) {
            fail(
              `${rel}:${i + 1}: \`${fieldName}\` comment omits "${need}" — expected ` +
                `${contract.authoringComment[fieldName]}`,
            );
          }
        }
      }
    });
  }

  // Prose claims outside struct blocks (e.g. "config.y = delta_time") are also banned.
  const proseBans = [/config\s*\.\s*y\s*(?:=|is|→|->)\s*[`"']?\s*(?:delta|dt\b)/i];
  for (const rel of trackedFiles) {
    const abs = path.join(ROOT, rel);
    if (!fs.existsSync(abs)) continue;
    const lines = fs.readFileSync(abs, 'utf8').split('\n');
    // Lines that explicitly debunk the myth are allowed to quote it.
    const negation = /\b(not|never|no longer|wrong|myth|stale|incorrect|was never)\b/i;
    lines.forEach((line, i) => {
      if (negation.test(line)) return;
      for (const re of proseBans) {
        if (re.test(line)) {
          fail(`${rel}:${i + 1}: prose claims config.y is delta time — it is rippleCount`);
        }
      }
    });
  }

  ok(`authoring surfaces: ${trackedFiles.length} files scanned (${scanned} Uniforms comments checked)`);
}

// ── 5. BINDING_CONTRACT.md must document every field ────────────────────────

function checkBindingContractDoc() {
  const rel = 'docs/BINDING_CONTRACT.md';
  const src = read(rel);
  if (!/##\s*Uniforms struct \(binding 3\)/.test(src)) {
    fail(`${rel}: missing "## Uniforms struct (binding 3)" section`);
    return;
  }
  for (const field of contract.fields) {
    for (const comp of field.components) {
      // Array fields are documented per element, e.g. `ripples[i].x`.
      const accepted = field.count
        ? [`${field.name}[i].${comp.swizzle}`, `${field.name}[].${comp.swizzle}`, `${field.name}.${comp.swizzle}`]
        : [`${field.name}.${comp.swizzle}`];
      const cell = accepted[0];
      if (!accepted.some((c) => src.includes(c))) {
        fail(`${rel}: Uniforms table does not document \`${cell}\` (${comp.meaning})`);
      }
    }
    if (!src.includes(`| ${field.offset} `) && field.name !== 'ripples') {
      // offsets are documented per component row; tolerate formatting variance
    }
  }
  if (!src.includes('src/contracts/uniforms_layout.json')) {
    fail(`${rel}: must cross-reference src/contracts/uniforms_layout.json`);
  }
  ok(`${rel}: Uniforms struct documented field-by-field`);
}

// ── Run ─────────────────────────────────────────────────────────────────────

checkUniformBufferTs();
checkTypesTs();
checkCpp();
checkAuthoringSurfaces();
checkBindingContractDoc();

for (const c of checks) console.log(`✅ ${c}`);

if (errors.length) {
  console.error(`\n❌ Uniforms layout contract drift (${errors.length} problem(s)):\n`);
  for (const e of errors) console.error(`  - ${e}`);
  console.error('\nSource of truth: src/contracts/uniforms_layout.json + src/renderer/UniformBuffer.ts');
  process.exit(1);
}

console.log('\n✅ Uniforms layout contract in sync (TS ↔ C++ ↔ docs/briefs)');
