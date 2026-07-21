# bitonic-sort — Optimizer Upgrade Notes (2026-07-21)

**Gate:** `wgsl_precommit_gate.py` → PASS (exit 0, naga OK, bindgroup compatible), 0 warnings.
**JSON:** `shader_definitions/simulation/bitonic-sort.json` parses OK; `updatedParams` (index 0–3) + `"updated": true` added per brief.
**Line count:** 241 → 304 (**+63**, within the +50…+90 expansion window; brief target 291–331 ✓).

## Changes by domain

### Slider params (re-scoped per brief, exactly 4 via `u.zoom_params`)
- `x` → **Sort Threshold** (default 0.5): pixel-sorter style participation gate on luma.
- `y` → **Warp Amplitude** (default 0.3): pre-sort domain-warp strength; `0` dials warp exactly to zero (`mix(kUV, warp, 0)`).
- `z` → **Edge Glow** (default 0.4): intensity of the sorted-span boundary highlight.
- `w` → **Sort Length** (default 0.5): fraction of each workgroup's sorted run that contributes.
- Old param usages (NoiseMix, SortDir, NoiseOctaves) replaced with named constants (`NOISE_MIX=0.3`, `FIXED_OCTAVES=4`, `FEEDBACK_DECAY=0.955`, `SORT_MIX_BASE=0.9`); hardcoded kaleidoscope/scale/mouse-radius constants that previously piggybacked on `zoom_params.w` are now fixed (kSegs=6, scale=7, radius=0.2).

### Audio reactivity (bass via `plasmaBuffer[0].x`)
- Bass smoothly **lowers** the sort threshold: `thresh = sortThresh * (1 - bass*0.45)` (clamped ≥0.02) — beats pull more pixels into the sorted run.
- Bass **modulates sorted-span length**: `span = sortLen * (1 + bass*0.40) + 0.05`.
- Existing bassMod / CA / feedback-reactivity untouched.

### Edge glow (new, restrained)
- Post-sort shared-memory boundary detection: compares `sKey[pi]` vs next slot's key; flags sorted↔sentinel transitions plus sharp key jumps (`smoothstep(0.06, 0.30, Δkey)`), masked by the ripple mask.
- New `edgeGlowColor()` helper: warm-amber→cool-cyan ramp keyed by the normalized sort key; additive glow scaled by `edgeGlow * (0.35 + bass*0.30)`, result clamped to [0,1].

### Algorithm / structure preservation
- **Bitonic network (PASS 2) 100% untouched** — padded 17-stride shared memory, stage order, branchless single-sided compare-and-swap, barrier placement all identical.
- Canonical 13-binding layout unchanged; `@workgroup_size(16,16,1)` kept; `textureSampleLevel(...,0.0)` for sampler reads; writes `writeTexture` + `writeDepthTexture` + `dataTextureA` every frame.
- Sort direction feature preserved without a slider: ascending by default, **mouse-press (`zoom_config.w`) flips to descending**; sentinel key (±sentinel) selected per direction so out-of-bounds/non-participating pixels still park at the run tail.
- Threshold non-participants get the sentinel key — they drift to the unsorted tail, which is exactly what the edge-glow boundary detection highlights.

## QA flags
- **Eyeballed constants** (no GPU here): bass→threshold factor 0.45, bass→span factor 0.40, warp strength 0.35 (+bass 0.15), key-jump smoothstep 0.06–0.30, glow pulse 0.35+0.30·bass, span smoothstep width ±0.06. All chosen conservative/restrained; may want visual tuning on real hardware.
- **No-GPU caveat:** validated only via naga/gate + JSON parse in the headless VM; visual behavior (glow restraint, threshold gating feel, mouse-flip direction) not eyeballed on a live canvas.
- **Slider semantics re-scoped:** the 4 sliders no longer mean SortMix/NoiseMix/SortDir/NoiseOctaves — this is intentional per the brief's `updatedParams`; legacy `params` array kept in JSON for UI compatibility. Users with saved presets will see new behavior on old values.
- Mouse-press now toggles sort direction (repurposed feature); documented in shader comment.
