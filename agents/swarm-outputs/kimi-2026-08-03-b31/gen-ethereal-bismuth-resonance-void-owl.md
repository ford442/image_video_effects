# Changelog — gen-ethereal-bismuth-resonance-void-owl (visualist, b31)

## Critical bug fix
- **Replaced non-canonical extended Uniforms struct** (`resolution/time/frame/view_matrix/proj_matrix/camera_pos`) with the canonical `config, zoom_config, zoom_params, ripples` struct. This was misaligning against the engine's 848-byte uniform buffer — every field after `frame` read garbage at runtime.
- Remapped: `u.time` → `u.config.x`, `u.resolution` → `u.config.zw`, `frame` unused (derived when needed), camera matrices/camera_pos deleted (camera was already built in-code).
- Added the missing **resolution bounds guard** on `global_invocation_id` (shader previously had none).
- Now writes `writeTexture`, `writeDepthTexture` AND `dataTextureA` every frame (previously only `writeTexture`).

## Visual upgrades (role mandate)
- **Thin-film iridescence** (`thinFilm()`): physically-flavored interference palette on the bismuth shell; film thickness varies per facet, hue offset driven by the Iridescence Shift slider.
- **Per-facet color variation**: quantized hit-position + normal hash gives each crystal cell its own film thickness, specular intensity and debris tint.
- **3-point lighting rig**: warm key (with 8-step **soft shadow**), cool fill and golden back scatter, both modulated by 3-tap **ambient occlusion**. Plus Blinn-Phong specular glints on the stair facets and a Fresnel rim fed by mids.
- **New geometry**: stepped pyramidal **ear tufts** (hollow bismuth frames, mirrored) so the silhouette reads as an owl.
- **2D geometric patterning**: recursive square-fold **hopper-crystal inlay** shimmering in the void fog, colored by the same thin-film palette; dims behind a surface hit.
- **Click ripples**: guarded (`min(u32(u.config.y), 50u)`) expanding iridescent shockwave rings.
- **ACES filmic tonemap** replaces Reinhard; semantic alpha from luma + hit presence (no hardcoded 1.0); real near-is-one depth (`1.0 - t/MAX_DIST`, miss = 0).
- Audio: bass drives core pulse/heart size, mids drive rim, treble + FFT bins (extraBuffer[5..132], read-only, arrayLength-guarded) drive inlay shimmer and facet sparkle.
- All 4 sliders live and meaningful (complexity→fold iterations, reactivity→audio gain everywhere, shift→thin-film hue, debris→density/spacing).

## Perf estimate
- Raymarch: 100 steps/px × SDF (≤6 fold iterations + tuft loop 3 + debris + heart).
- On hit: normal (6 SDF taps) + soft shadow (8) + AO (3) ≈ 17 extra SDF evals.
- Fog: 4 noise taps; inlay: 4 folds; ripples ≤ 50 (cheap, guarded).
- Roughly comparable to the original +~25%; still light for 16×16 compute at 1080p.

## Rating prediction
- Was: broken uniforms (garbage params), flat lighting, no depth. Now: cohesive bismuth-material story with strong 3D presence and 2D ornament. Predict **4.0–4.5 / 5**.

## Gate
- `wgsl_precommit_gate.py` ✅ naga OK, bindgroup compatible. 397 lines (+82 vs 315).
