# Shader templates (`public/shaders/_*`)

Pixelocity keeps **authoring templates** in `public/shaders/` with a leading underscore.
These files are **not catalog effects** — they are excluded from the unified manifest by:

- `scripts/generate_shader_lists.js` (skips defs without JSON; templates have no JSON)
- `scripts/audit_orphan_shader_defs.py` (`template-prefix` classification for `_*.wgsl`)
- `scripts/bindgroup_checker.py` (`TEMPLATE_FILES` list)

## Files

| File | Purpose |
|------|---------|
| `_prelude.wgsl` | **Includable.** The 13 canonical bindings + `struct Uniforms`. Generated — see below. |
| `_hash.wgsl` | **Includable.** The hash/noise functions, no bindings. Generated from `_hash_library.wgsl`. |
| `_template_canonical_compute.wgsl` | Canonical compute stub used by `scripts/new_shader.py`; includes `_prelude.wgsl` |
| `_template_shared_memory.wgsl` | Shared-memory tile example |
| `_template_workgroup_atomics.wgsl` | Workgroup atomics example |
| `_hash_library.wgsl` | Standalone copy-paste reference: the same functions **plus** a repeated binding header so the file parses on its own. Source for `_hash.wgsl`. |

## `#include`

`_`-prefixed libraries are really included, not "conceptually" included:

```wgsl
#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) { ... }
```

Textual substitution of whole files and nothing else — no macros, no conditionals,
no include guards. Contract: [`src/contracts/wgsl_include.json`](../src/contracts/wgsl_include.json).

- Only `_`-prefixed `.wgsl` files may be included, so a 2,000-line catalog effect
  cannot be inlined into another shader.
- `public/shaders` is flat; a path separator is rejected, not resolved.
- Cycles, nesting past 8, and **including the same library twice** are all errors.
  WGSL has no include guards, so a second copy would redeclare every symbol.
- A shader with no directive is returned byte-identical, which is nearly all of them.

**Migration is opt-in.** The catalog was not rewritten. Converted so far: the
canonical template and the five Physics Lab graph entry passes.

**`_hash.wgsl` collides with most of the catalog.** 1,168 shaders already define
their own `hash`, `fbm` or `noise`. Including it into one of them will not
compile until you delete the shader's own copies.

Expansion happens at the two fetch seams — `src/utils/fetchShaderWgsl.ts` for
WebGPU and `src/wasm/bridge/shader.ts` for WASM — because `ShaderCompilation.ts`
receives a finished string and cannot fetch a library. C++ has no parser: it
rejects any source where a directive survived.

## Generated libraries

`_prelude.wgsl` and `_hash.wgsl` are **not hand-edited**:

```bash
npm run shaders:libs         # regenerate both
npm run verify:wgsl-include  # fails if either is stale
```

`_prelude.wgsl` comes from `scripts/bindgroup_checker.py` `EXPECTED_BINDINGS`
plus `src/contracts/uniforms_layout.json` — the same sources the gates check
against, so it cannot drift into being a fourth hand-copied header. To change a
binding, change the contract. Binding 13 (`historyTexture`) is optional and is
**not** in the prelude; the 11 shaders that use it declare it themselves.

## Policy

1. **Shipped effects** must have all three: `shader_definitions/<category>/<id>.json`, `public/shaders/<id>.wgsl`, and a list entry (via `generate_shader_lists.js`).
2. **Templates / internal libraries** use the `_` prefix and do not need JSON definitions.
3. **Multipass secondary passes** (`*-pass2.wgsl`, etc.) are referenced from the primary JSON `multipass.passes[]` or `src/renderer/multipassRegistry.ts` and do not need their own catalog entry.
4. **Subgroup variants** (`*-sg.wgsl`) are optional compile-time variants; no separate JSON when the base effect is cataloged.

## Scaffolding a new shipped effect

```bash
python3 scripts/new_shader.py my-new-effect --category generative
node scripts/generate_shader_lists.js
python3 scripts/audit_orphan_shader_defs.py
```

`new_shader.py` creates both WGSL and JSON. Do not use `--skip-json` unless you are adding a deliberate multipass secondary file.

## CI gate

`python3 scripts/audit_orphan_shader_defs.py` fails when:

- any definition lacks a local WGSL (`only_def` > 0), or
- any non-template WGSL lacks a catalog entry (`only_wgsl` > 0)

Use `scripts/seed_orphan_shader_defs.py --write` to backfill JSON for legacy orphan WGSL (one-time / batch hygiene).

Cross-reference: `scripts/AUTHORING.md`, `scripts/bindgroup_checker.py` (`TEMPLATE_FILES`).
