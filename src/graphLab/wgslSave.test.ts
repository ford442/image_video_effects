import type { DiagnoseResult } from './wgslDiagnostics';
import { newWgslDraft, WGSL_TEMPLATE } from './wgslDraft';
import { buildShaderFiles, DirectoryHandleLike, saveShaderFiles, writeShaderFiles } from './wgslSave';

const clean = (source: string): DiagnoseResult => ({
  source,
  ok: true,
  diagnostics: [],
  expanded: null,
  header: { params: [], problems: [] },
});

describe('buildShaderFiles', () => {
  const draft = { ...newWgslDraft(0), id: 'lab-ripple', name: 'Lab Ripple', category: 'distortion' as const };

  it('emits the prelude-included WGSL and a definition with the @param sliders', () => {
    const r = buildShaderFiles(draft, { diagnosis: clean(draft.source) });
    if (!r.ok) throw new Error(r.errors.join('; '));
    expect(r.files.wgslPath).toBe('public/shaders/lab-ripple.wgsl');
    expect(r.files.jsonPath).toBe('shader_definitions/distortion/lab-ripple.json');
    expect(r.files.wgsl).toBe(WGSL_TEMPLATE);
    expect(r.files.definition).toMatchObject({ id: 'lab-ripple', url: 'shaders/lab-ripple.wgsl', category: 'distortion' });
    expect((r.files.definition.params as Array<{ mapping: string }>).map((p) => p.mapping)).toEqual([
      'zoom_params.x',
      'zoom_params.y',
      'zoom_params.z',
    ]);
    expect(JSON.parse(r.files.json)).toEqual(r.files.definition);
  });

  it('refuses unvalidated, broken, colliding, reserved and header-pasting drafts', () => {
    const errs = (d = draft, ctx: Parameters<typeof buildShaderFiles>[1] = { diagnosis: clean(d.source) }) => {
      const r = buildShaderFiles(d, ctx);
      return r.ok ? [] : r.errors;
    };
    expect(errs(draft, {})).toEqual(['wait for the diagnostics of the current text']);
    expect(errs(draft, { diagnosis: { ...clean(draft.source), ok: false, diagnostics: [{ severity: 'error', line: 1, column: 1, length: 1, message: 'boom', source: 'naga' }] } })[0]).toMatch(/boom/);
    expect(errs(draft, { diagnosis: clean(draft.source), existingIds: new Set(['lab-ripple']) })[0]).toMatch(/already exists/);
    expect(errs({ ...draft, id: 'graphlab-wgsl-0-a' })[0]).toMatch(/reserved/);
    expect(errs({ ...draft, id: 'Bad Id' })[0]).toMatch(/lowercase/);
    const noInclude = { ...draft, source: draft.source.replace('#include "_prelude.wgsl"', '// #include "_prelude.wgsl"') };
    expect(errs(noInclude).join()).toMatch(/must #include "_prelude.wgsl"/);
    const pasted = { ...draft, source: `${draft.source}\n@group(0) @binding(1) var readTexture2: texture_2d<f32>;\nstruct Uniforms { a: f32 };` };
    expect(errs(pasted)).toEqual([
      '@group(0) @binding(1) come from _prelude.wgsl; delete the pasted copy',
      'struct Uniforms comes from _prelude.wgsl; delete the pasted copy',
    ]);
    // The history ring (binding 13) is declared by hand, not by the prelude.
    expect(errs({ ...draft, source: `${draft.source}\n@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;` })).toEqual([]);
  });
});

/** In-memory FileSystemDirectoryHandle. */
function memoryDir(name: string, tree: Map<string, string>, prefix = ''): DirectoryHandleLike {
  const notFound = () => Object.assign(new Error('not found'), { name: 'NotFoundError' });
  return {
    name,
    async getDirectoryHandle(child, opts) {
      const p = `${prefix}${child}/`;
      if (!opts?.create && ![...tree.keys()].some((k) => k.startsWith(p))) throw notFound();
      if (opts?.create && !tree.has(`${p}.dir`)) tree.set(`${p}.dir`, '');
      return memoryDir(child, tree, p);
    },
    async getFileHandle(file, opts) {
      const p = `${prefix}${file}`;
      if (!opts?.create && !tree.has(p)) throw notFound();
      return {
        async createWritable() {
          let buf = '';
          return { write: async (d: string) => void (buf += d), close: async () => void tree.set(p, buf) };
        },
      };
    },
  };
}

describe('writing the files', () => {
  const draft = { ...newWgslDraft(0), id: 'lab-ripple' };
  const built = buildShaderFiles(draft, { diagnosis: clean(draft.source) });
  if (!built.ok) throw new Error('fixture');
  const repo = () => new Map([['public/shaders/a.wgsl', ''], ['shader_definitions/image/a.json', '']]);

  it('writes both files into the picked repository root', async () => {
    const tree = repo();
    expect(await writeShaderFiles(memoryDir('repo', tree), built.files)).toEqual({
      ok: true,
      via: 'directory',
      paths: ['public/shaders/lab-ripple.wgsl', 'shader_definitions/image/lab-ripple.json'],
    });
    expect(tree.get('public/shaders/lab-ripple.wgsl')).toBe(built.files.wgsl);
    expect(tree.get('shader_definitions/image/lab-ripple.json')).toBe(built.files.json);
  });

  it('refuses a folder that is not the repo, and never overwrites', async () => {
    expect(await writeShaderFiles(memoryDir('Downloads', new Map()), built.files)).toMatchObject({ ok: false, message: expect.stringMatching(/not the repository root/) });
    const tree = repo();
    tree.set('public/shaders/lab-ripple.wgsl', 'mine');
    expect(await writeShaderFiles(memoryDir('repo', tree), built.files)).toMatchObject({ ok: false, message: expect.stringMatching(/already exists/) });
    expect(tree.get('public/shaders/lab-ripple.wgsl')).toBe('mine');
  });

  it('falls back to two downloads without a directory picker; a cancelled picker is not an error', async () => {
    URL.createObjectURL = vi.fn(() => 'blob:x');
    URL.revokeObjectURL = vi.fn();
    const clicks: string[] = [];
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
      clicks.push(this.download);
    });
    expect(await saveShaderFiles(built.files, {} as Window)).toMatchObject({ ok: true, via: 'download' });
    expect(clicks).toEqual(['lab-ripple.wgsl', 'lab-ripple.json']);
    click.mockRestore();
    const abort = Object.assign(new Error('user'), { name: 'AbortError' });
    const win = { showDirectoryPicker: () => Promise.reject(abort) } as unknown as Window;
    expect(await saveShaderFiles(built.files, win)).toMatchObject({ ok: false, cancelled: true });
  });
});
