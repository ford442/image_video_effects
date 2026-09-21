# Batch closeout — interactive-mouse eight (2026-09-21)

IDs: `mouse-magnetic-pixel-sand`, `magnetic-rgb`, `mouse-julia-morph`, `cross-stitch`,
`foil-impression`, `interactive-voronoi-web`, `mouse-polarized-light-field`, `poly-art`.

Per shader — ideas actually added, what was kept verbatim, A packing:

- **mouse-magnetic-pixel-sand**: field-line chaining (multi-tap along `fieldDir`); bass-driven
  field pulse (`magnetStrength`/`magneticRange` scale with `plasmaBuffer[0].x`); settling
  residue via `dataTextureC`/`dataTextureA` (new raw-sim feedback: `.a` = decaying residue,
  `.rgb` = last filing color). Kept verbatim: magnet/ripple param roles, displaced-sample
  "moved filing" look, sheen/align-boost. No spring added — the file already had its own
  mouse-magnet field and ripple loop.
- **magnetic-rgb**: named the pre-existing iron-filing field-line filaments in the header;
  added bass-driven field surge (`displace` scales with bass) and semantic alpha from
  R/G/B channel-UV divergence (replaced hardcoded `1.0`). Kept verbatim: per-channel
  attract/swirl/repel physics, param roles. A: display RGBA passthrough (no prior history).
- **mouse-julia-morph**: orbit-trap filament glow (new `juliaOrbitTrap`, additive to the
  existing `julia` iteration, used only on the base view) and bass-driven zoom breathing.
  Kept verbatim: `currentC`/`autoC` blend, ripple-pinned Julia blending, image-as-palette
  sampling, alpha = escape iteration. A: display RGBA passthrough.
- **cross-stitch**: half-stitch/full-stitch shading (luma-gated `d1` vs `min(d1,d2)`, the
  real embroidery shading technique), satin thread sheen (highlight at `lineDist≈0`), and a
  subtle bass-driven weave-tension pulse on `thickness`. Kept verbatim: grid/X-pattern math,
  thread_alpha derivation chain, depth encoding. A: display RGBA passthrough.
- **foil-impression**: anisotropic brushed-metal streaks (brush direction blends toward the
  image-relief tangent as `press_factor` rises) and crinkle micro-fold shimmer gated at the
  press boundary (`4*p*(1-p)` band). Kept verbatim: foil/image normal blend, spec/brushed/
  spectral terms, existing audio use. A: display RGBA passthrough.
- **interactive-voronoi-web**: named the pre-existing living-neural-web mechanism (racing
  pulses, firing synapse nodes) in the header; added a bass-synchronized firing burst layered
  on top of the independent per-cell firing. Kept verbatim: web/edge geometry, param roles.
  A: display RGBA passthrough (added `clamp` before store/A-write since burst can push > 1).
- **mouse-polarized-light-field**: chromatic fringe dispersion (per-channel fringe *density*,
  not just hue, producing real rainbow-edged fringes) and treble-driven fringe shimmer (file
  had zero `plasmaBuffer` use before). Kept verbatim: Malus's-law filtering, ripple vortices,
  mouseDown flash, alpha = phase. Removed the now-redundant single-channel `fringe`/
  `fringeIntensity` locals (superseded by the dispersed per-channel version). A: display
  RGBA passthrough.
- **poly-art**: finished the facet edges the file had abandoned as dead code (perpendicular-
  bisector 2nd-closest-point border distance, so `edgeWidth` now draws real polygon borders)
  and added per-facet flat-shading (hashed per-cell pseudo-normal, fixed light direction,
  with a subtle bass pulse). Bug fix: the file had **no bounds guard** at all — added the
  mandatory `if (global_id.x >= ... ) { return; }`. Kept verbatim: cellSize/edgeWidth/
  randomness/influence param roles, fisheye distortion, per-cell flat sampling. A: display
  RGBA passthrough.

## Floor

- Canonical 13 bindings unchanged in all 8 files; `@workgroup_size(16, 16, 1)` unchanged.
- Saved `params` byte-exact in all `shader_definitions/interactive-mouse/*.json` — only
  `features` arrays were appended to (additive, `audio-reactive` / `upgraded-rgba` only
  where the WGSL now actually does that).
- A packing: all 8 write `dataTextureA` (none previously did); 7 are a straightforward
  display-RGBA passthrough (nothing reads `dataTextureC` as history in those files, so this
  just makes the channel live for a future consumer); `mouse-magnetic-pixel-sand` is the one
  exception — it introduces genuine raw-sim feedback (residue) and reads `dataTextureC`.

## Gates

- `node scripts/verify-naga-wasm.mjs --files <8 files>` — 8 valid, 0 invalid.
- `python3 scripts/wgsl_precommit_gate.py --files <8 files> --skip-naga` — 8/8 pass
  (bindgroup + workgroup; naga owned by the wasm validator above, no CLI `naga` binary
  available in this VM).
- `npm run audit:extrabuffer` — 0 new violations (1415 files scanned).
- `python3 scripts/audit_dead_sliders.py --files <8 ids>` — 0 new dead sliders.
- `node scripts/generate_shader_lists.js` — regenerated cleanly; only the touched
  `interactive-mouse.json` shader-list features changed.
- `node scripts/check_duplicates.js` — 1384 definitions, 1384 unique IDs.
- `python3 scripts/audit_catalog_consistency.py` — 105 violations, unchanged from the
  pre-batch baseline (confirmed by diffing against the pre-edit tree) — none introduced by
  this batch.
- **Not run**: `npx react-scripts test` / `SKIP_WASM_BUILD=1 npm run build`. This VM has no
  `node_modules` installed (fresh checkout, no GPU), so the JS toolchain isn't available —
  only the Python/naga-wasm structural gates above could run. Flagging this explicitly
  rather than claiming a green build/Jest run that never executed.

## Real-GPU visual QA

External — not performed from this VM (no GPU). Do not treat the structural gates above as
a substitute for looking at the eight effects.
