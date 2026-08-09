import fs from 'fs';
import path from 'path';

const repoRoot = process.cwd();
const generativeDefinitionsDir = path.join(repoRoot, 'shader_definitions', 'generative');
const shaderDir = path.join(repoRoot, 'public', 'shaders');

const findJsonDefinitions = (dir: string): string[] => {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...findJsonDefinitions(entryPath));
      continue;
    }
    if (entry.name.endsWith('.json')) {
      files.push(entryPath);
    }
  }
  return files;
};

const findBackupShaders = (dir: string): string[] => {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const backups: string[] = [];
  for (const entry of entries) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      backups.push(...findBackupShaders(entryPath));
      continue;
    }
    if (entry.name.endsWith('.wgsl.backup')) {
      backups.push(entryPath);
    }
  }
  return backups;
};

describe('generative catalog hygiene', () => {
  it('keeps category set on every generative definition', () => {
    const files = findJsonDefinitions(generativeDefinitionsDir);
    expect(files.length).toBeGreaterThan(0);

    for (const file of files) {
      const definition = JSON.parse(fs.readFileSync(file, 'utf8'));
      expect(definition.category).toBe('generative');
    }
  });

  it('does not keep stale wgsl backup files in public/shaders', () => {
    const backups = findBackupShaders(shaderDir);
    expect(backups).toEqual([]);
  });
});
