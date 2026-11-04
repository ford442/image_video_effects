// @vitest-environment node
/**
 * "Save as shader" output for a sample draft, run through the repo's own gates:
 *   verify:shader-definitions  scripts/validate_shader_definitions.mjs on the JSON
 *   verify:naga-wasm           scripts/verify-naga-wasm.mjs --files on the WGSL
 *   verify:wgsl-include        the TS bridge expander and the Python mirror agree on it
 *   verify:prelude-migration   prelude_header.pastes_header is false (rule R1)
 */
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { WGSL_TEMPLATE, newWgslDraft } from './wgslDraft';
import { buildShaderFiles, SavedShaderFiles } from './wgslSave';

const ROOT = path.resolve(__dirname, '../..');
const ID = 'graph-lab-save-sample';
let dir: string;
let files: SavedShaderFiles;
let wgslFile: string;
let jsonFile: string;

const hasPython = spawnSync('python3', ['--version']).status === 0;

beforeAll(() => {
  // A sample that uses a non-bundled library too, so the include path is exercised.
  const source = WGSL_TEMPLATE.replace('#include "_prelude.wgsl"', '#include "_prelude.wgsl"\n#include "_hash.wgsl"').replace(
    'let t = u.config.x * u.zoom_params.x;',
    'let t = u.config.x * u.zoom_params.x + hash21(uv) * 0.001;',
  );
  const draft = { ...newWgslDraft(0, source), id: ID, name: 'Graph Lab save sample', category: 'distortion' as const };
  const built = buildShaderFiles(draft, {
    diagnosis: { source, ok: true, diagnostics: [], expanded: null, header: { params: [], problems: [] } },
  });
  if (!built.ok) throw new Error(built.errors.join('; '));
  files = built.files;
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'graph-lab-save-'));
  wgslFile = path.join(dir, `${ID}.wgsl`);
  jsonFile = path.join(dir, 'distortion', `${ID}.json`);
  fs.mkdirSync(path.dirname(jsonFile), { recursive: true });
  fs.writeFileSync(wgslFile, files.wgsl);
  fs.writeFileSync(jsonFile, files.json);
});

afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

const run = (args: string[]) => spawnSync(process.execPath, args, { cwd: ROOT, encoding: 'utf8' });

describe('Save as shader output passes the CI gates', () => {
  it('verify:shader-definitions', () => {
    const r = run(['scripts/validate_shader_definitions.mjs', jsonFile]);
    expect(r.stderr).toBe('');
    expect(r.status).toBe(0);
  });

  it('verify:naga-wasm', () => {
    const r = run(['scripts/verify-naga-wasm.mjs', '--files', wgslFile]);
    expect(`${r.stdout}${r.stderr}`).not.toMatch(/❌/);
    expect(r.status).toBe(0);
  }, 30_000);

  it.runIf(hasPython)('verify:wgsl-include — the TS and Python expanders agree', async () => {
    const mod = (await import(pathToFileURL(path.join(ROOT, 'public/wasm/bridge/wgslInclude.js')).href)) as {
      expandWgslIncludes(s: string, r: (n: string) => Promise<string | null>, e: string): Promise<string>;
    };
    const read = async (n: string) => {
      const p = path.join(ROOT, 'public/shaders', n);
      return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null;
    };
    const ts = await mod.expandWgslIncludes(files.wgsl, read, `${ID}.wgsl`);
    const py = execFileSync(
      'python3',
      [
        '-c',
        [
          'import sys',
          `sys.path.insert(0, ${JSON.stringify(path.join(ROOT, 'scripts'))})`,
          'from pathlib import Path',
          'from wgsl_include import expand_wgsl_includes',
          `root = Path(${JSON.stringify(path.join(ROOT, 'public/shaders'))})`,
          'def resolve(n):',
          '    p = root / n',
          '    return p.read_text(encoding="utf-8") if p.exists() else None',
          `src = Path(${JSON.stringify(wgslFile)}).read_text(encoding="utf-8")`,
          `sys.stdout.write(expand_wgsl_includes(src, resolve, ${JSON.stringify(`${ID}.wgsl`)}))`,
        ].join('\n'),
      ],
      { encoding: 'utf8' },
    );
    expect(py).toBe(ts);
  });

  it.runIf(hasPython)('verify:prelude-migration — includes the prelude, pastes no header', () => {
    const out = execFileSync(
      'python3',
      [
        '-c',
        [
          'import sys',
          `sys.path.insert(0, ${JSON.stringify(path.join(ROOT, 'scripts'))})`,
          'from pathlib import Path',
          'import prelude_header as ph',
          `src = Path(${JSON.stringify(wgslFile)}).read_text(encoding="utf-8")`,
          'print(ph.pastes_header(src), "_prelude.wgsl" in ph.includes_of(src))',
        ].join('\n'),
      ],
      { encoding: 'utf8' },
    );
    expect(out.trim()).toBe('False True');
  });
});
