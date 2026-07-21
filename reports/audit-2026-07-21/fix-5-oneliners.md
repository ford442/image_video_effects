# Fix Agent 5 — Audit Lane C/D Logic Fixes (2026-07-21)

Gate: `python3 scripts/wgsl_precommit_gate.py --files <12 files>` → **exit 0** (12/12 pass, naga OK, bindgroup compatible).

Struct layout verified in every touched shader: `Uniforms { config, zoom_config, zoom_params, ripples }` — matches the diagnosis (zoom_config.x=time, .yz=mouse, .w=mouseDown; zoom_params = 4 user sliders). No mismatches found.

## 1. public/shaders/kaleidoscope.wgsl — time-as-audio accumulation

```diff
-  let audio = u.zoom_config.x;
   let audioBass = plasmaBuffer[0].x;
   let audioTreble = plasmaBuffer[0].z;
-  let audioReact = 1.0 + audio * 0.3 + audioBass * 0.2;
+  let audioReact = 1.0 + audioTreble * 0.3 + audioBass * 0.2;
...
-  let edgeGlow = (1.0 - edgeFade) * 1.5 + segmentEdge * 0.25 * audio;
+  let edgeGlow = (1.0 - edgeFade) * 1.5 + segmentEdge * 0.25 * audioTreble;
```
`u.zoom_config.x` is time, so `audioReact` grew ~0.3/s forever. Replaced with the legitimate audio path (`plasmaBuffer[0].z` = treble), preserving the audio-reactive identity. Gate: ✅ (initial run failed on the leftover `audio` ref at edgeGlow; fixed, re-gated ✅).

## 2. public/shaders/quantum-foam.wgsl — zoom_config consumed as sliders

```diff
-    let rotationSpeed = u.zoom_config.x * 2.0;
-    let depthParallax = u.zoom_config.y * 0.2;
-    let emissionThreshold = u.zoom_config.z * 0.5 + 0.3;
-    let chromaticSpread = u.zoom_config.w * 2.0 + 0.5;
+    let rotationSpeed = 0.5;
+    let depthParallax = 0.1;
+    let emissionThreshold = 0.55;
+    let chromaticSpread = 0.5;
```
All 4 real sliders (`u.zoom_params`) were already consumed by foamScale/flowSpeed/diffusionRate/octaveCount, so the mis-bound values were replaced with sane constants (rotationSpeed 0.5 ends the 2t² accelerating strobe: angle is now `time*0.5 + pattern*3.0`). 8x8 workgroup untouched. Gate: ✅.

## 3. public/shaders/tornado-vortex.wgsl — premultiplied rgb into alpha-ignoring blit

```diff
-  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color * a, a));
+  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, a));
```
Blit (`src/renderer/ShaderTemplates.ts` fs) returns `vec4f(rgb, 1.0)` — alpha ignored, so `color * a` went near-black outside the funnel (bloom-weight a ≈ 0 for most pixels). rgb no longer premultiplied; alpha kept in the channel for dataTextureA consumers. Gate: ✅.

## 4. public/shaders/anaglyph-3d.wgsl — pow(negative, gamma) NaN

```diff
-    c = pow(c, gamma);
+    c = pow(max(c, vec3<f32>(0.0)), gamma);
```
Lift can push dark channels negative before the gamma pow → NaN. Guarded with max(..., 0). Gate: ✅.

## 5. public/shaders/sand-dunes.wgsl — blackbody NaN domains

```diff
-    r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0);
-    g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0);
+    r = clamp(329.698727446 * pow(max(t - 60.0, 0.001), -0.1332047592) / 255.0, 0.0, 1.0);
+    g = clamp(288.1221695283 * pow(max(t - 60.0, 0.001), -0.0755148492) / 255.0, 0.0, 1.0);
...
-    g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0);
-    b = select(clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0), 0.0, t <= 19.0);
+    g = clamp((99.4708025861 * log(max(t, 0.001)) - 161.1195681661) / 255.0, 0.0, 1.0);
+    b = select(clamp((138.5177312231 * log(max(t - 10.0, 0.001)) - 305.0447927307) / 255.0, 0.0, 1.0), 0.0, t <= 19.0);
```
House-style epsilon guards (`log(max(x, 0.001))`, cf. gravity-well/neon-echo). Gate: ✅.

## 6. Guided-filter family — `/ count` div-by-zero (7 files found; Lane C estimated ~8)

Each file had 4 mean divisions; `/ count;` → `/ max(count, 1.0);` (28 lines total):

- blueprint-reveal-guided.wgsl (L105-108): sumGuide/sumInput/sumGuideInput/sumGuide2 — ✅
- chromatic-focus-guided.wgsl (L125-128): same 4 — ✅
- conv-guided-filter-depth.wgsl (L108-111): same 4 — ✅
- conv-guided-video-filter.wgsl (L93-96): sumG/sumP/sumGP/sumG2 — ✅
- digital-reveal-guided.wgsl (L98-101): same 4 — ✅
- dimension-slicer-guided.wgsl (L125-128): same 4 — ✅
- ink-dispersion-guided.wgsl (L109-112): same 4 — ✅

Repo-wide grep for `meanGuide|meanG2|meanGP|sumGuideInput` confirms exactly these 7 files share the pattern — no 8th guided-filter file exists. Other `/ count` hits (datamosh, dla-crystals, gen-*, lava-lamp-blobs, etc.) use unrelated loop-count semantics and were left alone.
