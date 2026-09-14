# Luminescent / magnetic generative ten — agent contract (2026-09-14)

Repo: /root/image_video_effects. Shaders: `public/shaders/<id>.wgsl`. Definitions: `shader_definitions/generative/<id>.json`.
Reference exemplar (already upgraded): `public/shaders/gen-ethereal-quantum-glass-nautilus.wgsl` + its JSON.

## Floor (every shader must end in this state)
1. **Full 13-binding contract** — exactly bindings 0..12 in this order/type, nothing added/removed/renamed:
   ```
   @group(0) @binding(0) var u_sampler: sampler;
   @group(0) @binding(1) var readTexture: texture_2d<f32>;
   @group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
   @group(0) @binding(3) var<uniform> u: Uniforms;
   @group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
   @group(0) @binding(5) var non_filtering_sampler: sampler;
   @group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
   @group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
   @group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
   @group(0) @binding(9) var dataTextureC: texture_2d<f32>;
   @group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
   @group(0) @binding(11) var comparison_sampler: sampler_comparison;
   @group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
   ```
   Uniforms: `config` (x=time, y=rippleCount/click count, zw=resolution), `zoom_config` (x=time, yz=mouse uv, w=mouse down), `zoom_params` (4 sliders), `ripples: array<vec4<f32>, 50>` (xy=pos, z=start time).
2. **ACES + semantic alpha** — ACES tone map on the display color; alpha must mean something (coverage/density/glow/SDF proximity), never a hardcoded `1.0`. Write the same final RGBA to `writeTexture` and `dataTextureA`. Write depth to `writeDepthTexture`. **dataTextureA writeback only** — do NOT write dataTextureB.
3. **Exact textureLoad from dataTextureC** — any temporal feedback reads `textureLoad(dataTextureC, coord, 0)` with integer coords. Replace `textureSampleLevel(dataTextureC, ...)` with an exact load (clamp coords). Never textureStore to dataTextureC.
4. **plasmaBuffer audio** — `let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;` (clamp 0..1) drive key visuals with controlled gains (e.g. `* (1.0 + bass * 0.3..0.5)`). **Delete every fake audio source**: `u.config.y` (click count), `u.config.z/w` (resolution), `u.zoom_config.x` (time) used as "audio"/intensity, and any `extraBuffer[...]` read pretending to be audio. Resolution use for aspect/coords is fine.
5. **Bounded extraBuffer[133..138]** — only indices 133..138 may be read/written, each guarded: `if (arrayLength(&extraBuffer) > 138u) { ... }`. Any other index (e.g. extraBuffer[0], [6..13]) must be removed or moved into 133..138. Don't add new springs; only keep/relocate existing state.
6. **Preserve mouse / held / click-ripple** — keep existing mouse interaction; mouse-held (`zoom_config.w`) and click ripples (`u.ripples[i]`, loop to `min(u32(u.config.y), 50u)`) must work. If a shader lacks ripples entirely, add a small, identity-native click response.
7. **naga-clean** — `naga public/shaders/<id>.wgsl` must pass. `@workgroup_size(16, 16, 1)`.
8. **4 named params in JSON** — all four `zoom_params.x/y/z/w` must be read in WGSL and visibly change output (no dead sliders). JSON keeps `updatedParams` (index 0..3) with human names/default/min/max/step **byte-exact to current values** (do not change saved defaults/ranges/names). Add a matching `params` array (id camelCase, name, mapping `zoom_params.x`..`w`, same default/min/max/step) if missing. `features` must include `"audio-reactive", "mouse-driven", "upgraded-rgba"` (keep existing entries). Keep `id`, `url`, `name`, `category`, tags untouched. Uniforms comment should list the 4 slider names.

## Innovation (per shader)
Two **native** ideas each — grounded in the shader's own subject (diatom biology, anglerfish anatomy, magnetism physics, ferrofluid Rosensweig instability…), not generic noise/bloom/IQ-palette overlays. Keep identity and existing core functions. No new springs. No replacing the motif.

## Header (replace the top comment block with this format)
```
// ═══════════════════════════════════════════════════════════════════
//  <Display Name>
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: <keep or High>
//  Upgraded: 2026-09-14
//  Ideas: <idea 1>; <idea 2>
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════
```
(Remove duplicate/legacy header blocks and "COPY PASTE THIS HEADER" junk.)

## Verify before reporting
```
cd /root/image_video_effects
naga public/shaders/<id>.wgsl
python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl
python3 scripts/audit_extrabuffer.py --files public/shaders/<id>.wgsl
grep -n "plasmaBuffer\[\|extraBuffer\[\|dataTextureC\|dataTextureB\|u.config.y\|zoom_params" public/shaders/<id>.wgsl
python3 -c "import json;json.load(open('shader_definitions/generative/<id>.json'))"
```
Do NOT run generate_shader_lists / git commit / touch other shaders — the coordinator does that.

## Card
Write an Idea Card section for each of your shaders to `agents/swarm-outputs/claude-2026-09-14-luminescent-magnetic-ten/card-<id>.md`:
```
SHADER: <id>
IDENTITY: ...
KEEP VERBATIM: ...
ADD (2 native ideas):
  1. ...
  2. ...
FLOOR FIXES: ... (fake audio removed, C load, extraBuffer relocation, etc.)
FORBID: ...
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live
```
