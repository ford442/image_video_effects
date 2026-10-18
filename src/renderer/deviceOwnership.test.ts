/**
 * One GPUDevice owner: only the boot probe requests an adapter or a device.
 * Device-loss recovery reruns that probe through the backend's init; nothing
 * else in src/ may acquire one (gpu-chores, depth, validators adopt instead).
 */
import { readdirSync, readFileSync, statSync } from 'fs';
import { join, relative } from 'path';

const SRC = join(__dirname, '..');
const ALLOWED = new Set(['renderer/webgpuBootProbe.ts']);

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.(ts|tsx)$/.test(name) && !/\.test\.tsx?$/.test(name) ? [path] : [];
  });
}

describe('GPUDevice ownership', () => {
  it('requestAdapter / requestDevice are only called by the boot probe', () => {
    const offenders: string[] = [];
    for (const file of sourceFiles(SRC)) {
      const rel = relative(SRC, file).split('\\').join('/');
      if (ALLOWED.has(rel)) continue;
      readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
        const code = line.trim();
        if (code.startsWith('*') || code.startsWith('//') || code.startsWith('/*')) return;
        if (/\.(requestAdapter|requestDevice)\s*\(/.test(code)) offenders.push(`${rel}:${i + 1}`);
      });
    }
    expect(offenders).toEqual([]);
  });
});
