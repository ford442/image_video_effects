import { mapVJStackToSharedChain, buildCatalogDefaultsLookup } from './vjToSharedChain';
import {
    DEFAULT_SLOT_PARAMS,
    MAX_SHARED_SLOTS,
    encodeChain,
    decodeChain,
    expandSharedChain,
} from './layerChainShare';
import { mapOrderedParamsToSlotParams } from '../utils/shaderParamMapping';
import { CatalogShader, CatalogParam } from './shaderCatalog';

// ── Test catalog ──────────────────────────────────────────────────────────────

function param(id: string, def = 0.5): CatalogParam {
    return { id, name: id, default: def, min: 0, max: 1 };
}

function shader(id: string, paramIds: string[], defaults: number[] = []): CatalogShader {
    return {
        id,
        name: id,
        category: 'test',
        tags: [],
        description: '',
        params: paramIds.map((p, i) => param(p, defaults[i] ?? 0.5)),
        searchText: id,
    };
}

const CATALOG: CatalogShader[] = [
    // 5 params to exercise the "only first 4 map" rule
    shader('liquid', ['speed', 'scale', 'warp', 'hue', 'extra'], [0.2, 0.4, 0.6, 0.8, 0.5]),
    shader('plasma', ['freq', 'amp'], [0.1, 0.9]),
    shader('glitch', ['amount'], [0.5]),
    shader('a', ['p0', 'p1', 'p2', 'p3'], [0.1, 0.2, 0.3, 0.4]),
    shader('b', ['p0'], [0.7]),
    shader('c', ['p0'], [0.7]),
    shader('d', ['p0'], [0.7]),
    shader('e', ['p0'], [0.7]),
    shader('f', ['p0'], [0.7]),
    shader('g', ['p0'], [0.7]),
];

const KNOWN = new Set(CATALOG.map(s => s.id));

let warnSpy: jest.SpyInstance;
beforeEach(() => {
    warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});
});
afterEach(() => {
    warnSpy.mockRestore();
});

describe('mapVJStackToSharedChain', () => {
    it('handles an empty stack (0 shaders)', () => {
        const chain = mapVJStackToSharedChain([], [], CATALOG, KNOWN);
        expect(chain.slots).toHaveLength(0);
        expect(warnSpy).not.toHaveBeenCalled();
    });

    it('handles a single shader', () => {
        const chain = mapVJStackToSharedChain(
            ['plasma'],
            [{ freq: 0.3, amp: 0.7 }],
            CATALOG,
            KNOWN,
        );
        expect(chain.slots).toHaveLength(1);
        expect(chain.slots[0].shaderId).toBe('plasma');
        // freq → zoomParam1, amp → zoomParam2
        expect(chain.slots[0].params).toMatchObject({ zoomParam1: 0.3, zoomParam2: 0.7 });
    });

    it('keeps exactly 6 shaders without truncation', () => {
        const ids = ['a', 'b', 'c', 'd', 'e', 'f'];
        const params = ids.map(() => ({}));
        const chain = mapVJStackToSharedChain(ids, params, CATALOG, KNOWN);
        expect(chain.slots).toHaveLength(MAX_SHARED_SLOTS);
        expect(warnSpy).not.toHaveBeenCalledWith(expect.stringContaining('truncating'));
    });

    it('truncates to MAX_SHARED_SLOTS when given 7+ shaders, warning once', () => {
        const ids = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
        const params = ids.map(() => ({}));
        const chain = mapVJStackToSharedChain(ids, params, CATALOG, KNOWN);
        expect(chain.slots).toHaveLength(MAX_SHARED_SLOTS);
        expect(chain.slots.map(s => s.shaderId)).toEqual(['a', 'b', 'c', 'd', 'e', 'f']);
        expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('truncating'));
    });

    it('drops unknown shader ids (warn + skip), keeping remaining slots tightly packed', () => {
        const chain = mapVJStackToSharedChain(
            ['plasma', 'does-not-exist', 'glitch'],
            [{ freq: 0.3 }, { whatever: 0.9 }, { amount: 0.6 }],
            CATALOG,
            KNOWN,
        );
        expect(chain.slots.map(s => s.shaderId)).toEqual(['plasma', 'glitch']);
        expect(chain.slots[1].params).toMatchObject({ zoomParam1: 0.6 });
        expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('does-not-exist'));
    });

    it('maps only the first four catalog params to zoomParam1-4 (parity with shared helper)', () => {
        const vjParams = { speed: 0.11, scale: 0.22, warp: 0.33, hue: 0.44, extra: 0.99 };
        const chain = mapVJStackToSharedChain(['liquid'], [vjParams], CATALOG, KNOWN);

        const orderedIds = CATALOG.find(s => s.id === 'liquid')!.params.map(p => p.id);
        const expected = mapOrderedParamsToSlotParams(vjParams, orderedIds);

        // 5th param ('extra') must not leak into any SlotParams field.
        expect(expected).toEqual({ zoomParam1: 0.11, zoomParam2: 0.22, zoomParam3: 0.33, zoomParam4: 0.44 });
        expect(chain.slots[0].params).toMatchObject(expected);
        expect(chain.slots[0].params).not.toHaveProperty('zoomParam5');
    });

    it('compacts default-valued params away when a defaultsLookup is provided', () => {
        // 'a' has per-shader defaults [0.1,0.2,0.3,0.4]. Feeding those exact values
        // with the matching lookup should compact every param out → no params key.
        const lookup = buildCatalogDefaultsLookup(CATALOG);
        const chain = mapVJStackToSharedChain(
            ['a'],
            [{ p0: 0.1, p1: 0.2, p2: 0.3, p3: 0.4 }],
            CATALOG,
            KNOWN,
            lookup,
        );
        expect(chain.slots[0].shaderId).toBe('a');
        expect(chain.slots[0].params).toBeUndefined();
    });

    it('does NOT over-compact against per-shader defaults when no lookup is given', () => {
        // Same values, but without a lookup the generic DEFAULT_SLOT_PARAMS are the
        // baseline, so the non-default values are retained (app round-trip safety).
        const chain = mapVJStackToSharedChain(
            ['a'],
            [{ p0: 0.1, p1: 0.2, p2: 0.3, p3: 0.4 }],
            CATALOG,
            KNOWN,
        );
        expect(chain.slots[0].params).toMatchObject({
            zoomParam1: 0.1, zoomParam2: 0.2, zoomParam3: 0.3, zoomParam4: 0.4,
        });
    });

    it('round-trips through encode→decode→expand (app decode path, no lookup)', () => {
        const ids = ['liquid', 'plasma', 'glitch'];
        const params: Record<string, number>[] = [
            { speed: 0.12, scale: 0.34, warp: 0.56, hue: 0.78 },
            { freq: 0.25, amp: 0.65 },
            { amount: 0.45 },
        ];

        const chain = mapVJStackToSharedChain(ids, params, CATALOG, KNOWN);
        const decoded = decodeChain(encodeChain(chain));
        expect(decoded).not.toBeNull();

        // Mirrors App.applySharedChain: expand WITHOUT a defaultsLookup.
        const { modes, slotParams } = expandSharedChain(decoded!);

        expect(modes).toEqual(['liquid', 'plasma', 'glitch']);

        // zoomParam1-4 reproduced for the liquid slot.
        expect(slotParams[0].zoomParam1).toBeCloseTo(0.12);
        expect(slotParams[0].zoomParam2).toBeCloseTo(0.34);
        expect(slotParams[0].zoomParam3).toBeCloseTo(0.56);
        expect(slotParams[0].zoomParam4).toBeCloseTo(0.78);

        // plasma: only first two params set; rest fall back to generic defaults.
        expect(slotParams[1].zoomParam1).toBeCloseTo(0.25);
        expect(slotParams[1].zoomParam2).toBeCloseTo(0.65);
        expect(slotParams[1].zoomParam3).toBeCloseTo(DEFAULT_SLOT_PARAMS.zoomParam3);

        // glitch: single param.
        expect(slotParams[2].zoomParam1).toBeCloseTo(0.45);
    });

    it('tolerates a params array shorter than shaderIds without throwing', () => {
        const chain = mapVJStackToSharedChain(['plasma', 'glitch'], [{ freq: 0.3 }], CATALOG, KNOWN);
        expect(chain.slots.map(s => s.shaderId)).toEqual(['plasma', 'glitch']);
        // glitch had no params entry → no overrides carried.
        expect(chain.slots[1].params).toBeUndefined();
    });
});
