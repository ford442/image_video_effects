# Ripple Blocks v2.0 — 4-Agent Swarm Analysis & Design

## Phase 1: Analysis (All Agents, 10 min)

### Algorithmist Assessment
**Current weaknesses:**
1. Primitive sine wave ripple with single frequency — no harmonic complexity
2. Rigid rectangular grid — no organic variation or cell shape diversity
3. Static falloff — could use multi-octave interference patterns
4. No noise functions at all

**Selected upgrades:**
- Domain-warped FBM for organic grid distortion
- Cymatics interference: 3-phase wave superposition (golden-ratio detuned)
- Per-cell hash for deterministic variation

### Visualist Assessment
**Current weaknesses:**
1. No HDR — values clamped to LDR, no overbright highlights
2. Flat shading — single scalar `wave * 0.1` added uniformly
3. No tone mapping — raw RGB output
4. Binary color (sampled vs black) — no gradient or atmospheric depth

**Selected upgrades:**
- ACES tone mapping on HDR accumulation
- Fresnel rim glow on cell edges
- Temperature-based color shifting (warm/cool based on audio mids)
- Treble sparkle particles

### Interactivist Assessment
**Current weaknesses:**
1. Mouse only used as distance scalar — no velocity, no click response
2. Audio only modulates amplitude — no multi-band frequency response
3. No ripple click handling (ripples array unused)
4. No depth integration — flat 2D effect
5. No temporal feedback

**Selected upgrades:**
- Ripples array for click shockwave spawn
- Bass → global env pulse, mids → frequency + temperature, treble → sparkle
- Depth-based parallax distortion
- dataTextureC temporal trail accumulation

### Optimizer Assessment
**Current weaknesses:**
1. Magic numbers everywhere (0.8, 5.0, 0.001)
2. Two texture samples of readTexture (one for color, one could be cached)
3. Per-cell `select` branch could be restructured
4. No early exit for background
5. Workgroup size 16x16 — acceptable for this workload

**Selected upgrades:**
- Named parameter extraction at top of main
- Single cached inputColor sample
- Early exit for out-of-bounds pixels (already present, verify)
- Vectorized `inBounds` check

---

## Phase 2: Design (20 min)

### Core Simulation Kernel (Algorithmist)
```
uv → domainWarp(uv * gridScale, time) → cellId, cellCenter
mouseDist + rippleShockwaves → interference(sin(f1), sin(f1*φ), fbm_noise)
scale = 1.0 - interference * falloff * env
```

### Color & Lighting (Visualist)
```
rim = exp(-edgeDist * gridScale * 10.0) * glowIntensity * env
temp = mix(warm, cool, mids)
col += rim * cyan + temp * abs(interference) + spark(treble)
aces(col * 1.2)
```

### Input Mapping (Interactivist)
```
bass   → env = 1.0 + bass * 2.0  (global scale pulse)
mids   → freq += mids * 30.0    (wave density)
       → tempColor(mids)        (thermal shift)
treble → sparkle threshold       (additive glints)
mouse  → mouseDist falloff       (spatial attenuation)
click  → ripples[] shockwaves    (transient events)
depth  → parallax offset         (3D separation)
       → alpha *= (1.0 - depth*0.3)
```

### Performance Budget (Optimizer)
```
Texture samples: 3 (readTexture input, readTexture cell, readDepthTexture)
Noise octaves: 4 (fbm) + 2 (domain warp q/r) = ~6 evaluations
Workgroup: 16x16 (256 threads, optimal occupancy)
Target: 60fps @ 1080p on GTX 1060 equivalent
```

---

## Phase 3: Implementation Plan

1. Algorithmist writes `hash2`, `vnoise`, `fbm`, `domainWarp`
2. Visualist writes `aces`, `tempColor`, rim/temp/spark logic
3. Interactivist writes ripple loop, audio extraction, depth parallax, feedback
4. Optimizer assembles main(), caches samples, structures early exits

---

## Phase 4: Polish Targets

- [ ] A/B: Compare v1 vs v2 side-by-side
- [ ] Verify temporal trails don't cause ghosting artifacts
- [ ] Check that domain warp doesn't break cell bounds math
- [ ] Ensure alpha composites cleanly in slot 1/2/3 chain

---

## Predicted Rating

**Before:** 2.8★ (simple grid distortion)
**After:** 4.6★ (organic cymatics field with HDR metal lighting)

**Confidence:** High — the upgrades address every major weakness while keeping the original "ripple blocks" soul.
