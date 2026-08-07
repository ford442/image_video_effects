# gen-eldritch-tesseract-hive-mind — VISUALIST upgrade note (Batch 38, tracker #342)

## Weaknesses found
- **Broken uniform truth**: read time from `config.z`, resolution from `config.xy`, mouse from `zoom_config.xy`, click from `zoom_config.z`, and "audio" from `zoom_config.w` — all contradicting the canonical contract (`config=[time, rippleCount, resW, resH]`, `zoom_config=[time, mouseX, mouseY, mouseDown]`). The shader was effectively running on garbage inputs.
- **No audio at all** in contract terms — `audio_intensity` came from a uniform word, never `plasmaBuffer`.
- **`dataTextureA` never written** (mandatory every-frame write missing); no feedback of any kind.
- **Flat 0.0 depth** written to `writeDepthTexture`; **alpha hardcoded 1.0**.
- **Naive gamma (`pow 1/2.2`)** instead of ACES; glow capped LDR, no HDR pipeline.
- **Motion energy low**: single slow 4D rotation plane, static camera, sentinel "swarm" was a static noise threshold — no streaks, no trails, no transients.

## Techniques applied (Visualist domain)
1. ⚡ **FAST MOTION — HDR velocity feedback trails** (`dataTextureC`→`dataTextureA`, `textureLoad` only): decaying HDR history added to the new frame so the 4D spin, swarm streaks and voxel glitches leave light-trails. History clamped to `HDR_CLAMP = 6.0` (Batch 36 lesson); decay `0.84 + p1*0.045` — faster spin = longer streaks.
2. ⚡ **FAST MOTION — velocity-stretched speed streaks**: sentinel swarms rebuilt as anisotropic streaks elongated along their local orbital (tangential) velocity, scrolled at `4 + 4*p1 + 5*bass`. Smooth value noise only (`vnoise3`) — temporally coherent, zero hash-strobe.
3. ⚡ **FAST MOTION — audio transient flash bursts**: rising-edge detect on bass, envelope in `extraBuffer[133..134]` (prev-bass + burst env, single-writer `gid==(0,0)`, `arrayLength` guard, exp decay ×0.90, clamped ≤2.0). Burst flashes vein glow, voxel tearing, swarm brightness and ACES exposure.
4. ⚡ **FAST MOTION — faster dynamics + time-warp easing**: default 4D spin ~2× faster (`0.25 + p1*1.5`), added a **second y-w tumble plane** so the hypercube visibly unfolds through itself, orbiting camera scaled by p1, and `warpT = time + 0.4·sin(0.31·t)` easing for fast-surge/smooth-settle motion.
5. **Linear HDR workflow + ACES** tone map with audio-riding exposure (`1.15 + 0.25·mids + 0.35·burst + 0.1·treble`).
6. **Audio-reactive color temperature**: mids swing the hive between cool-cyan and warm-amber via `tempTint` applied to vein glow, swarms and fog (split-tone: warm highlights, violet shadows preserved).
7. **Real generated depth** (`clamp(d/12)`) written to both `writeDepthTexture` and `dataTextureA.a`; **semantic alpha** from luma + hit mask + swarm energy.

## Slider wiring (all 4 LIVE, byte-exact JSON)
- p1 **Tesseract Rotation Speed** → 4D spin rate (both planes), camera orbit, swarm streak speed, trail decay — the motion-energy master.
- p2 **Swarm Density** → streak threshold (`0.94 − p2*0.055`).
- p3 **Voxel Tearing Intensity** → voxel scale + bass gate (unchanged semantics, now driven by real bass).
- p4 **Iridescence Shift** → thin-film phase (plus slow time drift).

## Contract compliance
- Canonical 13 bindings verbatim; Uniforms struct exactly `config, zoom_config, zoom_params, ripples` with corrected truth comments.
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard; `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- Audio only from `plasmaBuffer[0].xyz`; feedback reads only `textureLoad(dataTextureC)`; extraBuffer state only `[133..134]`, single-writer + `arrayLength` guard.
- Mouse gravity well now uses real `zoom_config.yz` uv + `zoom_config.w` click; stays reactive at speed.
- JSON: additive only (description + truthful features incl. `fast-motion`); `updatedParams` verified unchanged vs `git show HEAD:`.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK, bindgroup compatible, 0 extraBuffer violations) for both shaders.
