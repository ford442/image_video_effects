import fs from 'fs';
import path from 'path';
import {
  parseShaderDefinition,
  parseShaderParam,
  parseShaderParams,
} from '../services/shaderDefinition';

// Standalone ajv output (CommonJS, no ajv at runtime) — same module the CI validator loads.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const validate = require('../contracts/shaderDefinition.validate.js') as ((data: unknown) => boolean) & {
  errors?: unknown[];
};

const ROOT = path.resolve(__dirname, '..', '..');
const LISTS_DIR = path.join(ROOT, 'public', 'shader-lists');

function listEntries(): { file: string; entry: Record<string, unknown> }[] {
  return fs
    .readdirSync(LISTS_DIR)
    .filter((f) => f.endsWith('.json'))
    .flatMap((file) =>
      (JSON.parse(fs.readFileSync(path.join(LISTS_DIR, file), 'utf8')) as Record<string, unknown>[]).map(
        (entry) => ({ file, entry }),
      ),
    );
}

describe('shader definition schema vs shipped shader lists', () => {
  const entries = listEntries();

  it('has entries to check', () => {
    expect(entries.length).toBeGreaterThan(1000);
  });

  it('every list entry satisfies the schema (x-meta is stripped, nothing legacy ships)', () => {
    const bad = entries
      .filter(({ entry }) => !validate(entry))
      .map(({ file, entry }) => `${file}:${String(entry.id)}`);
    expect(bad).toEqual([]);
  });

  it('parseShaderDefinition keeps every entry and every slider', () => {
    for (const { entry } of entries) {
      const parsed = parseShaderDefinition(entry);
      expect(parsed).not.toBeNull();
      expect(parsed?.id).toBe(entry.id);
      expect(parsed?.params?.length ?? 0).toBe(((entry.params as unknown[]) ?? []).length);
    }
  });

  it('parseShaderDefinition does not change a schema-valid slider', () => {
    for (const { entry } of entries) {
      const parsed = parseShaderDefinition(entry);
      for (const [i, p] of ((entry.params as Record<string, unknown>[]) ?? []).entries()) {
        const q = parsed?.params?.[i] as unknown as Record<string, unknown>;
        for (const key of Object.keys(p)) expect(q[key]).toEqual(p[key]);
      }
    }
  });
});

describe('shader definition schema', () => {
  const minimal = { id: 'demo', name: 'Demo', url: 'shaders/demo.wgsl' };

  it('accepts a minimal definition and rejects legacy keys', () => {
    expect(validate(minimal)).toBe(true);
    expect(validate({ ...minimal, updatedParams: [] })).toBe(false);
    expect(validate({ ...minimal, advanced_params: [] })).toBe(false);
    expect(validate({ ...minimal, _seeded_by: 'x' })).toBe(false);
  });

  it('keeps authoring metadata under x-meta', () => {
    expect(validate({ ...minimal, 'x-meta': { upgrade: { params: [] }, seeded_by: 'x' } })).toBe(true);
  });

  it('rejects a slider without an id or with an unknown audio band', () => {
    const slider = { id: 'a', name: 'A', default: 0.5, min: 0, max: 1 };
    expect(validate({ ...minimal, params: [slider] })).toBe(true);
    expect(validate({ ...minimal, params: [{ ...slider, id: undefined }] })).toBe(false);
    expect(validate({ ...minimal, params: [{ ...slider, audio: 'sub' }] })).toBe(false);
    expect(validate({ ...minimal, params: [{ ...slider, audio: { fft: 10 } }] })).toBe(true);
  });

  it('rejects a multipass pass without totalPasses', () => {
    expect(validate({ ...minimal, multipass: { pass: 1 } })).toBe(false);
    expect(validate({ ...minimal, multipass: { pass: 1, totalPasses: 2, nextShader: 'demo-2' } })).toBe(true);
  });
});

describe('parseShaderParam defaults', () => {
  it('fills the historical slider defaults', () => {
    expect(parseShaderParam({}, 2)).toEqual({ id: 'param3', name: 'Parameter 3', default: 0.5, min: 0, max: 1 });
    expect(parseShaderParam({ name: 'Wind' }, 0).id).toBe('Wind');
  });

  it('ignores non-objects and non-arrays', () => {
    expect(parseShaderParams(undefined)).toEqual([]);
    expect(parseShaderParams('x')).toEqual([]);
    expect(parseShaderDefinition(null)).toBeNull();
    expect(parseShaderDefinition({ name: 'no id' })).toBeNull();
    expect(parseShaderDefinition({ id: 'a' })?.url).toBe('shaders/a.wgsl');
  });
});
