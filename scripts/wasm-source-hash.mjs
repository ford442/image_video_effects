#!/usr/bin/env node
/**
 * Source-hash freshness gate for the committed WASM renderer artifacts.
 *
 * Hashes the files that define the emcc build of public/wasm/pixelocity_wasm*.wasm
 * (sources, generated headers, build script, compile-flag / export contracts and
 * the scripts that turn them into flags or headers). It hashes the *sources*, not
 * the binary, so emsdk patch-level nondeterminism cannot cause false failures.
 *
 *   node scripts/wasm-source-hash.mjs           print the current hash
 *   node scripts/wasm-source-hash.mjs --write   record it to public/wasm/source-hash.json
 *   node scripts/wasm-source-hash.mjs --check   exit 1 when the recorded hash differs
 *
 * --check when public/wasm/source-hash.json does not exist yet prints a warning
 * and exits 0 (warn mode until the first hash is committed); once the file is
 * committed the gate is blocking. `wasm_renderer/build.sh` runs --write after a
 * successful release compile, so a local or wasm.yml rebuild records the hash.
 * wasm.yml's path filter includes public/wasm/** so a PR that edits this file
 * also gets the build-and-compare job.
 *
 * Not hashed: Markdown and analysis docs under wasm_renderer/, and the JS bridge
 * (src/wasm/bridge/** → wasm_renderer/bridge, public/wasm/wasm_bridge.js). The
 * bridge is plain JS synced by concat_bridge.sh on every build and verified by
 * `npm run verify:wasm-bridge-sync`; it does not feed the emcc binary.
 */
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const RECORD_REL = 'public/wasm/source-hash.json';
const RECORD_PATH = path.join(REPO_ROOT, RECORD_REL);

/** Files (or globs, `*` within one path segment) that define the emcc build. */
export const WASM_SOURCE_PATTERNS = [
  'wasm_renderer/*.cpp',
  'wasm_renderer/*.h',
  'wasm_renderer/build.sh',
  'wasm_renderer/emsdk_env_locate.sh',
  'src/contracts/wasm_compile_flags.json',
  'src/contracts/wasm_exports.json',
  // Contracts that generate the committed wasm_renderer/*.h headers.
  'src/contracts/bind_group0.json',
  'src/contracts/canvas_configure.json',
  'src/contracts/webgpu_limits.json',
  'scripts/format-wasm-compile-flags.js',
  'scripts/format-wasm-exports.js',
  'scripts/emcc-version-gate.sh',
  'scripts/gen-*-header.js',
];

function globToRegex(pattern) {
  const escaped = pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '[^/]*');
  return new RegExp(`^${escaped}$`);
}

/** Candidate files: tracked files from git, or a walk of the pattern dirs without git. */
function candidateFiles() {
  const dirs = [...new Set(WASM_SOURCE_PATTERNS.map((p) => path.posix.dirname(p)))];
  try {
    const out = execFileSync('git', ['ls-files', '-z', '--', ...dirs], {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const tracked = out.split('\0').filter(Boolean);
    if (tracked.length > 0) return tracked;
  } catch {
    // Not a git checkout (e.g. a tarball): fall through to a directory listing.
  }
  const files = [];
  for (const dir of dirs) {
    const abs = path.join(REPO_ROOT, dir);
    if (!fs.existsSync(abs)) continue;
    for (const entry of fs.readdirSync(abs, { withFileTypes: true })) {
      if (entry.isFile()) files.push(path.posix.join(dir, entry.name));
    }
  }
  return files;
}

export function listWasmSourceFiles() {
  const regexes = WASM_SOURCE_PATTERNS.map(globToRegex);
  return candidateFiles()
    .filter((rel) => regexes.some((re) => re.test(rel)))
    .filter((rel) => fs.existsSync(path.join(REPO_ROOT, rel)))
    .sort();
}

export function computeWasmSourceHash() {
  const files = listWasmSourceFiles();
  const total = createHash('sha256');
  for (const rel of files) {
    // Normalise CRLF so a Windows checkout with autocrlf hashes the same as CI.
    const content = fs.readFileSync(path.join(REPO_ROOT, rel)).toString('latin1').replace(/\r\n/g, '\n');
    const fileHash = createHash('sha256').update(content, 'latin1').digest('hex');
    total.update(`${rel}\0${fileHash}\n`);
  }
  const flags = JSON.parse(fs.readFileSync(path.join(REPO_ROOT, 'src/contracts/wasm_compile_flags.json'), 'utf8'));
  return { sourceHash: total.digest('hex'), emsdkVersion: flags.emsdkVersion ?? null, files };
}

export function readRecord() {
  if (!fs.existsSync(RECORD_PATH)) return null;
  return JSON.parse(fs.readFileSync(RECORD_PATH, 'utf8'));
}

/**
 * @returns {{ status: 'ok' | 'missing' | 'stale', current: ReturnType<typeof computeWasmSourceHash>, recorded: any }}
 */
export function checkWasmSourceHash() {
  const current = computeWasmSourceHash();
  const recorded = readRecord();
  if (!recorded) return { status: 'missing', current, recorded };
  return { status: recorded.sourceHash === current.sourceHash ? 'ok' : 'stale', current, recorded };
}

function describeDrift(current, recorded) {
  const before = new Set(recorded.files ?? []);
  const after = new Set(current.files);
  const added = current.files.filter((f) => !before.has(f));
  const removed = [...before].filter((f) => !after.has(f));
  const lines = [];
  if (added.length) lines.push(`  added:   ${added.join(', ')}`);
  if (removed.length) lines.push(`  removed: ${removed.join(', ')}`);
  if (recorded.emsdkVersion !== current.emsdkVersion) {
    lines.push(`  emsdkVersion: ${recorded.emsdkVersion} → ${current.emsdkVersion}`);
  }
  return lines;
}

function main(argv) {
  const mode = argv.includes('--write') ? 'write' : argv.includes('--check') ? 'check' : 'print';

  if (mode === 'write') {
    const current = computeWasmSourceHash();
    fs.mkdirSync(path.dirname(RECORD_PATH), { recursive: true });
    fs.writeFileSync(RECORD_PATH, `${JSON.stringify(current, null, 2)}\n`);
    console.log(`[wasm-source-hash] wrote ${RECORD_REL}: ${current.sourceHash} (${current.files.length} files, emsdk ${current.emsdkVersion})`);
    return 0;
  }

  if (mode === 'print') {
    const current = computeWasmSourceHash();
    console.log(current.sourceHash);
    return 0;
  }

  const { status, current, recorded } = checkWasmSourceHash();
  if (status === 'ok') {
    console.log(`[wasm-source-hash] ✅ ${RECORD_REL} matches the WASM sources (${current.sourceHash.slice(0, 12)}, ${current.files.length} files)`);
    return 0;
  }
  if (status === 'missing') {
    console.warn(`[wasm-source-hash] ⚠️  ${RECORD_REL} not committed yet (warn mode). Current source hash: ${current.sourceHash}`);
    console.warn('   Commit it from a pinned-emsdk build (`npm run wasm:build` writes it) to make this gate blocking.');
    return 0;
  }
  console.error(`[wasm-source-hash] ❌ WASM sources changed without a rebuild.`);
  console.error(`   recorded ${recorded.sourceHash}`);
  console.error(`   current  ${current.sourceHash}`);
  for (const line of describeDrift(current, recorded)) console.error(line);
  console.error('   Rebuild with the pinned emsdk (`npm run wasm:build`, which rewrites the hash) and commit public/wasm/*,');
  console.error("   or take public/wasm/ from wasm.yml's wasm-artifacts upload for this PR.");
  return 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
