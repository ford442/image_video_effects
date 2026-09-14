# Coordinator Review — Optical / Glass / Holographic "Remaining Ten" (2026-09-13)

Verdict: **7 skip (already upgraded) / 3 metadata-pass (no new ideas) / 0 new
creative upgrades.** This batch is not a 10-shader Idea Card upgrade — the
supplied list was stale. See BRIEFS.md for the audit and NOTES.md for the diff.

## Per-file checklist

| ID | Idea Card before diff | Ideas pointable in WGSL | KEEP VERBATIM held | Diff ≥70% boilerplate? | No generic overlay | A packing matches C read | Saved params unchanged | Springs/ripples native-only | Naga/extraBuffer/dead-sliders |
|---|---|---|---|---|---|---|---|---|---|
| `gen-ethereal-glass-flora-terrarium` | n/a — untouched | n/a | yes | n/a | n/a | yes | yes | yes | not re-run (untouched) |
| `gen-ethereal-quantum-hologram-bonsai` | n/a — untouched | n/a | yes | n/a | n/a | yes | yes | yes | not re-run (untouched) |
| `gen-ethereal-quantum-holographic-fractal-coral` | n/a — untouched | n/a | yes | n/a | n/a | yes | yes | yes | not re-run (untouched) |
| `gen-ethereal-quantum-medusa` | n/a — untouched | n/a | yes | n/a | n/a | yes | yes | yes | not re-run (untouched) |
| `gen-holographic-plasma-geode` | n/a — untouched | n/a | yes | n/a | n/a | yes | yes | yes | not re-run (untouched) |
| `gen-holographic-rainbow-surface` | n/a — untouched | n/a | yes | n/a | n/a | yes | yes | yes | not re-run (untouched) |
| `gen-holographic-lens-flare-matrix` | n/a — untouched | n/a | yes | n/a | n/a | yes | yes | yes | not re-run (untouched) |
| `gen-glass-mosaic-liquid-refraction` | written, documents pre-existing work | yes (Voronoi/Worley/Fresnel/Beer-Lambert/curl-noise all present pre-edit) | yes | **yes — 100% header-only** (flagged, see below) | n/a (no new overlay added) | yes | yes | n/a (no pointer spring in this file) | PASS |
| `gen-holographic-fracture` | written, documents pre-existing work | yes (spring-crack, click-fronts, FFT-bin iridescence all present pre-edit) | yes | **yes — 100% header-only** (flagged, see below) | n/a | yes | yes | native, unchanged | PASS |
| `gen-holographic-membrane` | written, documents pre-existing work | yes (thin-film, click impulses, audio vibration all present pre-edit) | yes | **yes — 100% header-only** (flagged, see below) | n/a | yes | yes | n/a (no extraBuffer spring in this file) | PASS |

## On the "≥70% header/boilerplate" flag

`docs/SHADER_UPGRADE_BATCH.md` §9 fails a file whose diff is ≥70% header
boilerplate **when it's presented as an upgrade**. These 3 are explicitly
**not** presented as upgrades — BRIEFS.md and NOTES.md label them a metadata
pass, `Upgraded:` was not date-stamped (or left at its original date), and
`docs/SHADER_UPGRADE_BATCH.md` §5.3 lists exactly this case ("Header / tag /
`updatedParams` missing, picture already good") as an **allowed** pass, so
long as it isn't miscounted as upgrade throughput. Passing this review on that
basis; flagging here so a future coordinator doesn't double-count these 3
toward "shaders upgraded today."

## Recommendation

The requested 10-ID list is exhausted (7 already done, 3 now correctly
tagged/documented). If more optical/glass/holographic throughput is wanted,
a genuinely fresh batch exists — a discovery pass over `*.wgsl` filenames
matching glass/holographic/hologram/crystal/iridescence/prism/quantum/lens/
refract keywords found ~235 files with no `Ideas:` header, most well under
200 lines (e.g. `liquid-lens`, `quantum-prism`, `molten-glass`,
`hybrid-voronoi-glass`, `holographic-glitch`, `crystal-facets`,
`glass-brick-distortion`, `gen-kaleidoscopic-synapse-bloom`), after excluding
files already in this batch and multipass secondaries. Not started here —
scope was the 10 supplied IDs.
