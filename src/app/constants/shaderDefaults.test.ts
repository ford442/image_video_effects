import { getShaderDefaults, SHADER_DEFAULTS } from './shaderDefaults';

describe('getShaderDefaults', () => {
    it('returns exact ID match from SHADER_DEFAULTS', () => {
        expect(getShaderDefaults('liquid', 4)).toEqual(SHADER_DEFAULTS.liquid);
    });

    it('strips .wgsl extension when looking up defaults', () => {
        expect(getShaderDefaults('liquid.wgsl', 4)).toEqual(SHADER_DEFAULTS.liquid);
    });

    it('appends .wgsl when lookup key includes extension', () => {
        const withExt = Object.keys(SHADER_DEFAULTS).find((k) => k.endsWith('.wgsl'));
        if (withExt) {
            const base = withExt.replace(/\.wgsl$/, '');
            expect(getShaderDefaults(base, 4)).toEqual(SHADER_DEFAULTS[withExt]);
        } else {
            expect(getShaderDefaults('liquid.wgsl', 4)).toEqual(SHADER_DEFAULTS.liquid);
        }
    });

    it('normalizes kebab-case to snake_case', () => {
        const kebabKey = Object.keys(SHADER_DEFAULTS).find((k) => k.includes('-'));
        if (kebabKey) {
            const snake = kebabKey.replace(/-/g, '_');
            expect(getShaderDefaults(snake, 4)).toEqual(SHADER_DEFAULTS[kebabKey]);
        }
    });

    it('normalizes snake_case to kebab-case', () => {
        const snakeKey = 'liquid_chrome_ripple';
        expect(getShaderDefaults(snakeKey, 4)).toEqual(SHADER_DEFAULTS['liquid-chrome-ripple']);
    });

    it('normalizes gen_ prefix to gen-', () => {
        expect(getShaderDefaults('gen_crystalline-chrono-dyson', 4)).toEqual(
            SHADER_DEFAULTS['gen-crystalline-chrono-dyson'],
        );
    });

    it('falls back to 0.5 array for unknown shader', () => {
        expect(getShaderDefaults('nonexistent-shader-xyz', 4)).toEqual([0.5, 0.5, 0.5, 0.5]);
    });

    it('respects numParams for truncation', () => {
        const full = getShaderDefaults('liquid', 4);
        expect(getShaderDefaults('liquid', 2)).toEqual(full.slice(0, 2));
    });

    it('returns at most padded length of four when defaults exist', () => {
        const four = getShaderDefaults('liquid', 4);
        expect(getShaderDefaults('liquid', 6)).toEqual(four);
    });
});
