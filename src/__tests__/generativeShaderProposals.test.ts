import fs from 'fs';
import path from 'path';

const repoRoot = process.cwd();
const generativeDefinitionsDir = path.join(repoRoot, 'shader_definitions', 'generative');
const publicDir = path.join(repoRoot, 'public');

const proposalIds = [
  'gen-chrono-mycelial-tapestry',
  'gen-topological-phase-weave',
  'gen-recursive-ancestral-terrains',
  'gen-gravito-phononic-accretion',
  'gen-emergent-script-gardens',
];

describe('generative shader proposals', () => {
  test.each(proposalIds)('%s has a definition and compute shader', (id) => {
    const definitionPath = path.join(generativeDefinitionsDir, `${id}.json`);
    expect(fs.existsSync(definitionPath)).toBe(true);

    const definition = JSON.parse(fs.readFileSync(definitionPath, 'utf8'));
    expect(definition.id).toBe(id);
    expect(definition.category).toBe('generative');
    expect(definition.url).toMatch(/^shaders\/.+\.wgsl$/);

    const shaderPath = path.join(publicDir, definition.url);
    expect(fs.existsSync(shaderPath)).toBe(true);

    const shader = fs.readFileSync(shaderPath, 'utf8');
    expect(shader).toContain('@compute');
    expect(shader).toContain('fn main(');
    expect(shader).toContain('@group(0) @binding(12)');
  });
});
