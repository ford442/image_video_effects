# Mid twelve — notes (2026-10-11)

Cards: `BRIEFS.md`, written before the WGSL edits. None of these ids were in the October 10 batches or the crackle-palm batch.

Every file was migrated from a pasted binding header to `#include "_prelude.wgsl"` first (header-only, not counted). Saved `params` stay byte-identical. Each definition's `description` gained one sentence.

| Shader | Kept | New ideas | A packing |
|---|---|---|---|
| gen-acid-lissajous | beads, waist, cusp dwell, 2:1 lobe | pen head; beat envelope | ACES display RGBA |
| gen-apollonian-gasket | seed rims, curvature tint, stipple, kisses | interior wash; soddy spark | linear RGB + alpha, ACES on display |
| gen-barnsley-fern | IFS, affine tint, stem rib, pinna, crozier | rachis scales; sori | ACES display RGBA |
| gen-bifurcation-diagram | logistic map, Lyapunov ridges, ghost, cobweb | period-3 window; superstable points | HDR density RGB + alpha |
| gen-bio-luminescent-jelly | bell, jet tentacles, canals, gonad, snow | oral arms; bell muscle striations | raw pulsePhase in A.r |
| gen-coral-reef-colony | forks, skeleton in A.a, bleaching, mouths | apical pallor; zooxanthellae speckles | A.rgb history, A.a skeleton |
| gen-cycloid-bloom | hypotrochoid, vein, stamen, epicycloid, crossings | cusp sparks; rolling circle | ACES display RGBA |
| gen-fibonacci-spiral-garden | golden disks, 8- and 13-ridges | floret age; involucre bracts | raw HDR in A, ACES on writeTexture |
| gen-fireworks-chrysanthemum | pistil heart, latitude foreshorten | petal barbs; color break | ACES display RGBA |
| gen-fireworks-comet-trail | ion tail, dust trail, coma | disconnection kink; nucleus jets | ACES display RGBA |
| gen-crystal-caverns | habits, pinacoid, phantom shell | prism striations; fluid inclusions | ACES display RGBA |
| gen-aperiodic-monotile | reflected hats, brim, kite notch, metatile | hat crown; substitution tint | ACES display RGBA |

No new spring. Existing pointer, held, and click behavior left in place.

Gates: Naga 12/12, extraBuffer 0 new, dead sliders 0 new, catalog drift 0. Jest: 152 suites passed. `RendererManager.test.ts` fails to parse the TypeScript `private` keyword under the installed Babel; that file was not part of this batch. Real-GPU visual QA: external.
