<<<<<<< HEAD
# COORDINATOR REVIEW — Sentient / Radiant Cosmic Entities Eight (2026-09-15)

Checklist per file: card written first (BRIEFS.md predates all WGSL edits) ✓.

| Shader | Ideas pointable in diff? | KEEP holds? | <70% boilerplate? | No shared overlay? | A packing honest? | Params exact? | Native pointer/audio? | Naga+audits? | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| moth | `g_vein_dist` / `veinMask`; storm `reversal` wake | yes (ellipsoid/antennae/FBM wings) | yes | yes | ACES display RGBA | yes (mirrored `params`) | plasmaBuffer; mouse orbit kept | 8/8 gate | PASS |
| bismuth | hopper terrace loop; `g_facet`/`g_hopper` film | yes (4 abs-folds, cuboid, source mix) | yes | yes | ACES after source mix | yes (`params` + aligned `updatedParams`) | plasmaBuffer (was C) | naga OK | PASS |
| owl | mat-3 `lane` currents; iris `sector` aperture | yes (capsule/lattice/glass/aurora) | yes | yes | ACES including source blend | yes | plasmaBuffer; mouse UV fixed | naga OK | PASS |
| leviathan-moth | `armorGroove`; wing `lamella` | yes (Voronoi wings, gyroid, dust) | yes | yes | ACES display RGBA | yes | plasmaBuffer map+main | naga OK | PASS |
| nautilus | septa at chamber phase; birefringent lobes | yes (log spiral, Fresnel interiors) | yes | yes | ACES display RGBA | yes | pointer axial kept | naga OK | PASS |
| stag | `tine_d` child per segment; trail `packet` | yes (leap SDF, antler chain, heart) | yes | yes | ACES display RGBA | yes | mouse UV fixed; plasmaBuffer | naga OK | PASS |
| forge | `hitMap.y` twin spectra; `g_seam` weld | yes (6-fold abs IFS + fog) | yes | yes | same ACES vec4 on A+output | yes | mouse UV gravity; no primary shim | naga OK | PASS |
| kraken | `suckA`/`suckB` underside; `peri` on `t_radius` | yes (8 capsules, noisy core) | yes | yes | ACES display RGBA | yes | plasmaBuffer; Twist/Glow/Heat unclamped | naga OK | PASS |

No file failed. ExtraBuffer 0. Dead sliders 0. Real-GPU QA external.
=======
# Coordinator review — Sentient / Radiant eight

- Cards written before WGSL (`BRIEFS.md`). Each numbered idea is present in the diff.
- Identity preserved: moths still moths, owl still owl, nautilus still spiral chambers, stag still stag, forge still KIFS, kraken still 8 tentacles + core.
- No generic spring/ripple/IQ overlay stamp.
- Forge helper deletion is floor (param theft), not an idea. Hopper terraces + recalescence are the upgrade.
- Kraken default Twist/Glow still match saved defaults; Core Heat default 1.5 now actually reads 1.5 instead of clamping to 1. That restores the JSON range rather than inventing a new slider.
- Cloud VM cannot exercise WebGPU; do not treat this review as visual QA.
>>>>>>> f6dd97e68a019af78b520bcf8959f4b8bc31c88e
