#!/usr/bin/env node
/**
 * validate_shader_definitions.mjs — validate every shader_definitions/<category>/*.json against
 * src/contracts/shader_definition.schema.json (compiled standalone validator) plus the
 * cross-field rules JSON Schema cannot express:
 *
 *   - the file is named <id>.json
 *   - `category`, when present, equals the folder
 *   - ids are unique across the catalog
 *   - param ids are unique within a shader
 *   - min <= default <= max, and min < max, for every param
 *
 * id vs `url` stem (the audit that allows pinned legacy pairs) stays in
 * scripts/audit_catalog_consistency.py, which also checks the WGSL file exists.
 *
 *   node scripts/validate_shader_definitions.mjs            # all definitions
 *   node scripts/validate_shader_definitions.mjs a.json ...  # just these files
 */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DEFINITIONS_DIR = path.join(ROOT, 'shader_definitions');
const require = createRequire(import.meta.url);
const validate = require('../src/contracts/shaderDefinition.validate.js');

function listDefinitionFiles() {
  const files = [];
  for (const dir of fs.readdirSync(DEFINITIONS_DIR).sort()) {
    const full = path.join(DEFINITIONS_DIR, dir);
    if (!fs.statSync(full).isDirectory()) continue;
    for (const f of fs.readdirSync(full).sort()) {
      if (f.endsWith('.json')) files.push(path.join(full, f));
    }
  }
  return files;
}

/** @returns {string[]} human-readable problems for one parsed definition */
export function checkDefinition(def, file) {
  const problems = [];
  if (!validate(def)) {
    for (const e of validate.errors ?? []) {
      const where = e.instancePath || '(root)';
      const extra = e.params?.additionalProperty ? ` '${e.params.additionalProperty}'` : '';
      problems.push(`schema ${where}: ${e.message}${extra}`);
    }
    return problems; // cross-field rules assume a well-shaped object
  }
  const stem = path.basename(file, '.json');
  if (stem !== def.id) problems.push(`file is named '${stem}.json' but id is '${def.id}'`);
  const folder = path.basename(path.dirname(file));
  if (def.category !== undefined && def.category !== folder) {
    problems.push(`category '${def.category}' does not match folder '${folder}'`);
  }
  const seen = new Set();
  for (const p of def.params ?? []) {
    if (seen.has(p.id)) problems.push(`duplicate param id '${p.id}'`);
    seen.add(p.id);
    if (!(p.min < p.max)) problems.push(`param '${p.id}': min ${p.min} is not below max ${p.max}`);
    if (p.default < p.min || p.default > p.max) {
      problems.push(`param '${p.id}': default ${p.default} outside [${p.min}, ${p.max}]`);
    }
  }
  return problems;
}

function main() {
  const args = process.argv.slice(2);
  const files = args.length ? args.map((a) => path.resolve(a)) : listDefinitionFiles();
  const idOwner = new Map();
  let failed = 0;
  for (const file of files) {
    const rel = path.relative(ROOT, file);
    let def;
    try {
      def = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (e) {
      console.error(`${rel}: invalid JSON: ${e.message}`);
      failed += 1;
      continue;
    }
    const problems = checkDefinition(def, file);
    if (def && typeof def.id === 'string') {
      if (idOwner.has(def.id)) problems.push(`id '${def.id}' also defined in ${idOwner.get(def.id)}`);
      else idOwner.set(def.id, rel);
    }
    if (problems.length) {
      failed += 1;
      console.error(`${rel}:`);
      for (const p of problems) console.error(`  - ${p}`);
    }
  }
  if (failed) {
    console.error(`\nvalidate_shader_definitions: ${failed} of ${files.length} definition(s) invalid`);
    console.error('Fix them, or for legacy keys run: python3 scripts/migrate_shader_definitions.py --write');
    process.exit(1);
  }
  console.log(`validate_shader_definitions: ${files.length} definition(s) valid`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
