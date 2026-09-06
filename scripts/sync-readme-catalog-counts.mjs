#!/usr/bin/env node
/**
 * sync-readme-catalog-counts.mjs — patch README catalog totals from manifest + lists.
 *
 * Run after: npm run build:manifest
 */

import fs from 'node:fs';
import {
  LISTS_DIR,
  MANIFEST_PATH,
  README_PATH,
  formatCount,
  loadJson,
  countListIds,
  replaceMarkedSection,
} from './catalog-count-utils.mjs';

const CATEGORY_DESCRIPTIONS = {
  generative: 'Procedural art, fractals, generative patterns',
  'interactive-mouse': 'Mouse and touch-driven interactions',
  'advanced-hybrid': 'Multi-technique / advanced hybrid stacks',
  artistic: 'Creative and artistic visual effects',
  image: 'Image processing and filtering',
  distortion: 'Spatial warping and distortion',
  simulation: 'Physics simulations, cellular automata',
  'visual-effects': 'Post-processing and visual enhancements',
  'retro-glitch': 'Retro aesthetics and glitch art',
  'liquid-effects': 'Fluid and liquid simulations',
  'post-processing': 'Color grading, bloom, composite passes',
  hybrid: 'Combined technique shaders',
  geometric: 'Geometric patterns and tessellations',
  'lighting-effects': 'Volumetric lighting and glow',
};

function buildCategoryTable(byCategory, total, categoryCount) {
  const rows = Object.entries(byCategory)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([category, count]) => {
      const desc = CATEGORY_DESCRIPTIONS[category] ?? '';
      return `| **${category}** | ${count} | ${desc} |`;
    });

  return [
    '| Category | Count | Description |',
    '|----------|------:|-------------|',
    ...rows,
    `| **Total** | **${formatCount(total)}** | ${categoryCount} canonical categories |`,
  ].join('\n');
}

function underscoreCatalogCount(listIds) {
  return [...listIds].filter(id => id.includes('_')).length;
}

function main() {
  if (!fs.existsSync(MANIFEST_PATH)) {
    console.error(`Missing ${MANIFEST_PATH} — run npm run build:manifest first`);
    process.exit(1);
  }

  const manifest = loadJson(MANIFEST_PATH);
  const total = manifest?._meta?.total_count ?? manifest.shaders?.length ?? 0;
  const categories = manifest?._meta?.categories?.length ?? 14;
  const { byCategory, ids: listIds } = countListIds(LISTS_DIR);
  const formatted = formatCount(total);
  const underscoreCount = underscoreCatalogCount(listIds);

  let readme = fs.readFileSync(README_PATH, 'utf8');
  const before = readme;

  readme = replaceMarkedSection(
    readme,
    'catalog-counts:intro',
    `A React + WebGPU app for real-time GPU shader effects — fluids, generative art, audio-reactive visuals, AI depth estimation, and a catalog of **${formatted}** compute shaders across ${categories} categories.`,
  );

  readme = replaceMarkedSection(
    readme,
    'catalog-counts:features',
    `- **${formatted} shader effects** — counts from \`public/shader-manifest-unified.json\` (regenerate: \`npm run build:manifest\`; gate: \`npm run verify:catalog-counts\`)`,
  );

  readme = replaceMarkedSection(
    readme,
    'catalog-counts:table',
    buildCategoryTable(byCategory, total, categories),
  );

  readme = replaceMarkedSection(
    readme,
    'catalog-counts:structure',
    `│   ├── shaders/                    # WGSL compute shaders (${formatted} catalog ids; more pass files on disk)`,
  );

  readme = replaceMarkedSection(
    readme,
    'catalog-counts:legacy-ids',
    `**Legacy underscore ids:** ${underscoreCount} catalog ids use underscores (\`aurora_borealis\`, \`kimi_flock_symphony\`, …). New shaders must use hyphens. Share URLs with hyphens resolve via \`public/shader-id-aliases.json\` (\`resolveShaderId\` in the app).`,
  );

  if (readme !== before) {
    fs.writeFileSync(README_PATH, readme);
    console.log(`sync-readme-catalog-counts: updated README (${formatted} shaders)`);
  } else {
    console.log(`sync-readme-catalog-counts: README already up to date (${formatted} shaders)`);
  }
}

main();
