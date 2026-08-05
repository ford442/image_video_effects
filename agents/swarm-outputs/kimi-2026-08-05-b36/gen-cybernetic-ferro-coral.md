# gen-cybernetic-ferro-coral — Batch 36 upgrade (Algorithmist)

**Lines:** 199 → 285 (+86, within +50–90 budget)
**Gate:** `wgsl_precommit_gate.py` ✅ (naga OK, bindgroup compatible, 0 workgroup errors, 0 extraBuffer violations)

## What changed

### New algorithms (3 advanced, fused with the raymarched ferro-coral soul)
1. **Domain-warped FBM spikes** (`fbm3` + `warpedFbm`): the old single-octave value-noise spike field is replaced by a 3-octave FBM whose domain is warped by a time-drifting 3D noise vector. Spikes now branch like real ferrofluid fingers instead of uniform blobs. Warp drifts slowly with time → temporal-coherent motion.
2. **Ridged micro-detail** (`ridged3`): squared ridged noise (`1-|2n-1|`)² at 14× frequency carves sharp creases into the coral skin — the micro scale of the new macro+micro structure. Gated behind a cheap early-out (`if (d < 0.45)`) so far-field march steps never pay for it.
3. **Gray-Scott / Turing banding hint** (`turingBand`): two decorrelated 2-octave FBM fields act as activator/inhibitor; `exp(-(a-b)²·90)` isolates the narrow stripes where they balance — reaction-diffusion-style banding carved into the shell, amplitude driven by treble.

### Contract compliance repairs
- **Added resolution bounds guard** (was missing entirely).
- **dataTextureA now written EVERY frame** (was never written — hard violation). It carries the tonemapped, feedback-smoothed color as display history; the existing `textureLoad(dataTextureC)` feedback read now resolves to this shader's own previous frame (host copies A→C) → true temporal coherence instead of undefined history.
- **Semantic alpha fix:** old alpha was `proximity · glow · sourceDepth` — for a generative shader with no media, source depth can be 0/flat, zeroing alpha. New alpha = `hit(proximity) · (0.3 + glow) · mix(1, depth, 0.25)`, with an explicit ray-hit term (`1 - smoothstep(15,20,t)`); depth is now a bounded modulator, never a kill switch.
- **Guarded FFT bins 1–8** (indices 6..13, `arrayLength` guard, clamped 0–2) → `fftEnv` shimmer envelope driving the iridescent palette phase. No hash-based fake spectrum.
- **Click ripples:** bounded loop `min(u32(max(u.config.y,0)),50u)`, Gaussian screen-space falloff × `exp(-age·1.8)` decay, capped at 1.5 → `spikeBoost` multiplier on spike amplitude and core emission. Finite, spatially local.

### Slider wiring (all 4 live, index order preserved via `u.zoom_params.xyzw`)
- p1 Density → cell repetition size (unchanged, still the core density constant)
- p2 Spike Intensity → macro warped-FBM spike amplitude + ridged micro-crease depth
- p3 Core Glow → core emission + march-loop glow accumulation
- p4 Iridescence → fresnel palette factor (now also phase-shifted by mids + FFT env)

### JSON
Additive only: `description` extended with upgrade sentence, `features` populated (13 truthful entries). `updatedParams` verified byte-exact vs HEAD (sorted-key diff identical).

## Perf estimate
map() went from 1 noise eval to ~6 (warp 3 + FBM 3) per march step, plus gated +5 near-surface (ridged 1 + Turing 4). With 100 steps × 3 chromatic rays ≈ 3–3.5× the original per-pixel cost. Early-outs: `d < 0.45` gate on micro/Turing detail, existing `t > 20` and `d < 0.01` breaks unchanged. Estimated ~25–40 fps at 1080p on a mid-range discrete GPU; the march loop is the sole hotspot (normal calc re-evaluates map 6× only on hits).

## Deviations
- None contractual. Note: `normalize(op - mousePos + 0.0001)` guards the zero-vector case at exact mouse position (previously UB when `op == mousePos`).
