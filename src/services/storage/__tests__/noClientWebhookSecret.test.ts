/**
 * #1511 bug 2: the storage webhook HMAC secret must never ship in the browser bundle.
 * Signing happens in storage_manager's /api/webhook-proxy route.
 */
import fs from 'fs';
import path from 'path';

const REPO_ROOT = path.join(__dirname, '..', '..', '..', '..');
const SRC_ROOT = path.join(REPO_ROOT, 'src');
// Built by concatenation so this file does not match its own scan.
const FORBIDDEN = ['WEBHOOK' + '_SECRET', 'your-webhook-' + 'secret-here'];

function collectSourceFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'node_modules') files.push(...collectSourceFiles(fullPath));
    } else if (/\.(ts|tsx|js|jsx|mjs)$/.test(entry.name)) {
      files.push(fullPath);
    }
  }
  return files;
}

describe('no client-side webhook secret (#1511 bug 2)', () => {
  test.each(FORBIDDEN)('no file under src/ or vite.config.ts contains %s', (needle) => {
    const files = [...collectSourceFiles(SRC_ROOT), path.join(REPO_ROOT, 'vite.config.ts')];
    const offenders = files
      .filter((file) => fs.readFileSync(file, 'utf8').includes(needle))
      .map((file) => path.relative(REPO_ROOT, file));
    expect(offenders).toEqual([]);
  });

  test('KNOWN_APP_ENV in vite.config.ts does not inline a webhook secret', () => {
    const viteConfig = fs.readFileSync(path.join(REPO_ROOT, 'vite.config.ts'), 'utf8');
    const list = /const KNOWN_APP_ENV = \[([\s\S]*?)\];/.exec(viteConfig)?.[1];
    expect(list).toBeDefined();
    expect(list).toContain('REACT_APP_STORAGE_API_URL');
    expect(list ?? '').not.toMatch(/SECRET/i);
  });
});
