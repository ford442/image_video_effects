# F1 Flagship: gen-auroral-ferrofluid-monolith — Kimiclaw Notes

## Before/After

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Lines | 277 | 325 | +48 |
| Features | 4 | 12 | +8 flags |
| ACES | ❌ `col/(1+col)` + gamma | ✅ `acesToneMap` | canonical |
| Chromatic | ❌ none | ✅ standard chunk | +3 lines |
| Temporal | ❌ no dataTextureA/C | ✅ read prev + blend | +8 lines |
| bass_env | ❌ raw bass | ✅ smoothed envelope | +5 lines |
| Semantic alpha | ❌ hardcoded formula | ✅ presence-based | +2 lines |
| Depth | ❌ no writeDepthTexture | ✅ ray distance normalized | +2 lines |
| Branchless | ❌ `if(audio>0.1)` tip glow | ✅ `smoothstep` tip glow | -1 branch |
| mapAurora | ❌ `if(dBox>2.0) return` | ✅ `inRange` multiplier | -1 branch |

## What Changed & Why

### 1. ACES Tone Mapping (lines 33–36)
Replaced the gamma-approximation tone mapper (`col / (1.0 + col)` + `pow(col, 1.0/2.2)`) with canonical `acesToneMap`. This gives better highlight rolloff and consistent color grading across all upgraded shaders.

### 2. bass_env Envelope Smoothing (lines 38–40)
Added `bass_env(prev, bass, attack, release)` to prevent raw bass from causing strobing. Previous frame's smoothed bass is read from `dataTextureC.a` and written back to `dataTextureA.a` for persistence.

**Usage:**
- `map()` glyph formation uses `smoothBass` instead of raw `bass`
- Tip glow intensity modulated by `smoothBass`
- Temporal blend factor uses `smoothBass`
- Chromatic strength uses `smoothBass`

### 3. Temporal Feedback (lines 194–195, 286–287)
- Read previous frame color from `dataTextureC` via `uv01 = fragCoord / res`
- Blend current render with previous: `mix(prev.rgb, col, 0.82 + smoothBass * 0.08)`
- Write current color + envelope to `dataTextureA`

This smooths the ferrofluid motion between frames and makes bass-driven transitions feel liquid rather than jarring.

### 4. Chromatic Aberration (lines 291–293)
Standard generative chromatic chunk applied after temporal blend, before ACES:
```wgsl
let caStr = 0.003 * (1.0 + smoothBass) + depth * 0.001;
col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);
```

### 5. Semantic Alpha (lines 296–297)
Replaced hardcoded `alpha = 0.65 + magneticField * 0.5 + aurIntensity * 0.6` with presence-based semantic alpha:
```wgsl
let presence = clamp(length(col) * 1.2, 0.0, 1.0);
let alpha = clamp(presence * (0.6 + depth * 0.25), 0.2, 0.92);
```
This makes dark background regions more transparent and bright auroral regions more opaque.

### 6. Meaningful Depth (lines 289, 294)
`writeDepthTexture` now stores `t / 20.0` (normalized ray distance) for hit pixels and `1.0` for misses. Previously no depth was written at all.

### 7. Branchless Conversions
- **Tip glow** (line 234): Removed `if(audio > 0.1)` block. Now uses `smoothstep(0.1, 0.15, smoothBass) * smoothBass` as a continuous multiplier.
- **mapAurora** (line 149): Removed `if(dBox > 2.0) { return 0.0; }`. Now computes `inRange = f32(dBox <= 2.0)` and multiplies the result. The extra fbm work outside the box is acceptable for a flagship shader.

### 8. Parameter Semantics (unchanged)
All 4 parameters retain their original clear semantics:
- `zoom_params.x` = Spike Length
- `zoom_params.y` = Aurora Intensity
- `zoom_params.z` = Magnetic Twist
- `zoom_params.w` = Fluid Metallic

## Validation

- **naga 29.0.3**: Pass ✅
- **generate_shader_lists.js**: Pass ✅
- **check_duplicates.js**: Pass ✅ (1126 unique IDs)
- **buildMultipassRegistry.js**: Pass ✅

## Showcase Readiness

| Criterion | Status |
|-----------|--------|
| Strong idle visuals | ✅ Raymarched monolith + aurora always renders |
| Satisfying interaction | ✅ Mouse drag rotates B-field; bass forms glyphs |
| Audio reactivity | ✅ 4 parameters driven by smoothBass/treble |
| Temporal smoothness | ✅ dataTextureC blend |
| No jarring cuts | ✅ bass_env prevents strobing |
| 12s rotation ready | ✅ Self-contained generative scene |
