/**
 * Writes thumbnails straight into the local repo checkout via the File System
 * Access API (Chrome / Edge). The user picks the repo root once per session;
 * picking public/thumbnails directly also works (no failure report then).
 */
import type { ThumbnailManifest } from './freshness';

// Minimal File System Access typings (not in TS lib.dom).
interface FsWritable {
  write(data: Blob | string): Promise<void>;
  close(): Promise<void>;
}
interface FsFileHandle {
  getFile(): Promise<File>;
  createWritable(): Promise<FsWritable>;
}
interface FsDirHandle {
  name: string;
  getDirectoryHandle(name: string, opts?: { create?: boolean }): Promise<FsDirHandle>;
  getFileHandle(name: string, opts?: { create?: boolean }): Promise<FsFileHandle>;
  requestPermission?(desc: { mode: 'readwrite' }): Promise<PermissionState>;
}
type PickerWindow = Window & {
  showDirectoryPicker?: (opts?: { id?: string; mode?: 'readwrite' }) => Promise<FsDirHandle>;
};

export interface RepoThumbnailWriter {
  /** Human-readable target shown in the UI. */
  label: string;
  canWriteReports: boolean;
  readManifest(): Promise<ThumbnailManifest>;
  /** Re-reads the manifest on disk and merges `entries` into it, so concurrent CLI runs are not clobbered. */
  mergeManifest(entries: ThumbnailManifest): Promise<ThumbnailManifest>;
  writePng(id: string, pngB64: string): Promise<void>;
  writeReport(fileName: string, payload: unknown): Promise<void>;
}

export function isRepoWriterSupported(): boolean {
  return typeof (window as PickerWindow).showDirectoryPicker === 'function';
}

async function tryDir(parent: FsDirHandle, ...names: string[]): Promise<FsDirHandle | null> {
  let dir = parent;
  for (const n of names) {
    try {
      dir = await dir.getDirectoryHandle(n);
    } catch {
      return null;
    }
  }
  return dir;
}

async function hasFile(dir: FsDirHandle, name: string): Promise<boolean> {
  try {
    await dir.getFileHandle(name);
    return true;
  } catch {
    return false;
  }
}

async function writeFile(dir: FsDirHandle, name: string, data: Blob | string): Promise<void> {
  const handle = await dir.getFileHandle(name, { create: true });
  const w = await handle.createWritable();
  await w.write(data);
  await w.close();
}

export async function pickRepoWriter(): Promise<RepoThumbnailWriter> {
  const picker = (window as PickerWindow).showDirectoryPicker;
  if (!picker) {
    throw new Error('Saving thumbnails needs the File System Access API — open the app in Chrome or Edge.');
  }
  const root = await picker({ id: 'pixelocity-repo', mode: 'readwrite' });
  if (root.requestPermission && (await root.requestPermission({ mode: 'readwrite' })) !== 'granted') {
    throw new Error('Write permission was not granted for the selected folder.');
  }

  let thumbsDir: FsDirHandle | null = null;
  let reportsDir: FsDirHandle | null = null;
  let label = root.name;
  if (await hasFile(root, 'manifest.json')) {
    thumbsDir = root; // picked public/thumbnails itself
    label = `${root.name}/`;
  } else {
    thumbsDir = await tryDir(root, 'public', 'thumbnails');
    if (thumbsDir && (await hasFile(thumbsDir, 'manifest.json'))) {
      reportsDir = await root.getDirectoryHandle('reports', { create: true });
      label = `${root.name}/public/thumbnails`;
    } else {
      thumbsDir = null;
    }
  }
  if (!thumbsDir) {
    throw new Error(
      `"${root.name}" is not the image_video_effects repo root (no public/thumbnails/manifest.json). ` +
        'Pick the repo folder or its public/thumbnails folder.',
    );
  }
  const dir = thumbsDir;

  const readManifest = async (): Promise<ThumbnailManifest> => {
    const file = await (await dir.getFileHandle('manifest.json')).getFile();
    return JSON.parse(await file.text()) as ThumbnailManifest;
  };

  return {
    label,
    canWriteReports: reportsDir !== null,
    readManifest,
    async mergeManifest(entries) {
      const onDisk = await readManifest();
      const merged = { ...onDisk, ...entries };
      // Same format as the CLI writers (2-space, trailing newline) so the two paths don't churn diffs.
      await writeFile(dir, 'manifest.json', JSON.stringify(merged, null, 2) + '\n');
      return merged;
    },
    async writePng(id, pngB64) {
      const bytes = Uint8Array.from(atob(pngB64), c => c.charCodeAt(0));
      await writeFile(dir, `${id}.png`, new Blob([bytes], { type: 'image/png' }));
    },
    async writeReport(fileName, payload) {
      if (!reportsDir) throw new Error('Reports folder unavailable — pick the repo root to save reports.');
      await writeFile(reportsDir, fileName, JSON.stringify(payload, null, 2));
    },
  };
}
