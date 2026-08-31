import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

// ─── Types ────────────────────────────────────────────────────────────────────

interface ShaderParam {
  id: string;
  name: string;
  default?: number;
  min?: number;
  max?: number;
  step?: number;
  mapping?: string;
  description?: string;
  labels?: string[];
}

interface ShaderEntry {
  id: string;
  name: string;
  url?: string;
  category?: string;
  description?: string;
  tags?: string[];
  features?: string[];
  params?: ShaderParam[];
  advanced_params?: ShaderParam[];
  performance_target?: string;
  [key: string]: unknown;
}

interface AliasMap {
  [alias: string]: string;
}

interface UnifiedManifest {
  _meta: {
    generated_at: string;
    total_count: number;
    categories: string[];
    aliases: AliasMap;
  };
  shaders: ShaderEntry[];
}

// ─── Paths ────────────────────────────────────────────────────────────────────

const PROJECT_ROOT = process.cwd();
const LISTS_DIR = path.join(PROJECT_ROOT, 'public', 'shader-lists');
const OUTPUT_FILE = path.join(PROJECT_ROOT, 'public', 'shader-manifest-unified.json');

const ALLOW_ABSOLUTE_URLS =
  Boolean(process.env.SHADER_LIST_BASE_URL) ||
  Boolean(process.env.REACT_APP_SHADER_BASE_URL) ||
  Boolean(process.env.SHADER_BASE_URL);

const ALIASES_FILE = path.join(PROJECT_ROOT, 'public', 'shader-id-aliases.json');

function loadAliases(): AliasMap {
  if (!fs.existsSync(ALIASES_FILE)) {
    console.warn(`⚠️  Alias file missing: ${ALIASES_FILE} — run: node scripts/generate-shader-id-aliases.mjs`);
    return {};
  }
  try {
    const raw = JSON.parse(fs.readFileSync(ALIASES_FILE, 'utf-8'));
    return (raw.aliases ?? {}) as AliasMap;
  } catch (err) {
    console.error(`❌ Failed to parse ${ALIASES_FILE}: ${(err as Error).message}`);
    process.exit(1);
  }
}

function isAbsoluteShaderUrl(url: unknown): boolean {
  return typeof url === 'string' && /^https?:\/\//.test(url);
}

/** Must match folder names under shader_definitions/ and generate_shader_lists.js output. */
const CANONICAL_LIST_FILES = [
  'advanced-hybrid.json',
  'artistic.json',
  'distortion.json',
  'generative.json',
  'geometric.json',
  'hybrid.json',
  'image.json',
  'interactive-mouse.json',
  'lighting-effects.json',
  'liquid-effects.json',
  'post-processing.json',
  'retro-glitch.json',
  'simulation.json',
  'visual-effects.json',
];

// ─── Main ─────────────────────────────────────────────────────────────────────

function buildUnifiedManifest(): void {
  console.log('🔄 Building unified shader manifest...');

  if (!fs.existsSync(LISTS_DIR)) {
    console.error(`❌ Directory not found: ${LISTS_DIR}`);
    process.exit(1);
  }

  const missingCanonical: string[] = [];
  const jsonFiles = CANONICAL_LIST_FILES.filter((f) => {
    const filePath = path.join(LISTS_DIR, f);
    if (!fs.existsSync(filePath)) {
      missingCanonical.push(f);
      return false;
    }
    return true;
  });

  if (missingCanonical.length > 0) {
    console.error(
      `❌ Missing canonical list file(s) — regenerate with: node scripts/generate_shader_lists.js\n` +
      missingCanonical.map((f) => `   • ${f}`).join('\n'),
    );
    process.exit(1);
  }

  if (jsonFiles.length === 0) {
    console.error(`❌ No JSON files found in ${LISTS_DIR}`);
    process.exit(1);
  }

  const seenIds = new Map<string, string>(); // id → source file
  const allShaders: ShaderEntry[] = [];
  const categories: string[] = [];
  const duplicates: string[] = [];
  let validationErrors = 0;

  for (const file of jsonFiles) {
    const filePath = path.join(LISTS_DIR, file);
    const categoryName = path.basename(file, '.json');

    let entries: unknown;
    try {
      const raw = fs.readFileSync(filePath, 'utf-8');
      entries = JSON.parse(raw);
    } catch (err) {
      console.error(`❌ Failed to parse ${file}: ${(err as Error).message}`);
      process.exit(1);
    }

    if (!Array.isArray(entries)) {
      console.error(`❌ Expected an array in ${file}, got ${typeof entries}`);
      process.exit(1);
    }

    let fileCount = 0;
    for (const raw of entries) {
      const entry = raw as ShaderEntry;

      // Validate required fields
      if (!entry.id || typeof entry.id !== 'string' || entry.id.trim() === '') {
        console.error(
          `❌ Entry in ${file} is missing a valid "id" field: ${JSON.stringify(entry).slice(0, 120)}`
        );
        validationErrors++;
        continue;
      }

      // Normalise name — trim whitespace and fall back to "label" for legacy entries
      if (typeof entry.name === 'string') {
        entry.name = entry.name.trim();
      }
      if (!entry.name || typeof entry.name !== 'string' || entry.name === '') {
        const label = (entry as Record<string, unknown>)['label'];
        if (label && typeof label === 'string' && label.trim() !== '') {
          // Compatibility layer: some older list files use "label" instead of "name"
          console.warn(
            `⚠️  Entry "${entry.id}" in ${file} uses "label" instead of "name" — consider migrating the source file`
          );
          entry.name = label.trim();
        } else {
          console.error(
            `❌ Entry "${entry.id}" in ${file} is missing a valid "name" (or "label") field`
          );
          validationErrors++;
          continue;
        }
      }

      if (isAbsoluteShaderUrl(entry.url) && !ALLOW_ABSOLUTE_URLS) {
        console.error(
          `❌ Entry "${entry.id}" in ${file} has absolute url ${entry.url}. ` +
            'Regenerate shader lists without --base-url or set SHADER_LIST_BASE_URL for deploy builds.'
        );
        validationErrors++;
        continue;
      }

      // Deduplicate on id — first occurrence wins
      if (seenIds.has(entry.id)) {
        duplicates.push(`${entry.id} (in ${file}, already seen in ${seenIds.get(entry.id)})`);
        continue;
      }

      seenIds.set(entry.id, file);
      allShaders.push(entry);
      fileCount++;
    }

    if (!categories.includes(categoryName)) {
      categories.push(categoryName);
    }

    console.log(`  ✓ ${file}: ${fileCount} shaders`);
  }

  // Exit non-zero if any entry failed validation
  if (validationErrors > 0) {
    console.error(`\n❌ ${validationErrors} validation error(s) found. Fix them before continuing.`);
    process.exit(1);
  }

  if (duplicates.length > 0) {
    console.warn(`\n⚠️  Deduplicated ${duplicates.length} entries (first occurrence kept):`);
    duplicates.forEach((d) => console.warn(`   - ${d}`));
  }

  const aliases = loadAliases();

  const manifest: UnifiedManifest = {
    _meta: {
      generated_at: new Date().toISOString(),
      total_count: allShaders.length,
      categories: categories.sort(),
      aliases,
    },
    shaders: allShaders,
  };

  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(manifest, null, 2), 'utf-8');

  console.log(`\n✅ Wrote ${allShaders.length} shaders (${categories.length} categories) to:`);
  console.log(`   ${OUTPUT_FILE}`);

  if (duplicates.length > 0) {
    console.log(`   (${duplicates.length} duplicate IDs skipped)`);
  }

  try {
    execSync('node scripts/sync-readme-catalog-counts.mjs', { stdio: 'inherit' });
  } catch {
    console.error('❌ Failed to sync README catalog counts');
    process.exit(1);
  }
}

buildUnifiedManifest();
