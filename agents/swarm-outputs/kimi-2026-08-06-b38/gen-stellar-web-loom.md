# gen-stellar-web-loom — VISUALIST upgrade note (Batch 38, tracker #343)

## Weaknesses found
- **Broken mouse mapping**: treated `zoom_config.yz` as pixel coords (`/dims.x`); canonical truth is 0–1 canvas uv — the singularity pull was anchored off-screen.
- **Fake audio**: `g_audio = config.y * 0.1` — `config.y` is rippleCount, not audio; `plasmaBuffer` bass was read but the "audio" warp driver was noise.
- **Copied source depth**: `writeDepthTexture` was a passthrough of `readDepthTexture` (explicitly forbidden) — no generated depth.
- **`dataTextureA` never written**; no feedback/trails.
- **Reinhard + gamma** (`col/(col+1)`, `pow 0.4545`) instead of ACES; weak HDR headroom for a plasma shader.
- **Motion energy low**: camera drifted forward at fixed 0.5/s; starfield static; no speed lines, no transients.

## Techniques applied (Visualist domain)
1. ⚡ **FAST MOTION — warp-flight camera**: forward speed `1.2 + 1.6*p2` — the **Weave Speed** slider now also drives flight velocity, so the whole loom rushes past the camera (closed-form trajectory, fps-independent by construction).
2. ⚡ **FAST MOTION — radial speed-line streaks**: `atan2`-space streak field stretched along the flight (radial) direction, rushing inward at `2.5 + 3.5*p2`; smooth `noise3` only — temporally coherent at any speed, no strobing.
3. ⚡ **FAST MOTION — HDR velocity feedback trails** (`dataTextureC`→`dataTextureA`, `textureLoad` only): the warp flight smears glowing threads into light-trails; history clamped to `HDR_CLAMP = 6.0`; decay `0.82 + 0.04*p2` — faster weave = longer streaks.
4. ⚡ **FAST MOTION — audio transient flash bursts**: rising-edge on bass, envelope in `extraBuffer[133..134]` (single-writer `gid==(0,0)`, `arrayLength` guard, ×0.90 exp decay, ≤2.0). Burst boosts node/thread plasma accumulation, streak brightness and ACES exposure. Weave turbulence gets time-warp easing (`+0.35·sin(0.43·t)`).
5. **Linear HDR workflow + ACES** replacing Reinhard; exposure `1.05 + 0.06·p3 + 0.2·mids + 0.4·burst`.
6. **Audio-reactive color temperature**: mids swing thread/node plasma and streaks cool-blue → warm-amber (`tempTint`); treble brightens star twinkle; stars now twinkle via smooth sinusoids (no hash-jitter).
7. **Real generated depth**: `clamp(t/maxT)` from the raymarch travel distance (no more copied source depth); semantic alpha preserved via `pow(luma·1.8, p4)`.

## Slider wiring (all 4 LIVE, byte-exact JSON)
- p1 **Thread Density** → lattice domain spacing (unchanged semantics).
- p2 **Weave Speed** → weave turbulence rate + **warp-flight speed** + streak scroll speed + trail decay — the motion-energy master.
- p3 **Plasma Glow** → volumetric thread/node accumulation gain + ACES exposure.
- p4 **Thread Opacity Exponent** → semantic alpha curve (unchanged semantics).

## Contract compliance
- Canonical 13 bindings verbatim; Uniforms struct exactly `config, zoom_config, zoom_params, ripples` with corrected truth comments.
- `@compute @workgroup_size(16, 16, 1)` + bounds guard; `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- Audio only from `plasmaBuffer[0].xyz`; feedback reads only `textureLoad(dataTextureC)`; extraBuffer state only `[133..134]`, single-writer + `arrayLength` guard.
- Mouse singularity now uses real `zoom_config.yz` uv (corrected mapping); `zoom_config.w` click deepens the pull — reactive at speed.
- JSON: additive only (description + truthful features incl. `fast-motion`, `warp-flight`); `updatedParams` verified unchanged vs `git show HEAD:`.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK, bindgroup compatible, 0 extraBuffer violations) for both shaders.
