# Coordinator review — `cursor/batch-12` (2026-10-26)

Cards were written before the WGSL edits (`BRIEFS.md`). Each numbered idea has a `// ── Idea` comment. Saved `params` were not renamed or re-defaulted. Eleven pasted headers were migrated first and that swap did not bump `Upgraded:` by itself; the date moved when the ideas landed.

## Formula use (no row on more than one file)

| Shader | §12.2 row |
|---|---|
| mouse-ink-bleed | paper granulation (C); dwell pressure (C) |
| velocity-field-paint | MacCormack advection (D) |
| liquid-touch | Boussinesq buoyancy (D), vertical only |
| mouse-paint-splatter | wet-edge accumulation (C), boundary form |
| cyber-ripples, echo-ripple, pixel-explode, sim-decay-system, gravity-well, interactive-pixel-wind, sim-heat-haze-field, black-hole | none |

`gravity-well` and `black-hole` do not share an idea. The well keeps its disk, halo, and Kepler streaks, and gains an ISCO lip plus chromatic deflection. The hole keeps its pinch, frame drag, and mirrored ring, and gains a photon-orbit caustic plus horizon reddening.

## Checklist

| Shader | Ideas pointable | Keep verbatim | Packing matches C | Springs only if native | Naga |
|---|---|---|---|---|---|
| mouse-ink-bleed | yes | yes | trail + wetness | no new spring | pass |
| cyber-ripples | yes | yes | display RGB + bass env | no | pass |
| velocity-field-paint | yes | yes | raw vel / omega / speed | no | pass |
| echo-ripple | yes | yes | display RGB + bass env | no | pass |
| pixel-explode | yes | yes | display RGBA, C unread | no | pass |
| sim-decay-system | yes | yes | raw decay fields | no | pass |
| liquid-touch | yes | yes | raw phi / vel / temp / merge; B kept | no | pass |
| gravity-well | yes | yes | lensing fields, C unread | no | pass |
| interactive-pixel-wind | yes | yes | display RGBA | no | pass |
| sim-heat-haze-field | yes | yes | raw temperature field | no | pass |
| black-hole | yes | yes | lens fields, C unread | no | pass |
| mouse-paint-splatter | yes | yes | paint + wetness; (0,0) stash | no | pass |

Pass 12/12 against the cards. Real-GPU visual QA is external.
