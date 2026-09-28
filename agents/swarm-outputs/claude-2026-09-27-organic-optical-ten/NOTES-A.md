# NOTES-A — leviathan-scales, pulsar, jellyfish-swarm, bioreactor-bloom

## gen-abyssal-leviathan-scales
- Kept verbatim: hex-grid map(), conveyor/rowWave timing, scalePalette(), spring cursor (extraBuffer[133..138]), click breach loop, camera fly-through, params.
- A packing: display RGBA, unchanged (already correct pre-upgrade).
- Ideas landed: (1) chromatic dispersion split via per-channel scalePalette phase offset scaled by fresnel — visible in the scale shading block; (2) molt scar — persistent `scarEnergy` decayed from `prev.a` (exact dataTextureC read), gated by the hex-grid `ridge` pattern and a new per-cell hash, added into scale color and folded into final alpha instead of the raw `breach` term; (3) held-flare micro-ridging — `ridgeBoost` in `map()` sharpens keel/facet frequency inside the existing `repel` field scaled by `g_held`.
- Deviation: none. Naga clean.

## gen-bioluminescent-aether-pulsar
- Kept verbatim: core/disk SDF + smin, spring-damper camera orbit, click shockwave loop, cosine palette, exact C feedback, params.
- A packing: display RGBA, unchanged.
- Ideas landed: (1) spin-locked twin jets — `jetAsym` term in the beam-glow accumulation, sign(p.y)-based, scaled by Pulsar Spin Rate; (2) Keplerian shear striping — disk noise sample now warped through a radius x spin-rate azimuthal rotation before the `noise3` call; (3) shockwave-triggered core flare — `pulsarShock` computation moved earlier so the core material branch can add `palette * pulsarShock * 1.6` directly, on top of the pre-existing screen-space shell overlay.
- Header previously had `Upgraded: 2026-08-03` with no `Ideas:` line and a bare `upgraded-rgba` token outside any Features list — replaced with canonical header, Upgraded bumped to 2026-09-27.
- Deviation: none. Naga clean.

## gen-bioluminescent-aether-jellyfish-swarm
- Kept verbatim: mapJellyfish bell/hollow/core/tentacle smin chain, mapScene domain repetition + raw mouse repulsion, volumetric empty-space pass, bioluminescentGlow(), params.
- A packing: display RGBA — floor fix applied: `textureSampleLevel` on `dataTextureC` replaced with exact `textureLoad`.
- Ideas landed: (1) bell-contraction jet propulsion — `swimPhase`/`contraction` now drives the bell radius (was a fixed 0.4 sphere) inside `mapJellyfish`; (2) stinger-tip glow — `mapJellyfish` now also returns tip-proximity distance, threaded through `mapScene` (widened vec2→vec4: dist, matId, tipProximity, repulseMag), re-evaluated once at the hit point in `main()` to light tentacle endpoints with `bioluminescentGlow()`; (3) startle flash — the same re-evaluation exposes `repulseMag`, gated with `smoothstep` to flash the bell on strong repulsion.
- Floor fix: `writeDepthTexture` was hardcoded `vec4(0,0,0,0)` — replaced with real `depthVal` from raymarch `dist`.
- Deviation: `mapJellyfish`'s return type changed from `f32` to `vec2<f32>` and `mapScene`'s from `vec2<f32>` to `vec4<f32>` to carry the two new signals without a second geometry pass; `raymarch()`/`getNormal()` are unaffected since they only read `.x`/`.y`. Naga clean.

## gen-bioreactor-bloom
- Kept verbatim: fbm-warped grid/cell hashing, nucleus/membrane/pulse formulas, nutrientTendril()/pulseBloom() core shapes, poisonCloud mouse falloff, spore sparkle, params, `bass_env` in extraBuffer[0].
- A packing: **fixed** — was writing raw fields (`nucleus, membrane, tendrils, bloomLayers`) into `dataTextureA` while reading `dataTextureC` back as color (`prev.rgb`); now writes the actual post-ACES display color + semantic alpha, matching the C-read.
- Ideas landed: (1) mitosis split event — `dividing`/`center2`/`nucleus2` bud a second nucleus along a hashed division axis (`divisionAxis`) once Mitosis and a phase cycle cross a threshold; (2) toxicity necrosis creep — `necrosis = tendrils * poisonCloud`, blends tendril color toward a necrotic brown and dims it; (3) reactivity-scaled bloom pulse — `pulseBloom()` gained a `sharpness` parameter, and both ring speed and ring thickness now scale with `reactivity` (previously Reactivity never touched the bloom rings at all).
- Other floor fixes: exact `textureLoad` replacing `textureSampleLevel`; real semantic alpha replacing hardcoded `vec4(color, 1.0)`; real relief-based depth replacing hardcoded `vec4(0,0,0,0)`; the "Explicit bypass for regex auditor" indirection (four separate `let zp_x/y/z/w` locals before reassembling `u.zoom_params`) simplified to a direct `clamp(u.zoom_params, ...)` — confirmed this was not a real dead-slider bypass, all four params already drove the effect.
- Deviation: none beyond the above. Naga clean.

All four files: `naga <file>.wgsl` → Validation successful. JSON `features[]` updated additively on all four (added `upgraded-rgba` plus the genuinely-true tags; `params`/`updatedParams` untouched, byte-exact).
