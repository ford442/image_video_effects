# gen-mycelium-network — Optimizer note (Batch 38, tracker #347)

## Weaknesses found (performance / elegance / motion)

1. **Unculled O(roots × branches) SDF traversal** — up to 3 × 70 segment
   distance evaluations per pixel (plus side branches), each with `distToSegment`,
   evaluated for every pixel regardless of proximity.
2. **Missing contract items** — no resolution bounds guard; alpha hardcoded
   `1.0` everywhere; depth was a flat `age * 0.5`.
3. **Not audio reactive at all** despite "audio/music/reactive" tags; mouse
   completely unused.
4. **Unbounded feedback saturation** — `col = max(col, prev * 0.98)` ratcheted
   forever toward full white; the old colony never cleared when `seed` jumped
   at each growth-cycle wrap (visible pop + permanent accumulation).
5. **Glacial motion** — growth phase advanced at `t * 0.05 * growthRate`
   (~20 s/cycle at default); no fast element anywhere in the shader.
6. Minor elegance: local variable named `length` (shadows the builtin).

## Techniques applied (⚡ fast-motion ones called out)

- **⚡ Traveling signal pulses along the hyphae** — closed-form traveling wave
  `fract(age·1.5 − t·pulseSpeed·0.12)` evaluated from data the traversal already
  returns — **zero extra traversal cost**. Pulse speed = `2 + growthRate·4 +
  bass·2 + kick·3`: fast signal propagation racing root→tip, surging on audio.
- **⚡ Time-warp eased growth front** — growth phase now uses fast-in/smooth-out
  easing `1 − (1−phase)³` driving a visible expanding front (`frontR`); branches
  ahead of the front are ghosted, so the colony visibly *grows fast* each cycle;
  cycle rate boosted ~3× and kicked by bass.
- **⚡ Bass-transient spore-burst shockwave** — rising-edge detector with
  **frame-rate-independent decay** (`exp(−dt·5)`, dt from persistent prev-time)
  in `extraBuffer[133..135]` (single-writer `gid==(0,0)` + `arrayLength` guard).
  The kick launches an expanding ring shockwave from the mouse (while pressed)
  or colony center, and accelerates pulses/growth.
- **Coarse cull before expensive evaluation** — every segment SDF (and the
  side-branch block) is gated behind a cheap AABB test (`CULL_MARGIN = 0.12`
  covers thickness + glow reach). The sequential walk (noise/direction) must
  always run, but ~80–95% of distance evaluations are pruned for pixels far
  from the colony. Iteration count explicitly bounded (`min(…, 70)`).
- **Bounded feedback, no saturation** — history hard-clamped ≤ `HDR_CAP = 4.0`;
  decay `mix(0.90, 0.965, clearFade)` where `clearFade` wipes the colony quickly
  near cycle wrap, so old growth clears for the new seed instead of popping or
  accumulating forever.
- **HDR-ready output** — HDR state to `dataTextureA`; ACES tone map for
  presentation; semantic alpha = bioluminescent mass (hyphae + tips + pulses +
  burst), floored at 0.06; real generated depth (hypha relief + age + pulse
  elevation).
- **Interactivity at speed** — mouse is a nutrient attractor (mids-modulated
  glow) and the burst origin while pressed; audio from `plasmaBuffer[0].xyz` +
  guarded FFT bins 1–8 (bass bins drive kick context, mid bins shimmer the
  nutrient field).
- Elegance: `length` local renamed `segLen`; named constants; `MycelData`
  struct replaces the overloaded vec4 (adds `branchR` for the growth front).

## Slider wiring (all 4 LIVE, byte-exact JSON)

- p1 **Growth Rate** → segment length + cycle speed + pulse speed (SPEED governor).
- p2 **Branching Factor** → branch count (20–70) + branch probability.
- p3 **Nutrient Density** → nutrient field + mouse-attractor glow strength.
- p4 **Bioluminescence** → tip glow + traveling-pulse intensity.

## Contract compliance

Canonical 13 bindings verbatim; Uniforms struct exact; 16×16×1; bounds guard
added; `writeTexture`/`writeDepthTexture`/`dataTextureA` written every frame;
`textureLoad`-only feedback; audio only from `plasmaBuffer[0].xyz` + guarded
FFT bins 1–8; persistent state only in `extraBuffer[133..135]`, single-writer +
`arrayLength` guarded; semantic alpha; real generated depth; smooth value noise
only (no hash strobing); no ripples used. Soul preserved: same 3-root
diffusion-limited branching walk, earthy palette, bioluminescent tips.

## Gate result

`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK,
bindgroup compatible, no extraBuffer violations). `updatedParams` diff vs
`git show HEAD:…` → IDENTICAL. JSON edits additive only (features + description).
