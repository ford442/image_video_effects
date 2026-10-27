# Coordinator review — `cursor/batch-13` (2026-10-27)

Cards were written before the WGSL edits (`BRIEFS.md`). Each numbered idea has a `// ── Idea` comment. Saved `params` were not renamed or re-defaulted. Eight pasted headers were migrated first and that swap did not bump `Upgraded:` by itself; the date moved when the ideas landed.

## Formula use (no row on more than one file)

| Shader | §12.2 row |
|---|---|
| quantized-ripples | deep-water dispersion (D) |
| sonic-boom, elastic-strip, elastic-surface, luma-force, pixel-repel, neon-ripple-split, mouse-gravity, magnetic-edge, magnetic-rgb, slinky-distort, mouse-magnetic-pixel-sand | none |

The two elastic files do not share an idea. The strip keeps its oscillator, bevel, and soap film, and gains string partials plus stretch bleach. The membrane keeps Verlet, the 4-neighbour Laplacian, and Poisson, and gains plate bending plus compression wrinkles.

The two magnetic files do not share an idea. `magnetic-rgb` filings follow a dipole return while the RGB offsets stay monopole. `mouse-magnetic-pixel-sand` keeps the radial pull and adds friction plus dashed links. `magnetic-edge` bends the existing edge field along spring velocity and holds remanence from C.a.

## Checklist

| Shader | Ideas pointable | Keep verbatim | Packing matches C | Springs only if native | Naga |
|---|---|---|---|---|---|
| sonic-boom | yes | yes | ACES display; C.r ring tail | existing shock spring | pass |
| elastic-strip | yes | yes | ACES display trail | no | pass |
| elastic-surface | yes | yes | raw disp / vel | no | pass |
| luma-force | yes | yes | raw mem / drive / contrast | no | pass |
| pixel-repel | yes | yes | display plus two pointer texels | no | pass |
| neon-ripple-split | yes | yes | linear colour; `(0,0)` bass env | no | pass |
| mouse-gravity | yes | yes | display plus two pointer texels | no | pass |
| magnetic-edge | yes | yes | ACES display history | existing edge spring | pass |
| magnetic-rgb | yes | yes | ACES display, C unread | no | pass |
| slinky-distort | yes | yes | linear echo in A | no | pass |
| mouse-magnetic-pixel-sand | yes | yes | raw residue | no | pass |
| quantized-ripples | yes | yes | raw haptic field, C unread | no | pass |

Pass 12/12 against the cards. Real-GPU visual QA is external.
