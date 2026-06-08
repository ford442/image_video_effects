import {
    SHARED_CHAIN_VERSION,
    MAX_SHARED_SLOTS,
    DEFAULT_SLOT_PARAMS,
    SharedChain,
    SharedChainSlot,
    buildSharedChain,
    expandSharedChain,
    encodeChain,
    decodeChain,
} from './layerChainShare';
import { SlotParams } from '../renderer/types';

function makeParams(overrides: Partial<SlotParams> = {}): SlotParams {
    return { ...DEFAULT_SLOT_PARAMS, ...overrides };
}

/** Encodes arbitrary (possibly malformed) payloads the same way encodeChain does, bypassing its validation. */
function encodeRaw(obj: unknown): string {
    const binary = unescape(encodeURIComponent(JSON.stringify(obj)));
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

describe('layerChainShare', () => {
    describe('round-trip', () => {
        it('encodes and decodes a simple chain losslessly', () => {
            const chain: SharedChain = {
                v: SHARED_CHAIN_VERSION,
                slots: [
                    { shaderId: 'liquid-metal', params: { zoomParam1: 0.3 } },
                    { shaderId: 'cosmic-flow' },
                    { shaderId: null },
                ],
            };

            const encoded = encodeChain(chain);
            expect(typeof encoded).toBe('string');
            // URL-safe: no '+', '/', or '=' padding
            expect(encoded).not.toMatch(/[+/=]/);

            const decoded = decodeChain(encoded);
            expect(decoded).toEqual(chain);
        });

        it('round-trips many random valid chains', () => {
            const shaderIds = ['liquid-metal', 'cosmic-flow', 'crystal-facets', 'fractal-kaleidoscope', null];

            for (let i = 0; i < 25; i++) {
                const slotCount = 1 + Math.floor(Math.random() * MAX_SHARED_SLOTS);
                const slots: SharedChainSlot[] = [];
                for (let s = 0; s < slotCount; s++) {
                    const shaderId = shaderIds[Math.floor(Math.random() * shaderIds.length)];
                    const slot: SharedChainSlot = { shaderId };
                    if (shaderId && Math.random() > 0.5) {
                        slot.params = { zoomParam1: Math.round(Math.random() * 100) / 100 };
                    }
                    if (Math.random() > 0.7) slot.enabled = false;
                    if (Math.random() > 0.7) slot.mode = 'parallel';
                    slots.push(slot);
                }

                const chain: SharedChain = { v: SHARED_CHAIN_VERSION, slots };
                const decoded = decodeChain(encodeChain(chain));
                expect(decoded).toEqual(chain);
            }
        });

        it('round-trips through buildSharedChain / expandSharedChain', () => {
            const modes = ['liquid-metal', 'none', 'cosmic-flow', 'none', 'none', 'none'];
            const slotParams: SlotParams[] = [
                makeParams({ zoomParam1: 0.42 }),
                makeParams(),
                makeParams({ lightStrength: 2.0 }),
                makeParams(),
                makeParams(),
                makeParams(),
            ];

            const chain = buildSharedChain(modes, slotParams);
            const encoded = encodeChain(chain);
            const decoded = decodeChain(encoded);
            expect(decoded).not.toBeNull();

            const expanded = expandSharedChain(decoded!);
            expect(expanded.modes).toEqual(['liquid-metal', null, 'cosmic-flow', null, null, null]);
            expect(expanded.slotParams[0].zoomParam1).toBeCloseTo(0.42);
            expect(expanded.slotParams[1]).toEqual(DEFAULT_SLOT_PARAMS);
            expect(expanded.slotParams[2].lightStrength).toBeCloseTo(2.0);
        });
    });

    describe('default-param compaction', () => {
        it('drops params equal to defaults and re-expands them on decode', () => {
            const modes = ['liquid-metal'];
            const slotParams: SlotParams[] = [makeParams({ zoomParam1: 0.42, lightStrength: DEFAULT_SLOT_PARAMS.lightStrength })];

            const chain = buildSharedChain(modes, slotParams);
            expect(chain.slots[0].params).toEqual({ zoomParam1: 0.42 });

            const expanded = expandSharedChain(chain);
            expect(expanded.slotParams[0]).toEqual(makeParams({ zoomParam1: 0.42 }));
        });

        it('omits params entirely when the slot matches all defaults', () => {
            const chain = buildSharedChain(['liquid-metal'], [makeParams()]);
            expect(chain.slots[0].params).toBeUndefined();
        });

        it('treats null/none shader ids as empty slots', () => {
            const chain = buildSharedChain(['none', null as any], [makeParams(), makeParams()]);
            expect(chain.slots[0].shaderId).toBeNull();
            expect(chain.slots[1].shaderId).toBeNull();
            expect(chain.slots[0].params).toBeUndefined();
        });
    });

    describe('clamping to MAX_SHARED_SLOTS', () => {
        it('clamps an over-long chain on encode rather than crashing', () => {
            const slots: SharedChainSlot[] = Array.from({ length: 9 }, (_, i) => ({ shaderId: `shader-${i}` }));
            const encoded = encodeChain({ v: SHARED_CHAIN_VERSION, slots });
            const decoded = decodeChain(encoded);

            expect(decoded).not.toBeNull();
            expect(decoded!.slots.length).toBe(MAX_SHARED_SLOTS);
            expect(decoded!.slots.map(s => s.shaderId)).toEqual(['shader-0', 'shader-1', 'shader-2', 'shader-3', 'shader-4', 'shader-5']);
        });

        it('clamps an over-long chain on build', () => {
            const modes = Array.from({ length: 10 }, (_, i) => `shader-${i}`);
            const slotParams = Array.from({ length: 10 }, () => makeParams());
            const chain = buildSharedChain(modes, slotParams);
            expect(chain.slots.length).toBe(MAX_SHARED_SLOTS);
        });
    });

    describe('malformed-input safety', () => {
        it('returns null for empty input', () => {
            expect(decodeChain('')).toBeNull();
        });

        it('returns null for non-base64url garbage', () => {
            expect(decodeChain('!!!not-valid-base64!!!')).toBeNull();
        });

        it('returns null for valid base64 that is not JSON', () => {
            const encoded = btoa('not json at all {{{').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
            expect(decodeChain(encoded)).toBeNull();
        });

        it('returns null for JSON missing required fields', () => {
            expect(decodeChain(encodeRaw({}))).toBeNull();
            expect(decodeChain(encodeRaw({ v: 1 }))).toBeNull();
            expect(decodeChain(encodeRaw({ slots: [] }))).toBeNull();
            expect(decodeChain(encodeRaw({ v: 1, slots: 'not-an-array' }))).toBeNull();
        });

        it('drops malformed slot entries but keeps valid ones', () => {
            const decoded = decodeChain(encodeRaw({
                v: SHARED_CHAIN_VERSION,
                slots: [
                    { shaderId: 'liquid-metal' },
                    { shaderId: 12345 },
                    { shaderId: null, mode: 'sideways' },
                    { notAShader: true },
                ],
            }));

            expect(decoded).not.toBeNull();
            expect(decoded!.slots).toEqual([{ shaderId: 'liquid-metal' }]);
        });

        it('never throws on garbage input', () => {
            const garbageInputs = [
                'a',
                'a'.repeat(5000),
                '====',
                '🎉🎉🎉',
                JSON.stringify({ v: 1, slots: null }),
            ];
            for (const input of garbageInputs) {
                expect(() => decodeChain(input)).not.toThrow();
            }
        });
    });

    describe('version migration', () => {
        it('rejects future/unknown versions safely', () => {
            const encodeRaw = (obj: any) => encodeChain(obj as any);

            const decoded = decodeChain(encodeRaw({ v: 999, slots: [{ shaderId: 'liquid-metal' }] }));
            expect(decoded).toBeNull();
        });

        it('decodes the current version', () => {
            const encoded = encodeChain({ v: SHARED_CHAIN_VERSION, slots: [{ shaderId: 'liquid-metal' }] });
            const decoded = decodeChain(encoded);
            expect(decoded?.v).toBe(SHARED_CHAIN_VERSION);
        });
    });
});
