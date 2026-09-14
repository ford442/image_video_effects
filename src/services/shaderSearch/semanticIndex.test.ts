import fs from 'fs';
import path from 'path';
import {
  decodeShaderSearchIndex,
  rankShaderSearch,
  substringFilter,
  type ShaderSearchIndexFile,
} from './semanticIndex';

// Query vectors were precomputed with the same CLIP text tower by
// `node scripts/build-shader-search-index.mjs --emit-fixture`; no model, network or GPU here.
import queryFixture from './__fixtures__/queryEmbeddings.json';

const indexFile = JSON.parse(
  fs.readFileSync(path.join(__dirname, '../../../public/shader-search-index.json'), 'utf8'),
) as ShaderSearchIndexFile;
const index = decodeShaderSearchIndex(indexFile);
const queries = queryFixture.queries as Record<string, number[]>;

function top(query: string, k = 5, queryText?: string): string[] {
  return rankShaderSearch(index, queries[query], { topK: k, queryText }).map(h => h.id);
}

describe('shader search index', () => {
  it('fixture was produced by the index model and recipe', () => {
    expect(queryFixture.model).toBe(indexFile.model);
    expect(queryFixture.dtype).toBe(indexFile.dtype);
    expect(queryFixture.recipe).toBe(indexFile.recipe);
  });

  it('covers every entry with an embedding', () => {
    expect(index.entries.length).toBe(indexFile.count);
    expect(index.vectors.every(Boolean)).toBe(true);
    expect(new Set(index.ids).size).toBe(index.ids.length);
  });

  it('"ferrofluid spikes" returns ferrofluid shaders', () => {
    // Embedding alone: every top-5 hit is a ferrofluid shader.
    const ids = top('ferrofluid spikes');
    expect(ids).toContain('ferrofluid-spikes');
    expect(ids.every(id => /ferro/.test(id))).toBe(true);
    // With the picker's lexical bonus the exact namesake leads.
    expect(top('ferrofluid spikes', 5, 'ferrofluid spikes')[0]).toBe('ferrofluid-spikes');
  });

  it('"halftone rosette" returns halftone shaders', () => {
    const ids = top('halftone rosette', 3);
    expect(ids.every(id => /halftone/.test(id))).toBe(true);
  });

  it('"Gray-Scott tank" and "CRT phosphor" find their namesakes', () => {
    expect(top('Gray-Scott tank', 3)).toContain('gray-scott-tank');
    expect(top('CRT phosphor', 5)).toContain('crt-phosphor-decay');
  });

  it('restricts results to allowIds', () => {
    const allowIds = new Set(['halftone', 'plasma', 'ferrofluid-spikes']);
    const hits = rankShaderSearch(index, queries['halftone rosette'], { allowIds, topK: 10 });
    expect(hits.map(h => h.id).sort()).toEqual([...allowIds].sort());
    expect(hits[0].id).toBe('halftone');
  });

  it('substring fallback matches name or id', () => {
    const items = [
      { id: 'halftone', name: 'Retro Halftone' },
      { id: 'plasma', name: 'Plasma' },
    ];
    expect(substringFilter(items, 'HALF').map(i => i.id)).toEqual(['halftone']);
    expect(substringFilter(items, '  ')).toHaveLength(2);
  });
});
