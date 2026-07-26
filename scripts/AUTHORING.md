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

Fast validation. Runs naga and the bindgroup checker on changed `.wgsl` files,
or a full-tree workgroup/bindgroup scan with `--full-tree`.

Usage:

```bash
# Against origin/main (default) — changed files only
python3 scripts/wgsl_precommit_gate.py

# Full-tree convention scan (CI; skips naga for speed)
python3 scripts/wgsl_precommit_gate.py --full-tree

# Against a different base
python3 scripts/wgsl_precommit_gate.py --base develop

# Explicit files
python3 scripts/wgsl_precommit_gate.py --files public/shaders/my-effect.wgsl

# JSON output
python3 scripts/wgsl_precommit_gate.py --json
```

It exits non-zero if any compute shader fails naga, bindgroup checks, or
workgroup-size convention checks.

### `@workgroup_size` convention (3 explicit dimensions — **blocking**)

Pixelocity requires **three explicit workgroup dimensions** on compute entry points
(e.g. `@workgroup_size(16, 16, 1)`). WGSL allows shorter forms; naga accepts
them, but the gate **fails** any compute shader with fewer than 3 args.

| Form | Gate |
|------|------|
| `@workgroup_size(16, 16, 1)` | pass |
| `@workgroup_size(8, 8)` | **blocking** (2-arg) |
| `@workgroup_size(block_width)` (override) | **blocking** (1-arg) |

Grandfathered paths may be listed in `reports/workgroup_grace_allowlist.json`
(shrink over time as shaders are fixed).

The check counts comma-separated arguments after stripping comments.

Local auto-fix (literal `(int, int)` only):

```bash
python3 scripts/wgsl_precommit_gate.py --files public/shaders/my-effect.wgsl --fix
```

**Changed-files gate** (`--base origin/main`): naga + bindgroup + workgroup on
diff only. **Full-tree scan** (`--full-tree`): bindgroup + workgroup on all
`public/shaders/*.wgsl` (no naga).

Never auto-fixes override or single-arg forms.

### Orphan shader definition audit

Offline report for `shader_definitions/**/*.json` entries missing local WGSL:

```bash
python3 scripts/audit_orphan_shader_defs.py --ci-gate
python3 scripts/audit_orphan_shader_defs.py --base origin/main
```

Writes `reports/orphan_shader_defs.{json,md}`. Audits **both directions** (full tree).

**CI gate** (`--ci-gate`): exits 1 when any full-tree definition is
`likely-broken` or `parse-error` and its id is not in
`reports/orphan_baseline.json`. `local`, `storage-only`, and `allowlisted` always pass.

**Forward-only enforcement** (with `--base`): exits 1 only when a **changed**
definition JSON is `likely-broken` or `parse-error`. Use for local pre-commit hooks.

Use `--no-fail` for report-only runs. `--fail-all` restores legacy full-tree
failure (includes orphan WGSL files).

Templates (`_*.wgsl`) and multipass secondaries are excluded — see
`docs/SHADER_TEMPLATES.md`.

Backfill legacy orphan WGSL:

```bash
python3 scripts/seed_orphan_shader_defs.py --write
node scripts/generate_shader_lists.js
```

## Swarm guardrail audits

Two offline auditors catch recurring generative-swarm regressions. Both use a
**forward-only triage baseline** — legacy violations are grandfathered in
`reports/*_baseline.json`; only **new** violations fail CI.

### `audit_extrabuffer.py` — FFT-zone footgun (blocking in CI)

Index map (`agents/WGSL_BUILTINS_GENERATIVE.md`):

| Range | Owner |
|-------|-------|
| `[0..4]` | Engine-reserved (CPU-written) |
| `[5..132]` | Engine FFT bins — **stomped every audio frame** |
| `[133..255]` | Safe persistent shader state |

```bash
npm run audit:extrabuffer
python3 scripts/audit_extrabuffer.py --files public/shaders/my-effect.wgsl
```

Fails on any WGSL **write** to `extraBuffer[i]` for `i` in `0..132` not in the
triage baseline. Reads are allowed. Dynamic-index writes are reported as
warnings (use `--strict` to fail).

The pre-commit gate (`wgsl_precommit_gate.py`) also runs this check on changed
compute shaders (baseline-aware).

### `audit_dead_sliders.py` — JSON params never read in WGSL

Compares `params` / `controls` uniform mappings against WGSL reads of
`u.zoom_params.x/y/z/w` (including alias and index forms).

```bash
npm run audit:dead-sliders
npm run audit:dead-sliders:generative   # faster swarm loop
python3 scripts/audit_dead_sliders.py --files my-shader-id
```

Writes `reports/dead_sliders_audit.{json,md}`. CI runs this in a **grace
period** (non-blocking) until the generative `updatedParams` pool is closed;
then flip to blocking.

### Generative batch completion checklist

After each 8-shader upgrade batch:

1. `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<batch>.wgsl`
2. `npm run audit:extrabuffer` (or `--files` on batch WGSL)
3. `npm run audit:dead-sliders -- --files <id1> <id2> …`
4. `node scripts/generate_shader_lists.js` + duplicate check
5. `npx react-scripts test --watchAll=false --ci`

## Local pre-commit hook

Save this as `.git/hooks/pre-commit` (and `chmod +x .git/hooks/pre-commit`):

```bash
#!/bin/bash
set -e

# Run the WGSL gate against the merge base for the current branch.
BASE="origin/main"
python3 scripts/wgsl_precommit_gate.py --base "$BASE"
python3 scripts/audit_orphan_shader_defs.py --base "$BASE"
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
