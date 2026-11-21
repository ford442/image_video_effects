import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { DEFAULT_SLOT1_SHADER_ID } from './shaderDefaults';

const root = resolve(__dirname, '../../..');

describe('Slot 1 boot default (frozen reference)', () => {
    it('is liquid-original, with a catalog definition and a shader file', () => {
        expect(DEFAULT_SLOT1_SHADER_ID).toBe('liquid-original');
        expect(existsSync(resolve(root, 'public/shaders/liquid-original.wgsl'))).toBe(true);
        expect(existsSync(resolve(root, 'shader_definitions/liquid-effects/liquid-original.json'))).toBe(true);
    });

    it('stays frozen: DO NOT UPGRADE banner, no Upgraded:/Ideas: lines', () => {
        const src = readFileSync(resolve(root, 'public/shaders/liquid-original.wgsl'), 'utf8');
        const header = src.split('\n').slice(0, 30).join('\n');
        expect(header).toContain('DO NOT UPGRADE');
        expect(header).not.toMatch(/^\/\/\s+Upgraded:/m);
        expect(header).not.toMatch(/^\/\/\s+Ideas:/m);
        expect(src).not.toMatch(/\/\/ ── Idea \d/);
    });
});
