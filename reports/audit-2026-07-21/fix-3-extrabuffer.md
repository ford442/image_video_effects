# Fix Agent 3 — Ungated reserved `extraBuffer[0..4]` writes (Lane C, finding 7a)

**Date:** 2026-07-21 · **Scope:** 68 ungated writes to reserved `extraBuffer` indices [0..4] across 36 files (`reports/audit-2026-07-21/lane-c-extrabuf.json`, category 7a) · **Commit:** none (working tree only)

## House convention (Task 1)

Single-invocation gating, confirmed from gate-green shaders already in the repo:
`gen-feedback-echo-chamber.wgsl`, `gen-ifs-fractal-flame.wgsl`, `gen-von-karman-vortex.wgsl`,
`hyperbolic-crystal-symbiosis.wgsl`, `echo-trace.wgsl` all wrap persistent-state writes in

```wgsl
if (global_id.x == 0u && global_id.y == 0u) { /* reserved-slot writes */ }
```

No atomic-based convention exists for these slots. Followed the single-invocation pattern,
using each file's own `global_invocation_id` parameter name (`gid` / `global_id` / `id`).

## Fix pattern (Task 2)

Contiguous runs of ungated literal writes `extraBuffer[N] = ...` (N ∈ 0..4) were wrapped in
`if (<gid>.x == 0u && <gid>.y == 0u) { ... }`. Reads were left ungated (per-pixel reads are
race-free and feed visuals); scratch slots ≥ 5 untouched; visuals/slider behavior preserved.

- **61 writes gated in 34 files.**
- **2 files needed no change** (audit false positives — already gated): `elastic-chromatic.wgsl`
  (`let isLeader = global_id.x == 0u && global_id.y == 0u;` → `if (isLeader)`) and
  `magnetic-interference.wgsl` (`if (pixel.x == 0 && pixel.y == 0)`).

### Files fixed (34)

elastic-chromatic* · electric-eel-storm · gen-alpha-aurora · gen-bioreactor-bloom ·
gen-celestial-weave · gen-chrono-mycelial-tapestry · gen-cryogenic-frost-plasma-matrix ·
gen-cybernetic-mycelium-neural-web (5 writes) · gen-echo-dunes ·
gen-ethereal-quantum-hologram-bonsai · gen-fireworks-audio-symphony · gen-ghost-flame
(2 writes, incl. **historyHead [4]**) · gen-hyper-dimensional-bismuth-matrix ·
gen-luminous-cauldron · gen-magnetic-ferrofluid-sculpture · gen-magnetic-kelp ·
gen-neon-snowfall · gen-neural-bioluminescence-matrix (5) · gen-neuro-fluid-plasma-lotus ·
gen-opal-circuit · gen-prismatic-crystal-growth ·
gen-prismatic-quantum-fractal-nautilus-engine · gen-resonant-quantum-plasma-dragon-eye ·
gen-sentient-ferro-silicate-swarm · gen-showcase-nebula-core (5) ·
gen-sierpinski-tetrahedron (5) · gen-topological-phase-weave · gen-translucent-nebula ·
gen-vortex-cathedral · gen-worley-cellular-noise (5) · holographic-crystal ·
magnetic-interference* · oscilloscope-overlay · phantom-lag (4) · pixel-stretch-cross (4) ·
waveform-glitch

\* already gated, verified only.

Batch fix script (repeatable): `temp/fix3_gate_reserved_writes.py`.

## Checker extension (Task 3)

`scripts/bindgroup_checker.py` — new `check_reserved_extrabuffer_writes(content)` in the
style of `check_workgroup_size_convention`:

- Strips comments first (`strip_wgsl_comments`), then matches literal writes
  `extraBuffer[0..4] =` (compound-assign included, `==` excluded).
- Gate detection: brace/single-statement span parser (`_block_spans`) finds enclosing
  `if` conditions; a write is gated if any enclosing condition is a (0,0)-invocation test —
  `<v>.x == 0u? && <v>.y == 0u?` (either order), `all(<v>.xy == vec2<u32>(0u…))`, or a bool
  variable initialized to such a test (`let isLeader = …`), resolved to fixpoint.
- Wired into `parse_shader`: violations set `status = "incompatible"` with per-line errors,
  so `scripts/wgsl_precommit_gate.py` now blocks this class of bug at gate time.
- Result dict gains `reserved_extrabuffer_writes: []`.

**Unit tests** (`scripts/test_bindgroup_checker.py`, +7 tests; fixtures
`bindgroup_extrabuf_{ungated,gated,gatevar}.wgsl`): ungated write flagged with correct
index/line; gated, gate-variable, brace-less `if`, comment-stripped, high-index (≥5), and
`==`-comparison cases all pass. **All tests pass** (standalone runner; pytest not installed
in this env). `test_workgroup_gate.py` and `test_authoring_gates.py` still pass.
(`test_orphan_gate.py` has a pre-existing import failure unrelated to this change.)

## Validation (Task 4)

```
python3 scripts/wgsl_precommit_gate.py --files <all 36 files>
→ Files checked: 36 | Passed: 36 | Failed: 0  (naga OK on all, exit 0)
```

Full-repo sweep of the new check over all 1314 `public/shaders/*.wgsl`: **0 files flagged**
— no other ungated reserved-index writes exist outside the fixed list (already-gated files
like `echo-trace`, `gen-feedback-echo-chamber`, `gen-percolation-threshold` pass cleanly).

## Notes / out of scope (per instructions, reserved [0..4] only)

- Lane C 7b/7c items (echo-trace stomping [0..7] while gated, gen-percolation-threshold
  [0..119] scratch, agent-state sims from slot 0, pixel-sand/physarum scatter races) were
  **not** touched — gated or ≥5-index, outside the reserved-write-only scope cap.
- Several fixed files also write slots ≥5 ungated (e.g. gen-sierpinski-tetrahedron [5],
  gen-cybernetic-mycelium-neural-web [5..6]) — per-pixel scratch / FFT-bin region, left as-is.
