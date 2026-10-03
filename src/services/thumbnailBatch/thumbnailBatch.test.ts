import { freshnessFor, needsThumbnail, summarizeFreshness, ThumbnailState } from './freshness';
import { pickRepoWriter } from './repoWriter';
import { analyzeImageData, classifyFrame } from './frameCheck';
import { defaultParamsSnapshot } from './captureShader';
import type { ShaderEntry } from '../../renderer/types';

const state: ThumbnailState = {
  hashes: { generated_at: '', algorithm: 'x', upgrades: {}, hashes: { a: 'h1', b: 'h2', c: 'h3', d: 'h4' } },
  manifest: {
    a: { thumbnail_url: 'thumbnails/a.png', generated_at: '', source_hash: 'h1' },
    b: { thumbnail_url: 'thumbnails/b.png', generated_at: '', source_hash: 'old' },
    c: { thumbnail_url: 'thumbnails/c.png', generated_at: '' },
  },
};

describe('thumbnail freshness', () => {
  it('classifies fresh / stale / unknown / missing', () => {
    expect(freshnessFor('a', state)).toBe('fresh');
    expect(freshnessFor('b', state)).toBe('stale');
    expect(freshnessFor('c', state)).toBe('unknown');
    expect(freshnessFor('d', state)).toBe('missing');
    expect(summarizeFreshness(['a', 'b', 'c', 'd'], state)).toEqual({ fresh: 1, stale: 1, unknown: 1, missing: 1 });
  });

  it('never queues skip-allowlisted ids', () => {
    const skipping: ThumbnailState = { ...state, hashes: { ...(state.hashes as NonNullable<ThumbnailState['hashes']>), skip: ['d'] } };
    expect(needsThumbnail('d', state)).toBe(true);
    expect(needsThumbnail('d', skipping)).toBe(false);
    expect(needsThumbnail('b', skipping)).toBe(true);
  });

  it('treats every entry as unknown when source hashes are unavailable', () => {
    expect(freshnessFor('a', { hashes: null, manifest: state.manifest })).toBe('unknown');
  });
});

function solid(r: number, g: number, b: number, n = 16): Uint8ClampedArray {
  const d = new Uint8ClampedArray(n * 4);
  for (let i = 0; i < n; i++) d.set([r, g, b, 255], i * 4);
  return d;
}

describe('frame check (matches thumbnailHarness thresholds)', () => {
  it('flags black, magenta and passes normal frames', () => {
    expect(classifyFrame(analyzeImageData(solid(0, 0, 0), 4, 4))).toBe('black_frame');
    expect(classifyFrame(analyzeImageData(solid(255, 0, 255), 4, 4))).toBe('magenta_frame');
    expect(classifyFrame(analyzeImageData(solid(120, 180, 90), 4, 4))).toBeNull();
  });
});

describe('defaultParamsSnapshot', () => {
  it('maps zoom_params defaults by mapping, 0.5 elsewhere', () => {
    const shader = {
      id: 's', name: 's', url: '', category: 'image',
      params: [{ id: 'p', name: 'p', default: 0.9, min: 0, max: 1, mapping: 'zoom_params.z' }],
    } as unknown as ShaderEntry;
    expect(defaultParamsSnapshot(shader)).toEqual([0.5, 0.5, 0.9, 0.5]);
  });
});

/** In-memory File System Access directory: { name: string contents | nested dir }. */
type FakeTree = { [name: string]: string | FakeTree };
function fakeDir(name: string, tree: FakeTree): unknown {
  return {
    name,
    async getDirectoryHandle(child: string, opts?: { create?: boolean }) {
      if (!(child in tree)) {
        if (!opts?.create) throw new DOMException('missing', 'NotFoundError');
        tree[child] = {};
      }
      const sub = tree[child];
      if (typeof sub === 'string') throw new DOMException('not a dir', 'TypeMismatchError');
      return fakeDir(child, sub);
    },
    async getFileHandle(file: string, opts?: { create?: boolean }) {
      if (!(file in tree) && !opts?.create) throw new DOMException('missing', 'NotFoundError');
      return {
        async getFile() { return { text: async () => tree[file] as string }; },
        async createWritable() {
          let buf = '';
          return {
            async write(data: Blob | string) { buf = typeof data === 'string' ? data : '<blob>'; },
            async close() { tree[file] = buf; },
          };
        },
      };
    },
  };
}

describe('repoWriter.mergeManifest', () => {
  afterEach(() => { delete (window as unknown as { showDirectoryPicker?: unknown }).showDirectoryPicker; });

  it('re-reads manifest.json from disk so entries written by a concurrent CLI run survive', async () => {
    const thumbs: FakeTree = { 'manifest.json': JSON.stringify({ old: { thumbnail_url: 'thumbnails/old.png', generated_at: 't0' } }) };
    const repo: FakeTree = { public: { thumbnails: thumbs } };
    (window as unknown as { showDirectoryPicker: unknown }).showDirectoryPicker = async () => fakeDir('repo', repo);

    const writer = await pickRepoWriter();
    expect(writer.label).toBe('repo/public/thumbnails');
    expect(writer.canWriteReports).toBe(true);

    // A CLI run lands after the writer was created.
    const onDisk = JSON.parse(thumbs['manifest.json'] as string);
    onDisk.cli = { thumbnail_url: 'thumbnails/cli.png', generated_at: 't1', source_hash: 'c' };
    thumbs['manifest.json'] = JSON.stringify(onDisk);

    const merged = await writer.mergeManifest({ app: { thumbnail_url: 'thumbnails/app.png', generated_at: 't2', source_hash: 'a' } });
    expect(Object.keys(merged).sort()).toEqual(['app', 'cli', 'old']);
    const written = thumbs['manifest.json'] as string;
    expect(Object.keys(JSON.parse(written)).sort()).toEqual(['app', 'cli', 'old']);
    expect(written.endsWith('}\n')).toBe(true);
  });

  it('rejects a folder that is not the repo or public/thumbnails', async () => {
    (window as unknown as { showDirectoryPicker: unknown }).showDirectoryPicker = async () => fakeDir('Downloads', {});
    await expect(pickRepoWriter()).rejects.toThrow(/not the image_video_effects repo root/);
  });
});
