# E1–E3 Handoff Notes for Claude

## Context
Batch 3A chromatic is complete. These three shaders are now ready for Claude's 3E polish pass.

---

## E1: gen-translucent-nebula

**What Kimiclaw changed (Batch 3A):**
- Added chromatic aberration before ACES
- Moved `depthVal` read before chromatic block (was after `writeTexture`)
- No other structural changes

**Current state:**
- 292 lines
- Features: `audio-reactive`, `chromatic-aberration`, `mouse-driven`, `temporal`, `upgraded-rgba`
- Has `dataTextureA` write (pre-ACES color for temporal feedback)
- Uses `bass` directly (no `bass_env`) — candidate for audio polish
- No semantic alpha (alpha = `accumDensity * breath * 0.9 + prevState.a * 0.05`)

**Recommended polish (Claude):**
- [ ] Replace raw `bass` with `bass_env` smoothed envelope
- [ ] Convert any remaining branchful patterns to branchless
- [ ] Add LOD comments if raymarch loop has optimization headroom
- [ ] Verify JSON `features` matches header exactly

**Validation:** `naga public/shaders/gen-translucent-nebula.wgsl` ✅

---

## E2: gen-prismatic-crystal-growth

**What Kimiclaw changed (Batch 3A):**
- Added chromatic aberration before ACES
- Moved raymarch `depthVal = clamp(t/30.0, 0.0, 1.0)` before chromatic block
- `dataTextureA` stores simulation state (`thickness`, `storedGrowth`, `0.0`, `alpha`) — unchanged

**Current state:**
- 356 lines
- Features: `audio-reactive`, `chromatic-aberration`, `mouse-driven`, `raymarched`, `temporal`, `upgraded-rgba`
- Raymarched SDF crystal with Fresnel + caustics
- Raw `bass` usage in `map()` and main

**Recommended polish (Claude):**
- [ ] Add `bass_env` for smoothed audio response
- [ ] Distance-based ray step LOD (reduce `map()` calls at distance)
- [ ] Early-exit optimization for far-miss pixels
- [ ] Check for duplicate helper functions vs other crystal shaders

**Validation:** `naga public/shaders/gen-prismatic-crystal-growth.wgsl` ✅

---

## E3: electric-eel-storm

**What prior batch changed:**
- Chromatic aberration added in Batch 2
- Already has ACES + dataA + temporal

**Current state:**
- No Kimiclaw changes in Batch 3A (excluded from 3A because chromatic was already done)
- Needs LOD polish per swarm board

**Recommended polish (Claude):**
- [ ] Distance-based LOD on eel path recursion / fractal detail
- [ ] Early-exit for off-screen / background pixels
- [ ] `bass_env` if still using raw bass
- [ ] Performance: check texture sample count per pixel

**Validation:** Run `naga` after changes

---

## Shared Validation Commands

```bash
# Per shader
naga public/shaders/{shader-id}.wgsl

# After all three
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```

## JSON Feature Flags to Verify

All three should have:
- `upgraded-rgba`
- `aces-tone-map`
- `chromatic-aberration`
- `depth-aware`
- `audio-reactive`
- `mouse-driven`
- `temporal`

Check for drift: `header Features:` must match `JSON features[]` exactly.
