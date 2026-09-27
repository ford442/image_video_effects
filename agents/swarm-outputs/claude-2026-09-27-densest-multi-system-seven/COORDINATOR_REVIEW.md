# Coordinator review — Densest Multi-System Seven (2026-09-27)

Checklist per docs/SHADER_UPGRADE_BATCH.md §9. All seven PASS on structure; visual QA is external (no GPU).

| Shader | Card first | Ideas pointable | Keep verbatim | Not boilerplate | No shared overlay | A packing | Saved params | Springs/ripples | Gates |
|---|---|---|---|---|---|---|---|---|---|
| obsidian-scarab-engine | ✓ | IDEA 1–3 tagged | ✓ | +68/-2, ideas | ✓ | ACES display | ✓ | none added | ✓ |
| plasma-dragon-eye | ✓ | Idea 1–4 tagged | ✓ (side views change: bug fix) | +149/-26 | ✓ (refused collarette/crypts, breath jet) | ACES display | ✓ (Pupil Sharpness revived, default-equal) | none added | ✓ |
| ferro-silicate-swarm | ✓ | Idea 1–4 tagged | ✓ helpers/grid/curl/SDF pull | +130/-37 | ✓ no spikes/field lines | ACES display, alpha occupancy | ✓ | none added | ✓ |
| sonoluminescent-geode | ✓ | [Idea 1–3] tagged | ✓ | +54/-31 | ✓ | raw HDR (unchanged) | ✓ | none added | ✓ |
| spectral-ferrofluid | ✓ | Idea 1–3 tagged | ✓ | +77/-2 | ✓ avoided Rosensweig lattice / psi filaments | raw fields (unchanged) | ✓ | existing ripples kept (bounds fix) | ✓ |
| superfluid-quantum-foam | ✓ | Idea 1–3 tagged | ✓ lattice/boil/vortex | +136/-25 | ✓ avoided foam-alpha membranes/pairs | ACES premult (unchanged) | ✓ | inert HEAD spring left | ✓ |
| bismuth-dragon-core | ✓ | IDEA 1–3 tagged | ✓ fold/sinew/palette | +110/-16 (floor + ideas) | ✓ no hopper/oxide | ACES display | ✓ `parameters` unchanged | none | ✓ |

Default-look shifts to flag for GPU QA (all from bug fixes, not reimagining):
- ferro-silicate-swarm: ~4× brighter (A was never written; C=0 dimmed to 25%).
- superfluid-quantum-foam: bubbles now whole/smooth (curlNoise hash warp + floor/round split fixed).
- bismuth-dragon-core: labyrinth visible for the first time (camera was inside the sinew; HEAD was a flat gold wash).
- plasma-dragon-eye: no more screen-crossing bar on side views.

Coordinator verified by diff read: ferro-silicate (full), dragon-eye (idea tags/header), JSON diffs for all seven.
