#!/usr/bin/env node
/**
 * Fails when the working tree has changes after `npm ci && npm run build`.
 * prebuild regenerates committed files (shader aliases, search index, ...); if a
 * build changes them, the committed copies are stale — rebuild and commit them.
 */
import { execFileSync } from 'node:child_process';

const out = execFileSync('git', ['status', '--porcelain', '--untracked-files=all'], { encoding: 'utf8' });
const dirty = out.split('\n').filter(Boolean);
if (dirty.length > 0) {
  console.error('verify:clean-tree: the build left the working tree dirty:');
  for (const line of dirty) console.error(`  ${line}`);
  console.error('Run `npm run build` locally and commit the regenerated files.');
  try {
    console.error(execFileSync('git', ['diff', '--stat'], { encoding: 'utf8' }));
  } catch {
    // diff is informational only
  }
  process.exit(1);
}
console.log('verify:clean-tree: working tree clean after build');
