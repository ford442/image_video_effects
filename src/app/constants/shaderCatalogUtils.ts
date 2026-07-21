import { ShaderCategory } from '../../renderer/types';
import { ShaderEntry as ApiShaderEntry } from '../../services/shaderApi';

const VALID_CATEGORIES: ShaderCategory[] = [
    'image', 'generative', 'simulation', 'distortion', 'artistic',
    'interactive-mouse', 'lighting-effects', 'liquid-effects',
    'retro-glitch', 'visual-effects', 'geometric', 'glitch',
];

export function determineCategory(shader: ApiShaderEntry): ShaderCategory {
    if (shader.category && VALID_CATEGORIES.includes(shader.category as ShaderCategory)) {
        return shader.category as ShaderCategory;
    }

    if (shader.tags?.includes('generative') || shader.id.startsWith('gen-') || shader.id.startsWith('gen_')) {
        return 'generative';
    }
    if (shader.tags?.includes('simulation')) return 'simulation';
    if (shader.tags?.includes('distortion') || shader.tags?.includes('warp')) return 'distortion';
    if (shader.tags?.includes('artistic') || shader.tags?.includes('painterly')) return 'artistic';
    if (shader.tags?.includes('interactive') || shader.tags?.includes('mouse-driven')) return 'interactive-mouse';
    if (shader.tags?.includes('lighting') || shader.tags?.includes('plasma') || shader.tags?.includes('glow')) return 'lighting-effects';
    if (shader.tags?.includes('liquid') || shader.tags?.includes('fluid')) return 'liquid-effects';
    if (shader.tags?.includes('retro') || shader.tags?.includes('glitch') || shader.tags?.includes('vhs')) return 'retro-glitch';
    if (shader.tags?.includes('visual-effects') || shader.tags?.includes('chromatic')) return 'visual-effects';
    if (shader.tags?.includes('geometric') || shader.tags?.includes('tessellation')) return 'geometric';
    return 'image';
}
