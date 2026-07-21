# Fix 4 — `dataTextureB` clobber of `dataTextureC` feedback

**Date:** 2026-07-21 · **Status:** ✅ Complete (picked up after Kimi agents 1/2/3/5)

## Root cause

In `src/renderer/webgpu/frame.ts` (and mirrored WASM `frame.cpp`), after each chained slot that
reads binding 9 (`dataTextureC`), the host copied:

1. `dataTexA → dataTexC` (if wrote A)
2. `dataTexB → dataTexC` (if wrote B) ← **last write wins**

Shaders that store **primary sim state in A** and **aux/detail in B** therefore sampled B's
contents as next-frame state. Confirmed broken by Lane D on:

- `liquid-touch` (phi/velocity state → clobbered by curvature pack)
- `gen-belousov-zhabotinsky` (reaction concentrations → Laplacian pack)
- `gen-acid-lissajous` (trail color → drift pack)

Fleet-wide grep: **57 shaders** write both A and B while reading C — all benefit from A-last.

Parallel slots never refreshed C at all → temporal feedback frozen in parallel mode.

## Fix

### Contract (documented in `docs/BINDING_CONTRACT.md`)

- **dataA** = primary feedback state
- **dataB** = secondary / detail
- Copy order when any shader reads C: **B first, then A** so A wins when both written

### Code

| File | Change |
|------|--------|
| `src/renderer/webgpu/frame.ts` | Chained: B→C then A→C. Parallel: after group, same order using aggregated writes. |
| `wasm_renderer/frame.cpp` | Both copy sites (dual-path render) reordered B then A. |
| `docs/BINDING_CONTRACT.md` | Feedback copy-order section + primary/secondary role notes. |

No shader rewrites required — host contract was wrong; shaders already wrote state to A.

## Validation

- Targeted WGSL gate on naga-fixed + feedback + guided-filter set: **18/18 exit 0**
- Jest (ShaderCompilation / bindingContract / GraphRunner / multipass): **31/31 pass**
- Full Jest suite: run after this note (see memory)

## Out of scope

- GraphRunner multipass barriers already plan per-role copies via `expandGraph` — not changed
- Shaders that intentionally store primary state in **B only** (no A write) still work: only B→C runs
- Visual GPU QA deferred (no adapter in this VM)
