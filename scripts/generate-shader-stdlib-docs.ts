/**
 * Generate docs/SHADER_STDLIB.md from the public/shaders/_std module headers.
 *   npm run shaderlib:docs             # write
 *   npm run shaderlib:docs -- --check  # exit 1 if stale
 */
import fs from 'node:fs';
import path from 'node:path';
import { parseStdModule, STD_DIR, STD_MODULE_NAMES, stdFileName } from '../src/shaderlib/stdlib';
import { renderStdlibDocs } from '../src/shaderlib/stdlibDocs';

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'docs/SHADER_STDLIB.md');
const modules = STD_MODULE_NAMES.map((n) =>
  parseStdModule(fs.readFileSync(path.join(ROOT, STD_DIR, stdFileName(n)), 'utf8')),
);
const md = renderStdlibDocs(modules);
if (process.argv.includes('--check')) {
  const cur = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
  if (cur !== md) {
    console.error('docs/SHADER_STDLIB.md is stale — run: npm run shaderlib:docs');
    process.exit(1);
  }
  console.log('docs/SHADER_STDLIB.md is up to date');
} else {
  fs.writeFileSync(OUT, md);
  console.log(`wrote docs/SHADER_STDLIB.md (${modules.reduce((n, m) => n + m.decls.length, 0)} declarations)`);
}
