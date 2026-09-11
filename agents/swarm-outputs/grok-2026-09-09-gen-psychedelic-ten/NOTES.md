# Generative fast-motion / psychedelic ten — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `gen-plasma-psychedelic-wormhole` | brightness / speed / scale / color; 1/r depth; plasma fBm; blackbody; spiral arms; stars | `contra` octave sign; `doppler` on 1/r hue | HDR trail RGB in A. Exact C. Mouse UV 0–1 |
| `gen-neon-acid-geometry` | intensity / speed / scale / color; triangle/hex/circle; `phToColor`; Snell | `geoFill` rim-only pH; `smin` sibling `siblingOff` | HDR A. Exact C. Mouse UV 0–1 |
| `gen-chromatic-acid-drip` | intensity / flow / blob / color; metaball; `chromaticDrip`; mouse splash | `meniscus1..3`; `gravity` on blob Y | HDR A. Exact C. Mouse UV 0–1 |
| `gen-polar-rainbow-explosion` | intensity / speed / scale / color; 36 rays; `shockR`; bursts | `ahead`/`behind` Mach split; `rayWidthR`/`rayWidthB` | HDR A then ACES write. Mouse UV 0–1 |
| `gen-neon-cyber-mandala` | glow / rotation / zoom / color; PHI; GOLDEN_ANGLE; patternedRing; stars | `ringInner *= PHI`; `contra` inner/outer spin | HDR A. Exact C. Mouse UV 0–1 |
| `gen-plasma-mandala` | symmetry / spin / zoom / glow; angular fold; plasma+fbm; mouse pull | `seam` on fold; `plasma(..., t - r * 1.15)` | ACES display RGBA. Single ACES. HEAD never reads C |
| `gen-neon-lotus` | petal count / bloom / speed / glow; `petalSdf`; 3 layers; stamens | `vein` on `localTheta`; `GOLDEN_ANGLE` layer offset | ACES display RGBA |
| `gen-electric-kaleidoscope-storm` | intensity / flicker / symmetry / color; `branchingBolt`; click shocks | `lich` C mix along `boltEnergy`; `strokeScale` leader/return | HDR trail A. Existing ripples kept. No new extraBuffer |
| `gen-rainbow-icosahedron-cascade` | shell count / spacing / glow / hue; icosa verts/edges; mouse orbit | `sil` silhouette; `rotY(p, sf * GOLDEN_ANGLE)` | Display RGBA in A (HEAD telemetry lie fixed) |
| `gen-neon-stellated-octahedron` | star / spin / neon / color; dual tetra; 6-fold XY | `ridge` = max(e0,e1); facet `* (1.0 - edge)` | Display RGBA in A (HEAD telemetry lie fixed) |

Skipped Batch 54–60 kaleido overlays, today’s psychedelic-motion ten, classic gen ten, Batch 71 DMT/cymatic, relay psychedelia, holographic leftovers.

Floor: additive named `params[]` on eight `updatedParams`-only defs (defaults exact). No new springs. extraBuffer unused on this ten.
