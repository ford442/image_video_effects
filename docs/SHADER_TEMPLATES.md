# Shader templates (`public/shaders/_*`)

Pixelocity keeps **authoring templates** in `public/shaders/` with a leading underscore.
These files are **not catalog effects** — they are excluded from the unified manifest by:

- `scripts/generate_shader_lists.js` (skips defs without JSON; templates have no JSON)
- `scripts/audit_orphan_shader_defs.py` (`template-prefix` classification for `_*.wgsl`)
- `scripts/bindgroup_checker.py` (`TEMPLATE_FILES` list)

## Files

| File | Purpose |
|------|---------|
| `_template_canonical_compute.wgsl` | Canonical 13-binding compute stub used by `scripts/new_shader.py` |
| `_template_shared_memory.wgsl` | Shared-memory tile example |
| `_template_workgroup_atomics.wgsl` | Workgroup atomics example |
| `_hash_library.wgsl` | Shared hash/noise snippets (included conceptually by upgraded shaders) |

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
