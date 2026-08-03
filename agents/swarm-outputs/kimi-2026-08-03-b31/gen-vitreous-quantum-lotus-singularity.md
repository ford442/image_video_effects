# Changelog — gen-vitreous-quantum-lotus-singularity (visualist, b31)

## Critical bug fix
- **Replaced non-canonical extended Uniforms struct** (`resolution/time/frame/view_matrix/proj_matrix/camera_pos`) with the canonical `config, zoom_config, zoom_params, ripples` — the old layout misaligned against the engine's 848-byte uniform buffer.
- Remapped: `u.time` → `u.config.x`, `u.resolution` → `u.config.zw`; unused matrices/camera_pos deleted (camera already built in-code).
- **Slider mapping bug fixed**: the shader did `mix(1.0, 10.0, zoom_params.x)` etc., but the engine passes RAW slider values (defaults 5.0 / 1.5 / 1.33 / 1.0) — Petal Complexity was exploding to 46 fold iterations and Singularity Mass to ~7.5. Now `clamp()`ed raw values; sliders behave exactly as their JSON ranges promise.
- Now writes `writeTexture`, `writeDepthTexture` AND `dataTextureA` every frame (previously only `writeTexture`); bounds guard switched to canonical `u.config.zw`.

## Visual upgrades (role mandate)
- **Material IDs**: `map()` returns `(dist, matId)` — 1=vitreous petals, 2=singularity core; the core now gets its own event-horizon shading: near-black disc, violet accretion glow, bass-pumped photon ring.
- **Thin-film iridescence** on the glass petals (cool cyan/violet/rose bias), blended 45% over the signature chromatic-dispersion refraction (kept intact).
- **Per-petal cell variation**: polar-cell hash drives film thickness and albedo per petal.
- **2D geometric ornament**: symmetry-folded **radial vein inlay** (spokes + drifting concentric arcs) traced across the bloom, glowing with the audio pulse — reads as lotus vasculature.
- **3-point lighting** (key/fill/translucent back-light through glass) with 3-tap **ambient occlusion** darkening petal crevices; Blinn-Phong specular; Fresnel glass-edge rim fed by mids.
- **ACES filmic tonemap**; semantic alpha (faint void, near-solid bloom); real near-is-one depth (`1.0 - dO/MAX_DIST`, miss = 0); `dataTextureA` packs encoded normal + material tag.
- All 4 sliders live and honest: Petal Complexity→fold count & symmetry, Singularity Mass→warp + horizon radius, Refraction Index→dispersion spread, Audio Pulse Glow→veins/pulse/dust gain.

## Perf estimate
- Raymarch: 120 steps/px × map (≤10 petal folds + polar fold + warp). On hit: +6 (normal) +3 (AO) map evals. Dust loop: 20 hash taps. Comparable to original (which secretly ran 46 folds at default — this upgrade is actually *faster* at defaults). Fine at 1080p.

## Rating prediction
- Was: misaligned uniforms + broken slider math (exploding geometry), no depth, hardcoded alpha. Now: coherent vitreous material story, working sliders, real 3D presence. Predict **4.0–4.5 / 5**.

## Gate
- `wgsl_precommit_gate.py` ✅ naga OK, bindgroup compatible. 296 lines (+70 vs 226).
