# Fix Agent 1 — Naga Validation Fixes (2026-07-21)

Gate: `python3 scripts/wgsl_precommit_gate.py --files <all 4>` → **4/4 PASS, exit 0** (naga OK, bindgroup compatible).

## 1. public/shaders/gen-ethereal-cyber-plasma-void-dragon.wgsl — ✅ PASS

Primary error (L114): second `fn map(...)` declared inside the body of an incomplete
first `fn map` stub (L96–112). The stub only declared locals, had no `return`, and
duplicated the name `map` — so simply inserting `}` would still fail (redefinition +
missing return). Minimal fix: removed the dead stub (L95–112), keeping the real 5-arg
`map`. This unmasked two latent errors, also fixed minimally:

```diff
-// Main SDF evaluation
-fn map(p: vec3<f32>, time: f32, audio: f32) -> vec4<f32> {
-    // Parameters
-    let plasmaIntensity = u.config.z; // param 0: 1.5 default
-    ... (incomplete stub body, 17 lines) ...
-    var glow = 0.0;
-
 // Environment mapping
 fn map(p: vec3<f32>, time: f32, audio: f32, mouseTarget: vec3<f32>, params: vec4<f32>) -> vec2<f32> {
```

Latent error A (L138): `sdCapsule` used but never defined. Added the standard IQ
capsule SDF helper next to `smin`:

```diff
+fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
+    let pa = p - a;
+    let ba = b - a;
+    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
+    return length(pa - ba * h) - r;
+}
```

Latent error B (L251): `main` declared `var final_col` but accumulated into undefined
`col` throughout, storing `final_col` (always black). Renamed the declaration and the
final store to `col` (2 edits vs ~8 the other way):

```diff
-    var final_col = vec3<f32>(0.0);
+    var col = vec3<f32>(0.0);
...
-    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_col, 1.0));
+    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
```

## 2. public/shaders/gen-radiant-cyber-plasma-astro-griffin.wgsl — ✅ PASS

L59 local `length` shadowed the `length()` builtin used at L63. Renamed local to
`spanLen` and updated its single use:

```diff
-    let length = 0.5 + span * 0.5;
+    let spanLen = 0.5 + span * 0.5;
...
-    let d = abs(q) - vec3<f32>(width, 0.02, length);
+    let d = abs(q) - vec3<f32>(width, 0.02, spanLen);
```

## 3. public/shaders/gen-sentient-cyber-chrono-void-serpent.wgsl — ✅ PASS

L147 mixed signed/unsigned compare (`i32 >= u32`). Cast the `u32` side, matching the
surrounding style (`f32(dimensions.x)` at L151):

```diff
-    if (tex_coords.x >= dimensions.x || tex_coords.y >= dimensions.y) {
+    if (tex_coords.x >= i32(dimensions.x) || tex_coords.y >= i32(dimensions.y)) {
```

## 4. public/shaders/gen-sentient-aether-plasma-nebula-moth.wgsl — ✅ PASS

L284 stored undefined `color`; accumulated variable is `col`. Typo fix:

```diff
-    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
+    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
```

No slider/preset bindings touched; no restyling. No git commit performed.
