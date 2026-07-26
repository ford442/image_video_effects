# bioluminescent-bloom — Batch 16 Upgrade Notes (Kimi)

**Date:** 2026-07-26
**Shader:** `public/shaders/bioluminescent-bloom.wgsl`
**JSON:** `shader_definitions/generative/bioluminescent-bloom.json`

## Line Delta
- Before: 194 lines
- After: 259 lines
- Delta: **+65** (within target 244–284 / +50–90)

## Key Changes per Technique

### 1. FIX: Double ACES tonemap (priority 1)
- Removed the second `col = acesToneMap(col * 1.1);` pass at the end of the
  output path — output is now tone-mapped exactly ONCE.
- Added `huePreserveClamp(c, ceiling)` helper: scales the HDR color so its
  brightest channel is ≤ ceiling while preserving channel ratios (hue intact).
- The HDR bloom term (`vec3(0.4, 0.8, 1.0) * bloom`) is now hue-preserving
  clamped at **1.2 BEFORE** the single ACES tonemap — quorum wave crests stay
  hot without clipping the palette.
- Fixed stale struct comment: `config.y` now correctly documented as
  `RippleCount (engine)` per the verified UniformBuffer truth (was
  `MouseClickCount`). Comment-only fix; no semantics changed.

### 2. Per-tendril spectrum
- Each tendril `ti` reads `plasmaBuffer[(ti % 8) + 1].x` into `band`.
- `band` phase-offsets the sway waves (`wave`, `wave2`), the node pulse phase
  (`+ band * 6.2831`), and subtly modulates tendril width, node size, and
  tendril brightness — every tendril dances to its own FFT bin instead of all
  following the global bass/mids/treble.

### 3. Spring-damper nutrient source
- New `springStep()` helper implements a critically-damped spring
  (`accel = ω²(aim − pos) − 2ω·vel`, ω = 6.0, dt = 0.016).
- State persisted in `extraBuffer[133..134]` (position) and `[135..136]`
  (velocity), init flag at `[137]` (snaps spring to cursor on first contact).
  All within the allowed [133..255] shader-state region.
- Thread (0,0) integrates and writes the spring state; all threads read it.
- `nutrientAim` (eased position) now drives both the chemotaxis gradient
  direction and the nutrient pellet drop — trails read as pursuit, not snap.

### 4. Slider wiring (4 params, existing ids/defaults/mapping preserved)
- `zoom_params.x` — **Tendril Count**: `3 + i32(x * 5.0)` strands (3–8).
- `zoom_params.y` — **Pulse Speed**: `0.2 + y * 2.0`; now drives both the
  tendril sway tempo AND the node pulse rate (was sway only).
- `zoom_params.z` — **Dot Density**: rewired from a pure size scalar to a real
  density control — `dotGate = step(hash21(...), 0.15 + z * 0.85)` ignites a
  fraction of grid cells, and dot size scales with `0.3 + z * 0.7`.
- `zoom_params.w` — **Glow Radius**: rewired from ambient-only to control the
  falloff radius and intensity of the ambient halo AND the volumetric scatter
  cone (`smoothstep(0.2 + w * 0.5, ...)`).

## Binding Contract Compliance
- Canonical 13-binding layout preserved verbatim (0–12, no renumbering, no
  binding 13 added). `dataTextureB`/`comparison_sampler` remain declared-but-
  unused exactly as before (pre-existing pattern).
- `@workgroup_size(16, 16, 1)` preserved.
- Writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every
  frame; `dataTextureA` packing `(un, vn, glow, density)` unchanged.
- Gray-Scott constants preserved VERBATIM: Du=0.18, Dv=0.09,
  feed base 0.025, kill base 0.055. `dataTextureA` sim state never
  clamped/tonemapped beyond the existing [0,1] state clamp.
- `extraBuffer` usage restricted to [133..137] (within [133..255]).
- `textureSampleLevel(..., 0.0)` for sampler reads; no reserved WGSL keywords
  used as identifiers (`target` avoided — used `nutrientAim`).
- JSON written verbatim from the brief's fenced block (updatedParams index
  0–3, updated:true, ids/defaults/mappings unchanged).

## Gate Status
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/bioluminescent-bloom.wgsl`
- **GREEN**: Passed 1, Failed 0, Workgroup errors 0, **Warnings 0**.
- Note: `naga` binary is not installed in this environment, so naga
  validation was skipped by the gate (bindgroup + workgroup checks still ran
  and passed). This matches other shaders in the repo under the same gate.

## QA Flags
- ⚠️ naga validation skipped (binary unavailable) — recommend a CI run with
  naga for full syntax validation.
- ⚠️ No GPU in this environment — visual/audio-reactive behavior not
  exercised; validated structurally only.
- Spring state uses thread (0,0) write / others read without barriers —
  standard pattern for these shaders; worst case is one-frame lag on the
  eased nutrient position, which is visually benign (it is an easing filter).
- `reports/wgsl_precommit_report.json` is shared/auto-generated and may be
  overwritten by concurrent swarm agents; not a defect of this shader.
