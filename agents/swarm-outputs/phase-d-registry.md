# Phase D Agent Swarm Registry

**Status:** ✅ COMPLETE  
**Started:** 2026-06-28  
**Goal:** Fix bind-group incompatibilities, standardize workgroup sizes, and optimize renderer/shader integration.

---

## Discovery Summary

**Fresh bind-group compatibility run:**
- **Total shaders:** 1,266
- **Compatible:** 1,256
- **Incompatible:** 6
- **Templates:** 4
- **Render shaders:** 0

**Incompatible shaders (6):**
| Shader | Issue | Fixable? |
|--------|-------|----------|
| `_hash_library` | No compute entry point (library file) | ❌ Expected / skip |
| `deep-workgroup-multi-effect-blend` | `@workgroup_size(16, 16, 4)` (deep workgroup) | ✅ Keep intentionally; add `requiresDeepWorkgroup` marker |
| `gen-showcase-nebula-core` | Missing `@workgroup_size` | ✅ Add canonical workgroup size |
| `molten-gold` | Binding 10 `array<f32>` mismatch; extra binding 11 `videoTexture` | ✅ Restructure bindings |
| `plasma` | Binding 12 custom `array<PlasmaBall, 50>` | ✅ Rewrite to canonical `array<vec4<f32>>` or use `plasmaBuffer` layout |
| `tone-histogram-apply` | Binding 10 `array<atomic<u32>>` | ✅ Convert to `array<f32>` or use atomic-compatible path |

**Workgroup size distribution:**
- `(16, 16, 1)`: 1,185 ✅
- `(8, 8, 1)`: 75 ⚠️ (pre-existing, renderer accepts)
- `(64, 1, 1)`: 2 ⚠️ (non-standard)
- `(16, 16, 4)`: 1 ⚠️ (deep workgroup)

**Conclusion:** Phase D focuses on binding compatibility fixes and conservative renderer hot-path optimizations.

---

## Standards Checklist

- [x] Keep canonical 13-binding header where possible.
- [x] If a shader genuinely needs a non-standard binding (e.g. atomic histogram, videoTexture), document it and add renderer fallback.
- [x] Add canonical `@workgroup_size(16, 16, 1)` unless deep-workgroup is intentional.
- [x] For intentional deep-workgroup shaders, add a `requiresDeepWorkgroup: true` marker in JSON and header comment.
- [x] Preserve alpha rules and zoom_param clamping.
- [x] Validate with `naga <file> /tmp/out.wgsl`.
- [x] Validate with `python3 scripts/bindgroup_checker.py` after fixes.

---

## Agent Assignments

### Agent 1d — Binding Compatibility Specialist
**Target:** Fix the 5 fixable incompatible shaders.

Files:
1. `/root/image_video_effects/public/shaders/gen-showcase-nebula-core.wgsl`
2. `/root/image_video_effects/public/shaders/molten-gold.wgsl`
3. `/root/image_video_effects/public/shaders/plasma.wgsl`
4. `/root/image_video_effects/public/shaders/tone-histogram-apply.wgsl`
5. `/root/image_video_effects/public/shaders/deep-workgroup-multi-effect-blend.wgsl` (mark intentional, ensure JSON has `requiresDeepWorkgroup`)

Approach per shader:
- `gen-showcase-nebula-core`: add `@workgroup_size(16, 16, 1)` and ensure canonical bindings.
- `molten-gold`: remove `videoTexture` extra binding; fix `extraBuffer` type to `array<f32>` read_write; restructure math to use `plasmaBuffer` or `extraBuffer`.
- `plasma`: rewrite binding 12 from `array<PlasmaBall, 50>` to canonical `array<vec4<f32>>` (use `plasmaBuffer` layout or pack custom data into vec4s).
- `tone-histogram-apply`: convert atomic histogram to non-atomic `array<f32>` read_write path, or use a separate compute path if atomics are required.
- `deep-workgroup-multi-effect-blend`: ensure header comment notes deep-workgroup; update JSON definition to include `requiresDeepWorkgroup: true`.

### Agent 2d — Workgroup Standardization Specialist
**Target:** Audit and standardize workgroup sizes on the safest subset.

- Review the 20 smallest shaders with `@workgroup_size(8, 8, 1)`.
- Convert them to `(16, 16, 1)` if they do NOT use shared memory, barrier synchronization, or 64-thread assumptions.
- Review the 2 shaders with `@workgroup_size(64, 1, 1)`.
- Leave any algorithmically-dependent 8×8 shaders unchanged and document them in the registry.
- Validate each change with `naga`.

### Agent 3d — Renderer Hot-Path Optimizer
**Target:** Optimize TypeScript renderer code in `src/renderer/` without changing behavior.

Files:
- `/root/image_video_effects/src/renderer/WebGPURenderer.ts`
- `/root/image_video_effects/src/renderer/ShaderCompilation.ts`

Optimizations:
- Reduce redundant `copyTextureToTexture` calls between chained slots when the intermediate result is not needed.
- Cache `blitBindGroup` recreation in `updateBlitBindGroup` (only recreate if dimensions changed).
- Batch uniform buffer writes if multiple fields are updated together.
- Add fast path for single-shader pipelines to skip slot iteration overhead.

**Important:** Do not change the public API or bind-group layout. Keep changes minimal and well-commented.

### Agent 4d — Integration Test / Compatibility Auditor
**Target:** Run the full compatibility + naga validation suite and produce a final report.

Steps:
1. Run `python3 scripts/bindgroup_checker.py` and capture results.
2. Run `naga` on every shader touched by Agents 1d/2d.
3. Run `node scripts/generate_shader_lists.js`.
4. Optionally run `npx react-scripts test --watchAll=false --ci` if tests cover renderer code.

### Agent 5d — QA & Integration
**Target:** Aggregate all changes, update this registry, ensure reports are regenerated.

**Status:** ✅ COMPLETE

---

## QA Results

| Check | Result | Details |
|-------|--------|---------|
| Bind-group compatibility | ✅ | 1,261 compatible / 1 incompatible (`_hash_library`, expected) |
| Naga validation | ✅ | 25/25 touched shaders passed |
| Shader-list generation | ✅ | `node scripts/generate_shader_lists.js` succeeded |
| Unit tests | ✅ | 21 suites, 178 tests passed |
| Build | ✅ | `SKIP_WASM_BUILD=1 npm run build` passed |
| Standalone type check | ⚠️ | `npx tsc --noEmit` has pre-existing errors in `node_modules/@xenova/transformers` (non-blocking) |

---

## Success Criteria

- [x] Incompatible shader count drops from 6 to 1 (`_hash_library` expected).
- [x] No new naga failures introduced.
- [x] Renderer changes pass existing unit tests or build.
- [x] Shader lists regenerate successfully.
- [x] Phase D registry marked ✅ COMPLETE.
