#!/usr/bin/env node
/**
 * generate-shader-id-aliases.mjs — emit hyphen aliases for legacy underscore catalog ids.
 *
 * Writes public/shader-id-aliases.json and syncs src/utils/shader-id-aliases.json (CRA import).
 */

import fs from 'node:fs';
import {
  ALIASES_PUBLIC_PATH,
  ALIASES_SRC_PATH,
  countListIds,
} from './catalog-count-utils.mjs';

function buildAliasMap(catalogIds) {
  const catalogSet = new Set(catalogIds);
  const aliases = {};
  const skippedCollisions = [];

  for (const canonical of [...catalogSet].sort()) {
    if (!canonical.includes('_')) continue;
    const alias = canonical.replace(/_/g, '-');
    if (catalogSet.has(alias)) {
      skippedCollisions.push({
        canonical,
        alias,
        reason: 'hyphen form is already a distinct catalog id',
      });
      continue;
    }
    if (aliases[alias]) {
      throw new Error(`Duplicate alias key "${alias}" for ${canonical} and ${aliases[alias]}`);
    }
    aliases[alias] = canonical;
  }

  return { aliases, skippedCollisions };
}

function writeAliases(filePath, aliases, { craCopy = false, skippedCollisions = [] } = {}) {
  const description = craCopy
    ? 'Hyphen URL aliases for legacy underscore catalog ids. Canonical ids stay underscore; new ids use hyphens. CRA-legal copy of public/shader-id-aliases.json.'
    : 'Hyphen URL aliases for legacy underscore catalog ids. Canonical ids stay underscore; new ids use hyphens.';

  const payload = {
    _meta: {
      description,
      canonical_rule: 'hyphen-alias -> underscore-id',
      generated_at: new Date().toISOString().slice(0, 10),
      count: Object.keys(aliases).length,
      skipped_collisions: skippedCollisions,
    },
    aliases,
  };

  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`);
}

function main() {
  const { ids } = countListIds();
  const { aliases, skippedCollisions } = buildAliasMap(ids);

  writeAliases(ALIASES_PUBLIC_PATH, aliases, { skippedCollisions });
  writeAliases(ALIASES_SRC_PATH, aliases, { craCopy: true, skippedCollisions });

  if (skippedCollisions.length > 0) {
    console.log(
      `generate-shader-id-aliases: skipped ${skippedCollisions.length} collision(s): ` +
      skippedCollisions.map(s => s.canonical).join(', '),
    );
  }
  console.log(
    `generate-shader-id-aliases: wrote ${Object.keys(aliases).length} aliases ` +
    `(public + src/utils)`,
  );
}

main();
