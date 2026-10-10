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

**Catalog shaders include the prelude; none may paste it.** The migration
(#1313) runs by category. Shaders that still paste the header are listed in
[`src/contracts/prelude_migration.json`](../src/contracts/prelude_migration.json)
`pending`, each with a reason, and that list may only shrink.
`scripts/check_prelude_migration.py` (CI and `npm run verify:prelude-migration`)
fails on a newly pasted header, on an edited shader still pending as `eligible`,
and on a stale or growing list. The fix is always one command:

```bash
python3 scripts/migrate_to_prelude.py --files public/shaders/<id>.wgsl
```

The codemod removes the 13 declarations and `struct Uniforms`, puts the include
where the first declaration was, and proves each file before writing it (code
tokens, comments, expanded declarations, bindgroup/extraBuffer gate verdicts;
`--naga` adds the naga verdict). It never touches `params`, packing, or the
`Upgraded:` line — a header swap is not an upgrade. The 22 shaders it refuses
have a non-canonical header (14 swap `zoom_params`/`zoom_config` in
`struct Uniforms`, a real layout bug) and need a reviewed fix instead.

**`_hash.wgsl` collides with most of the catalog.** 1,168 shaders already define
their own `hash`, `fbm` or `noise`. Including it into one of them will not
compile until you delete the shader's own copies.

Expansion happens at the two fetch seams — `src/utils/fetchShaderWgsl.ts` for
WebGPU and `src/wasm/bridge/shader.ts` for WASM — because `ShaderCompilation.ts`
receives a finished string and cannot fetch a library. C++ has no parser: it
rejects any source where a directive survived.

`_prelude.wgsl` itself is compiled into the bundle (`src/wasm/bridge/wgslLibraries.ts`,
generated) and both seams resolve it from there first: the app deploy does not
ship `public/shaders`, and the storage API and blob: URLs have no sibling
directory to fetch it from. Other libraries are fetched next to the shader.

## Generated libraries

`_prelude.wgsl` and `_hash.wgsl` are **not hand-edited**:

```bash
npm run shaders:libs         # regenerate both (+ the bundled copy in wgslLibraries.ts)
npm run verify:wgsl-include  # fails if any is stale
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

## Definition format

`shader_definitions/<category>/<id>.json` is validated against [`src/contracts/shader_definition.schema.json`](../src/contracts/shader_definition.schema.json) (JSON Schema 2020-12, no unknown top-level keys). The TypeScript type `src/types/ShaderDefinition.ts` and the standalone validator `src/contracts/shaderDefinition.validate.js` are generated from it by `node scripts/generate-shader-definition-types.mjs` and committed.

- **One slider key:** `params[]` = `{ id, name, default, min, max, step?, mapping?, audio?, description?, labels? }`. `mapping` is the WGSL uniform lane (`zoom_params.x`), `audio` is `bass | mid | treble | overall` or `{ "fft": bin }`.
- **`x-meta`** holds everything that is not shader behaviour: swarm output (`x-meta.upgrade.params`, formerly top-level `updatedParams`), provenance (`seeded_by`, `author`, `target_rating`, …) and verbatim redundant legacy containers (`x-meta.legacy`). The app never reads it and `generate_shader_lists.js` strips it from `public/shader-lists/`.
- **File name = id.** `category` is optional; when present it must equal the folder. Ids are unique; param ids are unique per shader; `min <= default <= max`.
- **id vs WGSL stem:** the WGSL file should be named after the id. The exact exceptions live in `scripts/catalog_id_url_allowlist.json` (pinned `id -> stem` pairs, enforced by `scripts/audit_catalog_consistency.py`); do not add new ones.

```bash
npm run verify:shader-definitions     # schema + cross-field rules, every definition
npm run verify:generated-sync         # registry / lists / aliases / generated type match a fresh regeneration
python3 scripts/migrate_shader_definitions.py --write   # fold legacy keys (idempotent; re-run after rebasing)
```

## CI gate

`python3 scripts/audit_orphan_shader_defs.py` fails when:

- any definition lacks a local WGSL (`only_def` > 0), or
- any non-template WGSL lacks a catalog entry (`only_wgsl` > 0)

`python3 scripts/audit_catalog_consistency.py --gate` (blocking) fails on any definition ↔ WGSL ↔ multipass-registry ↔ list drift beyond `reports/catalog_drift_baseline.json`; the baseline may only shrink. A WGSL file named by a multipass `graph.nodes[].entry`, `nextShader` or `passes[].file` is a secondary pass, not an orphan.

Use `scripts/seed_orphan_shader_defs.py --write` to backfill JSON for legacy orphan WGSL (one-time / batch hygiene).

Cross-reference: `docs/AUTHORING.md`, `scripts/bindgroup_checker.py` (`TEMPLATE_FILES`).
