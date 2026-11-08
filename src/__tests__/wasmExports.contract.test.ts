/**
 * src/contracts/wasm_exports.json `exports` is the one source for the WASM
 * export ABI: scripts/gen-wasm-exports-header.js emits the C prototypes
 * (wasm_renderer/wasm_exports.h, included by main.cpp) and the typed TS ccall
 * wrappers (src/wasm/bridge/_generated.ts). These pin the generator's rules.
 */
import fs from 'node:fs';
import path from 'node:path';
import exportsContract from '../contracts/wasm_exports.json';
import compileFlags from '../contracts/wasm_compile_flags.json';

// eslint-disable-next-line @typescript-eslint/no-require-imports
const gen = require('../../scripts/gen-wasm-exports-header.js') as {
  loadSignatures: (contract: unknown, flags?: unknown) => Array<{ name: string; isAsync: boolean }>;
  collectProblems: () => string[];
  checkCppSignatures: (sigs: unknown, cpp: string) => string[];
  parseKeepaliveSignatures: (cpp: string) => Map<string, { returns: string; args: string[] }>;
};

const ROOT = path.join(__dirname, '..', '..');
const mainCpp = fs.readFileSync(path.join(ROOT, 'wasm_renderer', 'main.cpp'), 'utf8');

type Contract = Omit<typeof exportsContract, 'exports'> & { exports: Record<string, Record<string, unknown>> };
const clone = (): Contract => JSON.parse(JSON.stringify(exportsContract)) as Contract;

function withEntry(name: string, entry: Record<string, unknown>): Contract {
  const c = clone();
  c.exports[name] = entry;
  return c;
}

describe('wasm_exports.json exports → generated TS + C++', () => {
  it('committed outputs are current and main.cpp agrees with every signature', () => {
    expect(gen.collectProblems()).toEqual([]);
  });

  it('main.cpp includes the generated header before its definitions', () => {
    const include = mainCpp.indexOf('#include "wasm_exports.h"');
    expect(include).toBeGreaterThan(-1);
    expect(include).toBeLessThan(mainCpp.indexOf('EMSCRIPTEN_KEEPALIVE'));
  });

  it('parses KEEPALIVE definitions down to their C types', () => {
    const defs = gen.parseKeepaliveSignatures(mainCpp);
    expect(defs.get('loadShader')).toEqual({ returns: 'int', args: ['const char*', 'const char*'] });
    expect(defs.get('getGPUTimings')).toEqual({ returns: 'void', args: ['float*', 'float*', 'float*', 'int*'] });
    expect(defs.get('getSlotShaderId')).toEqual({ returns: 'const char*', args: ['int'] });
    expect(defs.get('getFPS')).toEqual({ returns: 'float', args: [] });
  });

  it('flags a C++ definition that drifts from the contract', () => {
    const sigs = gen.loadSignatures(exportsContract);
    const drifted = mainCpp.replace(
      'int loadShader(const char* id, const char* wgslCode)',
      'int loadShader(const char* id, const char* wgslCode, int workgroupX)',
    );
    expect(gen.checkCppSignatures(sigs, drifted)).toEqual([
      'wasm_renderer/main.cpp loadShader is int(const char*, const char*, int); wasm_exports.json says int(const char*, const char*)',
    ]);
    const retyped = mainCpp.replace('void resizeCanvas(int newWidth', 'int resizeCanvas(int newWidth');
    expect(gen.checkCppSignatures(sigs, retyped).join('\n')).toMatch(/resizeCanvas is int\(int, int\)/);
  });

  it('async set must equal wasm_compile_flags.json jspi.jspiExports', () => {
    const c = withEntry('getFPS', { returns: 'float', args: [], async: true });
    expect(() => gen.loadSignatures(c, compileFlags)).toThrow(/jspi\.jspiExports/);
  });

  it('every exportedFunctions name needs exactly one entry', () => {
    const c = clone();
    delete c.exports.getFPS;
    expect(() => gen.loadSignatures(c, compileFlags)).toThrow(/missing \[getFPS\]/);
    const extra = withEntry('notExported', { returns: 'void', args: [], whileSuspended: 'call' });
    expect(() => gen.loadSignatures(extra, compileFlags)).toThrow(/extra \[notExported\]/);
  });

  it.each([
    ['a queued export that returns a value', 'setInputSource', { returns: 'int', args: ['source:int'], whileSuspended: 'queue' }, /must return void/],
    ['a queued export that takes a caller-owned pointer', 'setInputSource', { returns: 'void', args: ['p:const float*'], whileSuspended: 'queue' }, /caller-owned pointer/],
    ['a sync export without a policy', 'getFPS', { returns: 'float', args: [] }, /whileSuspended call\|queue\|skip/],
    ['an async export with a policy', 'loadShader', { returns: 'int', args: [], async: true, whileSuspended: 'call' }, /take no whileSuspended/],
    ['an unknown argument type', 'setMouseDown', { returns: 'void', args: ['down:bool'], whileSuspended: 'call' }, /must be int\|float\|string/],
    ['an unknown return type', 'getFPS', { returns: 'double', args: [], whileSuspended: 'call' }, /returns must be/],
    ['an optional export taking a string', 'getMaxShaderSlots', { returns: 'int', args: ['s:string'], whileSuspended: 'call', optional: true }, /cannot take a string/],
  ])('rejects %s', (_label, name, entry, message) => {
    expect(() => gen.loadSignatures(withEntry(name, entry), compileFlags)).toThrow(message);
  });
});
