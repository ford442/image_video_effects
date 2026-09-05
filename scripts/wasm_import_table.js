#!/usr/bin/env node
/**
 * Minimal WebAssembly binary import-section reader (section id 2).
 * Used by verify-device-policy-sync.js to assert shipped artifacts
 * do not import forbidden C API symbols (e.g. wgpuSurfacePresent).
 */

const fs = require('fs');

const WASM_MAGIC = 0x6d736100; // \0asm
const IMPORT_SECTION_ID = 2;

function readLeb128(buf, offset) {
  let result = 0;
  let shift = 0;
  let pos = offset;
  while (pos < buf.length) {
    const byte = buf[pos++];
    result |= (byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) break;
    shift += 7;
    if (shift > 35) throw new Error('LEB128 too long at offset ' + offset);
  }
  return { value: result >>> 0, next: pos };
}

function readName(buf, offset) {
  const len = readLeb128(buf, offset);
  const start = len.next;
  const end = start + len.value;
  if (end > buf.length) throw new Error('truncated name at offset ' + offset);
  return { value: buf.slice(start, end).toString('utf8'), next: end };
}

function skipLimits(buf, pos) {
  const flags = buf[pos++];
  const min = readLeb128(buf, pos);
  pos = min.next;
  if (flags & 1) {
    const max = readLeb128(buf, pos);
    pos = max.next;
  }
  return pos;
}

function skipImportKind(buf, kindOffset) {
  const kind = buf[kindOffset];
  let p = kindOffset + 1;
  if (kind === 0) return readLeb128(buf, p).next;
  if (kind === 1) {
    p += 1;
    return skipLimits(buf, p);
  }
  if (kind === 2) return skipLimits(buf, p);
  if (kind === 3) return p + 2;
  throw new Error('unknown wasm import kind ' + kind + ' at ' + kindOffset);
}

/**
 * @param {string|Buffer} fileOrBuffer
 * @returns {{ module: string, name: string, kind: number }[]}
 */
function readWasmImports(fileOrBuffer) {
  const buf = Buffer.isBuffer(fileOrBuffer) ? fileOrBuffer : fs.readFileSync(fileOrBuffer);
  if (buf.length < 8 || buf.readUInt32LE(0) !== WASM_MAGIC) {
    throw new Error('not a WebAssembly binary (bad magic)');
  }
  const version = buf.readUInt32LE(4);
  if (version !== 1) {
    throw new Error('unsupported wasm version ' + version);
  }

  const imports = [];
  let pos = 8;
  while (pos < buf.length) {
    const id = buf[pos++];
    const size = readLeb128(buf, pos);
    pos = size.next;
    const end = pos + size.value;
    if (end > buf.length) throw new Error('truncated wasm section id=' + id);
    if (id === IMPORT_SECTION_ID) {
      const count = readLeb128(buf, pos);
      let p = count.next;
      for (let i = 0; i < count.value; i++) {
        const mod = readName(buf, p);
        const field = readName(buf, mod.next);
        const kind = buf[field.next];
        imports.push({ module: mod.value, name: field.value, kind });
        p = skipImportKind(buf, field.next);
      }
    }
    pos = end;
  }
  return imports;
}

function importNames(fileOrBuffer) {
  return readWasmImports(fileOrBuffer).map((imp) => imp.name);
}

module.exports = {
  IMPORT_SECTION_ID,
  readWasmImports,
  importNames,
};

if (require.main === module) {
  const target = process.argv[2];
  if (!target) {
    console.error('usage: node scripts/wasm_import_table.js <file.wasm>');
    process.exit(2);
  }
  const names = importNames(target);
  names.forEach((n) => console.log(n));
}
