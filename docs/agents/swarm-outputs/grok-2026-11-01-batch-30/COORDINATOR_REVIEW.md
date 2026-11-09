# Coordinator review — cursor/batch-30 (2026-11-01)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea has a `// ── Idea n:` comment in that shader. Earlier ideas stay. Saved params were not renamed or re-defaulted.

| Shader | Verdict | Why |
|---|---|---|
| crumpled-paper | pass | Cockle is added only off the ridge and is in the height the iron flattens. Sheen broadens the existing specular inside the smooth disk and presses the fibre flat. |
| paper-burn | pass | Scorch is a band ahead of the ember. Curl offsets the photo sample by the burn gradient the diffusion already loads. A.r is still the burn and is not tone-mapped. |
| plastic-bricks | pass | Pip is a recess on the stud. Parting line is a vertical flash on the shell, skipped on the stud. Tubes and the knit line are untouched. |
| pin-art-3d | pass | Height, including the neighbour comparison, locks to seven steps. The cap equator darkens. The shaft and the push stay. |
| bubble-wrap | pass | Seal is the ring outside the dome. Flash is the first moments of a pop, then the existing collapse. A.rg is still the pop flag and time. |
| interactive-origami | pass | Score is a hairline at h0 = 0. Negative fold parity dulls the sheet and keeps most of the foil on the front. |
| kintsugi-repair | pass | Urushi is a dark shoulder wider than the gold. The glaze lip is a light chip and a short shadow outside that. The F2 junction and the meniscus stay. |
| venetian-blinds | pass | Openness shifts the photo seen through the gap, two ladder tapes cross the slats, and the lower gap picks up slat colour. Slat count, phase, bass, and the downward shadow stay. ACES is new because the file claimed it and did not have it. |
| kinetic-tiles | pass | The lit lip faces the spin the tile already has. The gap is mortar instead of a flat dim photo. The spring, domino delay, and grout compression stay. |
| interactive-emboss | pass | Crests desaturate toward plate gray. A one-texel downhill tap cuts a groove. Self-shadow and the Blinn glint stay. |
| texture | pass | Both §12.2A rows use the 3×3 taps the Laplacian already fetches. Edge Strength and Unsharp Amount are still the gains. C is an exact load. Vignette and voronoi glitch stay. |
| zipper-reveal | pass | A dashed thread sits just outside the teeth and hides under the puller. The opened slot darkens at each lip. Teeth and the slider stay. |

§9 checklist: cards exist and predate the diff; each idea is pointable; keep-verbatim holds; the diff is the material term, not a header/ACES/spring stamp (venetian is the one file that gained ACES, under three ideas); no formula is shared except the two rows that live only on `texture`; packing matches how C is read; springs only on kinetic-tiles, where HEAD already had one; Naga, extraBuffer, and dead sliders passed on these files.

Real-GPU visual QA is external. This review does not claim the ideas look right on a display.
