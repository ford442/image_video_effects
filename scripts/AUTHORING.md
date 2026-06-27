# WGSL Authoring Guide

This doc is for anyone adding a new compute shader to Pixelocity. The goal is to
stay on the renderer's bind-group contract so we stop authoring bugs that later
require fix-swarms.

## Quick start

```bash
# 1. Scaffold a new canonical compute shader
python3 scripts/new_shader.py my-cool-effect --category generative

# 2. Edit public/shaders/my-cool-effect.wgsl

# 3. Validate locally before committing
python3 scripts/wgsl_precommit_gate.py --files public/shaders/my-cool-effect.wgsl
```

## Canonical compute template

Copy from the template when hand-authoring:

```bash
cp public/shaders/_template_canonical_compute.wgsl public/shaders/my-effect.wgsl
```

The template contains the exact 13 bindings the renderer expects, the required
`Uniforms` struct, and a `(16, 16, 1)` workgroup size. Do not change binding
numbers or types unless you also update the renderer.

## `new_shader.py`

Usage:

```bash
python3 scripts/new_shader.py "My Cool Effect" --category generative
```

- Emits `public/shaders/my-cool-effect.wgsl`.
- Derives the binding contract from `scripts/bindgroup_checker.py` so it cannot
  drift from the source of truth.
- Refuses to overwrite an existing file.
- `--dry-run` prints the file instead of writing it.

## `wgsl_precommit_gate.py`

Fast, changed-files-only validation. Runs naga and the bindgroup checker on the
`.wgsl` files that differ from a base ref.

Usage:

```bash
# Against origin/main (default)
python3 scripts/wgsl_precommit_gate.py

# Against a different base
python3 scripts/wgsl_precommit_gate.py --base develop

# Explicit files
python3 scripts/wgsl_precommit_gate.py --files public/shaders/my-effect.wgsl

# JSON output
python3 scripts/wgsl_precommit_gate.py --json
```

It exits non-zero if any changed compute shader fails naga or bindgroup checks.

### `@workgroup_size` convention (3 explicit dimensions)

Pixelocity requires **three explicit workgroup dimensions** on compute entry points
(e.g. `@workgroup_size(16, 16, 1)`). WGSL allows two-arg forms (Z defaults to 1);
naga accepts them, but the gate flags `< 3` args as **`[WARN]`** (non-blocking).

The check counts comma-separated arguments after stripping comments, so override
forms like `@workgroup_size(block_width)` are caught as 1-arg violations.

Local auto-fix (literal `(int, int)` only):

```bash
python3 scripts/wgsl_precommit_gate.py --files public/shaders/my-effect.wgsl --fix
```

Never auto-fixes override or single-arg forms.

### Orphan shader definition audit

Offline report for `shader_definitions/**/*.json` entries missing local WGSL:

```bash
python3 scripts/audit_orphan_shader_defs.py
```

Writes `reports/orphan_shader_defs.{json,md}`. Classifies entries as `local`,
`storage-only` (present in `public/shader_coordinates.json` and/or
`storage_manager/seed_shaders.json`), `allowlisted`, or `likely-broken`.

## Local pre-commit hook

Save this as `.git/hooks/pre-commit` (and `chmod +x .git/hooks/pre-commit`):

```bash
#!/bin/bash
set -e

# Run the WGSL gate against the merge base for the current branch.
BASE="origin/main"
python3 scripts/wgsl_precommit_gate.py --base "$BASE"
```

To use against `main` when on a feature branch:

```bash
BASE=$(git merge-base origin/main HEAD)
python3 scripts/wgsl_precommit_gate.py --base "$BASE"
```

## Source of truth

The immutable bind-group contract lives in:

- `scripts/bindgroup_checker.py` -> `EXPECTED_BINDINGS`
- `public/shaders/_template_canonical_compute.wgsl`

If a new renderer feature needs a different layout, update the checker and the
template together, then re-run the gate over the whole library.
