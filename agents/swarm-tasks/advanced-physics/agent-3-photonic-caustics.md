# Agent 3: Photonic Caustics Accumulator

**Priority:** #3 (perf-sensitive)  
**Tier:** B multipass / Tier C for megapixel photon budgets  
**Base prototype:** `public/shaders/photonic-caustics.wgsl` (32 photons/pixel, single-pass)

---

## Mission

Turn the existing caustics shader into a **temporal accumulator** that feels like sunlight through a swaying pool — chromatic dispersion, Fresnel glints, iridescent micro-ripple normals. Mouse is a movable point light; audio treble shimmers the surface.

---

## Current state

`photonic-caustics.wgsl` already has:

- Schlick Fresnel, Snell refraction, chromatic IOR split
- Height from depth + FBM normal map
- 32 photon traces per pixel per frame
- `dataTextureA` accumulation with `dataTextureC` feedback

**Gaps vs plan:** no multipass separation, low photon count, no audio, params lack `mapping` in JSON.

---

## Target multipass (Tier B)

```
Pass 1: caustic-emitter.wgsl   — seed photon dirs from mouse light + surface normal
Pass 2: photon-trace.wgsl      — 64–128 traces, RGB split IOR, write dataTextureB scratch
Pass 3: caustic-accumulate.wgsl — blend into dataTextureA (temporal EMA), render writeTexture
```

**Packing:**

```
dataTextureA: .rgb = accumulated radiance (HDR), .a = blend weight / frame count
dataTextureB: per-pass photon energy stamp (pass 2 only)
dataTextureC: previous accumulation (read)
```

Temporal blend: `acc = mix(prev, new, 1.0 - zoom_params.y)` where y = persistence.

---

## Parameters

| Channel | UI name | Maps from legacy |
|---------|---------|------------------|
| x | Index of Refraction | `ior` |
| y | Persistence | new — temporal accumulation |
| z | Dispersion | `dispersion` |
| w | Intensity | `intensity` |

Mouse: `u.zoom_config.yz` = light position, `.w` = light height / focus.

Audio: treble (`plasmaBuffer[0].z`) perturbs normal map phase; bass boosts intensity.

---

## Performance guardrails

- **Tier B:** ≤128 photon traces × 4 bounces per pixel per frame across passes
- **Tier C:** 500k–2M traces via multi-frame accumulation + graph-runner batching — **blocked**
- Early exit when photon weight < 1e-4
- Half-res trace + full-res upsample acceptable (document in header)

---

## Deliverables

| File | Notes |
|------|-------|
| `caustic-accumulator-pass{1,2,3}.wgsl` | or upgrade `photonic-caustics` in place |
| `shader_definitions/simulation/caustic-accumulator.json` | multipass metadata |
| Thumbnail | bright caustic pool on dark image |

---

## Acceptance

- [ ] Multipass chain registered
- [ ] 4 zoom_params + mappings
- [ ] Mouse light + audio treble intentional
- [ ] Temporal accumulation visible over 2–3 seconds
- [ ] Thumbnail + blurb

---

## Required reading

1. `agents/WGSL_BUILTINS_GENERATIVE.md`
2. `swarm-tasks/advanced-physics/MULTIPASS_SIM_CONTRACT.md`
3. `public/shaders/photonic-caustics.wgsl` — port chunks
4. `public/shaders/photonic-caustics-iridescence.wgsl` — iridescence overlay ideas
