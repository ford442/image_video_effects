# gen-abyssal-quantum-leviathan-skeleton — Algorithmist note (Batch 38, tracker #341)

## Weaknesses found
1. **Fake audio (worst kind):** "Audio Reactivity" slider multiplied `u.config.y` — which per uniform truth is the **ripple count**, not audio. `plasmaBuffer` was never read. The rib "bulge" and marrow "pulse" were driven by click counts and a bare `sin(time)`.
2. **Slow drift motion:** camera orbit `time·0.2`, spine waves `time·0.5/0.3` — the leviathan barely swam.
3. **Contract gaps:** feedback read via `textureSampleLevel(dataTextureC, u_sampler, …)` (contract requires `textureLoad`), flat `0.0` depth, hardcoded alpha `1.0` on both outputs, no tone map, HDR history unclamped, `textureStore(writeDepthTexture, global_id.xy, …)` passed `vec2<u32>` coords.
4. **Mouse gravity well** used `zoom_config.z` directly as y-up mouse (truth: y=0 top-down, needs flip).

## Techniques applied (fast-motion ones marked ⚡)
- ⚡ **Fast undulating spine kinematics:** closed-form traveling wave `phase = k·z − ω·t` with `ω = mix(2.5, 9.0, turb)·(1+0.4·kick·audioReact)`; **whip amplitude grows toward the tail** (`1.4 + 0.9·smoothstep(0,12,|z|)`) plus an incommensurate second harmonic (`2.17×`) — smooth at any speed, analytic in time, no strobing.
- ⚡ **Ballistic lunge dynamics:** periodic dart-forward surge `lungeEnv = exp(-3.5·fract(0.45·animTime))` shifting the whole skeleton along its spine axis, with camera follow-through drag; a **racing shock-pulse** travels head→tail each cycle, flaring rib thickness and lighting the bones as it passes (bounded exp envelopes).
- ⚡ **Bass-transient kick bursts:** rising-edge detect on `plasmaBuffer[0].x`, dt-integrated exp decay (persisted prev-time ⇒ fps-independent), state only in `extraBuffer[133..135]`, single-writer + arrayLength guard, clamped ≤ 2.0; scaled by the Audio Reactivity slider. Kick boosts lunges, wave speed, and flow speed.
- ⚡ **High-speed aether-current advection (speed streaks):** background volumetric noise field streamed at `mix(2,10,turb)+3·kick·audioReact` and **anisotropically stretched along the flow axis** (`z·0.35` vs `xy·2.0`) so eddies elongate into speed lines; two-octave detail.
- ⚡ **Velocity-advected motion-blur trails:** history fetched via `textureLoad` offset along the analytic camera tangential velocity (clamped ±4 px), decay 0.85, **HDR clamp ≤ 6.0**.
- Kept the soul: same spine+ribs SDF composition (`smin` blend), same bone/rim/marrow shading language, same fog, same gradient-noise currents — upgraded, not rewritten. Added ACES, semantic alpha (0.92 hit / luma-scaled background), real depth (`1 − t/MAX_D`).

## Slider wiring (all LIVE, names/defaults byte-exact)
- **Bone Density (p1)** → spine radius + rib spacing/thickness (kept, clamped `mix(0.25,1.0)`).
- **Marrow Glow (p2)** → marrow intensity `mix(0.1, 1.6)`, now pulsed by real mids + FFT bins 1–4.
- **Current Turbulence (p3)** → the SPEED governor: global rate, spine wave speed, camera orbit rate, current flow speed + noise frequency.
- **Audio Reactivity (p4)** → `mix(0, 2.0)` gain on all real-audio terms: rib bulge (bass), marrow pulse (mids/FFT), kick coupling, current shimmer (treble).

## Contract compliance
Canonical 13-binding header verbatim; Uniforms struct exactly `config, zoom_config, zoom_params, ripples`; `@compute @workgroup_size(16, 16, 1)` + `u.config.zw` bounds guard; writes `writeTexture`/`writeDepthTexture`/`dataTextureA` every frame; `textureLoad`-only feedback; `plasmaBuffer[0].xyz` + guarded FFT bins 1–4; extraBuffer only [133..135] single-writer; no `textureSample`/`dpdx`/reserved words.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files …` → **2/2 PASS** (naga OK, bindgroup compatible, extraBuffer violations: 0).
`updatedParams` diff vs `git show HEAD:…json` → **IDENTICAL**. JSON edits additive only (description + truthful `features`).
