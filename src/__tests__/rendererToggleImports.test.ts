import fs from 'fs';
import path from 'path';

const SRC_ROOT = path.join(__dirname, '..');
const ALLOWED_RENDERER_TOGGLE_IMPORTS = new Set([
  path.join(SRC_ROOT, 'components', 'shaders', 'ShaderDemo.tsx'),
  path.join(SRC_ROOT, 'components', 'shaders', 'RendererToggle.tsx'),
  path.join(SRC_ROOT, 'components', 'shaders', 'index.ts'),
]);

function collectSourceFiles(dir: string): string[] {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === '__tests__') continue;
      files.push(...collectSourceFiles(fullPath));
      continue;
    }
    if (/\.(ts|tsx)$/.test(entry.name)) {
      files.push(fullPath);
    }
  }
  return files;
}

describe('deprecated renderer toggle imports', () => {
  test('RendererToggle is only imported from shader demo paths', () => {
    const offenders: string[] = [];

    for (const file of collectSourceFiles(SRC_ROOT)) {
      if (ALLOWED_RENDERER_TOGGLE_IMPORTS.has(file)) continue;
      const content = fs.readFileSync(file, 'utf8');
      if (/from\s+['"][^'"]*RendererToggle['"]/.test(content)) {
        offenders.push(path.relative(SRC_ROOT, file));
      }
    }

    expect(offenders).toEqual([]);
  });

  test('WASMToggle is not imported anywhere in src', () => {
    const offenders: string[] = [];

    for (const file of collectSourceFiles(SRC_ROOT)) {
      const content = fs.readFileSync(file, 'utf8');
      if (/from\s+['"][^'"]*WASMToggle['"]/.test(content)) {
        offenders.push(path.relative(SRC_ROOT, file));
      }
    }

    expect(offenders).toEqual([]);
  });
});
