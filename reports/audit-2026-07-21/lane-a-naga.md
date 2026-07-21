# Lane A — naga WGSL Audit (2026-07-21)

- **Tool:** `naga` CLI v29.0.3 (`/root/.cargo/bin/naga`), invoked as `naga <file.wgsl>` (parse + full validation, no output emitted).
- **Scope:** `public/shaders/*.wgsl` — all **1314** files validated, nothing skipped.
- **Result:** ✅ **1310 passed** / ❌ **4 failed** (matches the prior repo-wide scan's 4 failing generative shaders; total file count grew 1313 → 1314, new file passes).

## Exclusions
9 `*.wgsl.backup` files exist in the directory (gen-art-deco-sky, gen-biomechanical-hive, gen-chromatic-metamorphosis, gen-chronos-labyrinth, gen-ethereal-anemone-bloom, gen-fractured-monolith, gen-magnetic-ferrofluid, gen-prismatic-bismuth-lattice, gen_mandelbulb_3d). They are not `.wgsl` files and were **not** validated — flagged separately per instructions.

## Failures — grouped by root cause

### 1. Nested function declaration (missing closing brace) — 1 shader
**`public/shaders/gen-ethereal-cyber-plasma-void-dragon.wgsl`** (line 114)
```
error: expected assignment or increment/decrement, found "map"
114 │ fn map(p: vec3<f32>, ...) -> vec2<f32> {
```
**Root cause:** `fn map(...)` is declared at line 114 while still lexically inside the previous function's body (lines 100–111 are mid-function). A `}` is missing before line 114; WGSL does not allow nested function declarations.

### 2. Builtin shadowed by local variable — 1 shader
**`public/shaders/gen-radiant-cyber-plasma-astro-griffin.wgsl`** (line 63)
```
error: local declaration cannot be called
63 │ return length(max(d, vec3<f32>(0.0))) + ...
```
**Root cause:** `let length = 0.5 + span * 0.5;` at line 59 declares a local named `length`, shadowing the `length()` builtin. The call on line 63 then tries to "call" an f32. Rename the local (e.g. `featherLen`).

### 3. Mixed signed/unsigned comparison — 1 shader
**`public/shaders/gen-sentient-cyber-chrono-void-serpent.wgsl`** (line 147)
```
error: Entry point main at Compute is invalid
= Operation GreaterEqual can't work with i32 and u32
147 │ if (tex_coords.x >= dimensions.x || tex_coords.y >= dimensions.y) {
```
**Root cause:** `tex_coords` is `vec2<i32>` but `textureDimensions()` returns `vec2<u32>`. Cast one side, e.g. `tex_coords.x >= i32(dimensions.x)` (or build tex_coords with `vec2<u32>(id.xy)`).

### 4. Undefined identifier (typo) — 1 shader
**`public/shaders/gen-sentient-aether-plasma-nebula-moth.wgsl`** (line 284)
```
error: no definition in scope for identifier: `color`
284 │ textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
```
**Root cause:** The accumulated color variable is named `col` (lines 273–282); the final `textureStore` references nonexistent `color`. Typo — should be `col`.

## Bindgroup-convention check (secondary)

- **`scripts/bindgroup_checker.py`** runs repo-wide by default (no `--help`; it just runs): **1309 compatible / 1 incompatible / 4 templates** out of 1314. The single "incompatible" is `_hash_library.wgsl`, flagged only for "No @compute/@vertex/@fragment entry points" — it is an include-only template (`is_template: true`), i.e. a **false positive**, not a real bindgroup violation. (Note: running it rewrote `reports/bindgroup_compatibility_report.json` — same content, refreshed timestamp.)
- **`scripts/wgsl_precommit_gate.py --files ... --json`** on a 50-shader sample (46 random + the 4 naga-failures): 43 passed, 1 skipped (`_hash_library.wgsl`, template), 6 failed entries = the 4 unique naga-failing shaders (2 were also in the random sample), failing only at the naga stage. **Zero bindgroup-convention or workgroup violations** among the 44 naga-passing sampled shaders.

## Machine-readable report
`reports/audit-2026-07-21/lane-a-naga.json` (full error text + per-file root causes).
