# Notes — Optical / Glass / Holographic "Remaining Ten" (2026-09-13)

## Skipped — already idea-rich, untouched

| ID | Prior batch | Dated header |
|---|---|---|
| `gen-ethereal-glass-flora-terrarium` | Ethereal generative ten | Upgraded: 2026-09-11 |
| `gen-ethereal-quantum-hologram-bonsai` | Ethereal generative ten | Upgraded: 2026-09-11 |
| `gen-ethereal-quantum-holographic-fractal-coral` | Ethereal generative ten | Upgraded: 2026-09-11 |
| `gen-ethereal-quantum-medusa` | Ethereal generative ten | Upgraded: 2026-09-11 |
| `gen-holographic-plasma-geode` | (photo/optical batch) | Upgraded: 2026-09-06 |
| `gen-holographic-rainbow-surface` | (photo/optical batch) | Upgraded: 2026-09-06 |
| `gen-holographic-lens-flare-matrix` | (photo/optical batch) | Upgraded: 2026-09-06 |

No bytes changed in these 7. No `Upgraded:` date bump.

## Metadata pass — header/JSON only, no algorithm change

| ID | Kept verbatim | What was documented (already in code) | A packing | Upgraded: |
|---|---|---|---|---|
| `gen-glass-mosaic-liquid-refraction` | all 4 params, Voronoi/Worley/curl-noise kernel, Fresnel/Beer-Lambert optics | FBM domain-warped Voronoi mosaic + Worley grain; IOR Fresnel-Schlick + Beer-Lambert absorption; curl-noise liquid heightfield → refraction + caustics | ACES display RGBA | left at 2026-06-28 (not bumped) |
| `gen-holographic-fracture` | all 4 params, extraBuffer[133..137] spring-eased mouse-crack origin, SDF crack network, ripple crack fronts | spring-eased mouse crack origin; click-triggered expanding crack fronts w/ trailing spokes; per-crack iridescence phase from FFT bins 1-8 | ACES display RGBA, hue-preserving clamp | none added (had none before; metadata pass) |
| `gen-holographic-membrane` | all 4 params, raw [height, normal.xy, alpha] A/C packing | two-layer thin-film interference + mouse view-angle bulge; click impulses perturbing height/normal; audio-driven vibration/iridescence/trough transparency | raw sim state (unchanged) | none added (had none before; metadata pass) |

## What changed, file by file

- `public/shaders/gen-glass-mosaic-liquid-refraction.wgsl`: header banner rewritten
  (fixed stale `Category: artistic` comment → `generative`, matching its actual
  `shader_definitions/generative/` location per [[project_category_field_cleanup]]),
  added `Ideas:`/`A packing:` lines, `upgraded-rgba` added to `Features:`.
  No code below the header touched.
- `public/shaders/gen-holographic-fracture.wgsl`: header banner rewritten to the
  standard form with `Ideas:`/`A packing:`, `upgraded-rgba` added to `Features:`;
  kept the useful "engine uniform convention" note verbatim below the banner.
  No code below the header touched.
- `public/shaders/gen-holographic-membrane.wgsl`: header banner extended with
  `Ideas:`/`A packing:` lines (kept the original `Description:` block verbatim),
  `click-reactive` added to `Features:` (the ripple-impulse loop already reads
  `u.ripples[]`, this was just an undeclared tag). No code below the header touched.
- `shader_definitions/generative/{gen-glass-mosaic-liquid-refraction,
  gen-holographic-fracture,gen-holographic-membrane}.json`: appended
  `"upgraded-rgba"` to `features`. No `params`/`updatedParams` touched.

## Gates run

- `naga` 3/3 (the 3 touched files) — Validation successful.
- `python3 scripts/wgsl_precommit_gate.py --files <3 files>` — 3/3 passed,
  naga OK, bindgroup compatible, 0 extraBuffer violations.
- `python3 scripts/audit_extrabuffer.py` — 0 new violations (repo-wide).
- `python3 scripts/audit_dead_sliders.py --files <3 ids>` — 0 dead sliders.
- `node scripts/generate_shader_lists.js` — clean, no new multipass/alias issues.
- `node scripts/check_duplicates.js` — 1,378 definitions, 1,378 unique IDs, no dupes.
- Full `SKIP_WASM_BUILD=1 npm run build` / `react-scripts test` **not run**: the
  working tree already has an unrelated in-flight CSS-split/search-index task
  mid-edit (uncommitted); this batch's changes are header-comment + JSON-tag only
  on 3 files, so the shader-specific gates above are the relevant proof.
- Real-GPU visual QA: external, not available on this VM (no changes to visuals
  regardless — none of the 10 files had their rendered output touched).
