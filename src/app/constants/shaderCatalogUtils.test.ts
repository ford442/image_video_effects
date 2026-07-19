import { determineCategory } from './shaderCatalogUtils';
import { ShaderEntry as ApiShaderEntry } from '../../services/shaderApi';

function entry(partial: Partial<ApiShaderEntry> & { id: string }): ApiShaderEntry {
    return {
        name: partial.id,
        filename: `${partial.id}.wgsl`,
        type: 'compute',
        format: 'wgsl',
        tags: [],
        url: `/shaders/${partial.id}.wgsl`,
        ...partial,
    };
}

describe('determineCategory', () => {
    it('uses explicit category when valid', () => {
        expect(determineCategory(entry({ id: 'foo', category: 'simulation' }))).toBe('simulation');
    });

    it('infers generative from gen- prefix', () => {
        expect(determineCategory(entry({ id: 'gen-orb' }))).toBe('generative');
    });

    it('infers generative from gen_ prefix', () => {
        expect(determineCategory(entry({ id: 'gen_orb' }))).toBe('generative');
    });

    it('infers generative from tags', () => {
        expect(determineCategory(entry({ id: 'custom', tags: ['generative'] }))).toBe('generative');
    });

    it('infers liquid-effects from fluid tag', () => {
        expect(determineCategory(entry({ id: 'waves', tags: ['fluid'] }))).toBe('liquid-effects');
    });

    it('defaults to image', () => {
        expect(determineCategory(entry({ id: 'plain-effect' }))).toBe('image');
    });
});
