# BRIEFS — fork B (gen-cybernetic-crystalline-neuro-lattice, gen-hyperbolic-crystal-symbiosis)

Written BEFORE any WGSL edit. HEAD = origin/main 0761b6b9. Harness: `agents/mr.mjs` at SAVED defaults (neuro-lattice `0.5,0.3,0.2,0`, hyperbolic `0.4,0.5,0.5,0.3`), SwiftShader, `SRC=img`.

## HEAD render table (read the PNGs; scratch `…/scratchpad/forkB/`)

| file | case | size | meanL | stdL | meanA | nan | frameMs |
|---|---|---|---|---|---|---|---|
| neuro-lattice | idle | 192 | 0.446 | 0.173 | 0.583 | 0 | 160 |
| neuro-lattice | held (0.4,0.6,down) | 192 | 0.430 | 0.185 | 0.569 | 0 | 331 |
| neuro-lattice | audio 0.8/0.5/0.9 | 192 | 0.421 | 0.162 | 0.566 | 0 | 343 |
| neuro-lattice | idle | 576 | 0.449 | 0.171 | 0.584 | 0 | 2545 |
| hyperbolic | idle | 192 | 0.468 | 0.156 | 0.401 | 0 | 41 |
| hyperbolic | held | 192 | 0.470 | 0.154 | 0.400 | 0 | 55 |
| hyperbolic | audio | 192 | 0.507 | 0.231 | 0.335 | 0 | 68 |
| hyperbolic | idle | 576 | 0.461 | 0.165 | 0.401 | 0 | 623 |

What the pictures show:
- **neuro-lattice**: not dead. Camera sits inside the repeated lattice; cyan crystal nodes, a teal gyroid sheet washed cyan by the light-pipe term, almost no magenta in the default view. A few grazing-angle step-banded patches (march runs out of its 100 × 0.5-factor steps and accepts `d < 0.01` as a hit) — noted, not a rescue (fixing it needs a marcher change that belongs to the over-relaxed-tracing row, which the coordinator gave to bismuth).
- **hyperbolic**: not dead. Coloured wedges (tiling cell id = p-fold sector) with 7 rounded Voronoi blobs, white spokes at facet borders, concentric zoning rings near the rim, heavy temporal smear (history sampled 2–4 px away each frame, 68 % weight on history → everything ≥ ~10 px soft). Idle has no treble/mids glows (audio-gated) — expected.

## Suspected defects read from the code (verify → rescue)

**neuro-lattice** — R-N1 (documentation only): header `Ideas:` lists 2 of the 5 ideas the file contains (nucleation front, memory-crystal bit states and light-piped links are in the code as `// Idea 1-3` but not in the header). I add the three names; no behaviour change. Everything else I checked is already fixed at HEAD (audio = `plasmaBuffer[0].xyz`; ripple uses `.z` only; `uv01` and the ripple centre both y-down; ACES only on `writeTexture`, `dataTextureA` = pre-ACES HDR and C read back as HDR; alpha semantic; depth written; `pow` bases are `max(…,0)`).

**hyperbolic** — R-H1 (infra): pasted 13-binding header + `struct Uniforms` → `migrate_to_prelude.py` first (no `Upgraded:` bump for it). R-H2 (confirm by injected ripple): the click ring is centred at `(ripple.xy − 0.5)·2.2` in **disk** space but `diskUV` has since been scaled by `curv` (0.3–1.0, ≈0.65 at defaults) and Möbius-translated by the cursor focus, so the ring is centred at `0.5 + (click − 0.5)/curv` on screen, not on the click; at the same time its add is `0.45·e^{−1.4·age}·jewel` ≈ 0.1 by age 1 s (HEAD render with a click at (0.8,0.3), age 1 s: no ring visible). Fix = push the click centre through the same `·curv` + `hyperbolicTranslate(…, focus·0.8)` chain as the pixel. Strength left alone except what visibility measurement says.

## Idea Cards

```
SHADER: gen-cybernetic-crystalline-neuro-lattice
IDENTITY (one sentence): a raymarched camera-inside lattice of neon crystal nodes joined by a magenta gyroid network — nodes are somas, gyroid sheets are the links between them.
KEEP VERBATIM: latticeSpace (mouse bend, rotation by Growth Speed, centred repetition by Node Density), ifsCrystals + box node SDF, sdGyroid, smooth-min blend with near-clip bubble, the four params and their roles (Node Density / Growth Speed / Glitch / Neon Hue), nucleation front (Idea 1), cell bit states (Idea 2), light-piped links (Idea 3), braid (Idea 4), vesicle bursts (Idea 5), click ripples, mouse-down shockwave, HDR history in A/C, ACES only on writeTexture, semantic alpha, depth.
ADD (2 native ideas, numbered 6 and 7 to continue the file's own count):
  6. Action-potential wavefront with refractory undershoot — every node already fires a vesicle burst (Idea 5, period 2π/9 s, per-cell phase). Launch a conduction front from the node at that instant: it travels outward over the gyroid links at finite speed (distance field = the `d_crystal` the pipes already use), leading depolarisation spike (sharp, nearly white-cyan), then a dim hyperpolarised band behind it (the neuron's refractory undershoot), amplitude decrementing with distance. 0-bit nodes do not fire (their bit state gates it, as for pipes). Mids lift the amplitude. Native: a neuron-lattice link carries spikes launched by its soma — not a generic travelling ring (it is gated by node bit, node phase and link distance; wavefront speed is in world units, not screen).
  7. SDF curvature edge wear (§12.2E "SDF curvature") — Laplacian of the file's own `map()` from the six normal taps plus one centre tap at a wider stencil (e = 0.02): convex ridges of the crystal nodes catch a hard-light edge glint (frost-polished arrises), concave creases between node and sheet pick up a dark oxide tint. Native: crystal edges *are* the thing that physical crystals chip and polish.
FORBID on this file: springs / extraBuffer state (never persists), new ripple layers, IQ palettes, scanline/glitch costume, a second travelling ring system on screen space, any change to the saved params or to which material is crystal vs gyroid.
A PACKING: unchanged — HDR linear RGB (pre-ACES) + semantic alpha in A; C read back exactly as HDR history; ACES only on writeTexture.
FORMULAE: SDF curvature (§12.2E) on idea 7. Idea 6 is native (neuron physiology), no §12.2 row.
```

```
SHADER: gen-hyperbolic-crystal-symbiosis
IDENTITY (one sentence): competing jewel crystals grown as 7 hyperbolic Voronoi seeds on a Poincaré disk, with zoning bands, twin lamellae and a hyperboloid-lift sheen, drifting through a temporal history.
KEEP VERBATIM: hyperbolicTranslate / hyperbolicDist / hyperbolicTiling / crystalFacet (7 seeds, minD / secondD / border), jewelColor, growth zoning (Idea 1), twin lamellae (Idea 2), racing growth-front runners, facet border glow, tiling edge, growth-front rim, hyperboloid lift relief (Idea 3), the four params and their roles (Growth Speed / Competition / Curvature / Mutation), temporal history with the drifting offset, A = HDR display-history RGB + coverage alpha, ACES on writeTexture, depth.
ADD (2 native ideas, numbered 4 and 5 to continue the file's own count):
  4. Hourglass sector zoning — real crystals grow different composition in different crystallographic growth sectors, and the sectors meet in an hourglass. Promote the winning seed's frame `localZ` (already computed inside `crystalFacet`, then thrown away); its angle about the seed, measured from a per-seed axis, picks one of two tint families by the sign of cos(2θ), with a soft seam on the sector boundaries. Mutation sets the contrast (it is already the "growth mutation" slider), bass adds a little to the axis rotation. Visible as large tonal wedges inside every facet.
  5. Cleavage hypercycles — cleavage planes show as fine lines parallel to a crystal axis. In the Poincaré disk the lines at constant distance d⊥ from the diameter geodesic through the seed obey sinh d⊥ = 2·y′ / (1 − |z′|²) (z′ = localZ rotated by −axis); draw lines at equal steps of d⊥, so they converge toward the ideal boundary exactly like the file's zoning bands do, but straight and directional rather than concentric. Competition sets the density (it already drives lamella density); the line is dark with a bright shoulder (cleaved plane catching light), width chosen to survive the history smear.
FORBID on this file: springs, shockwave overlays, new geometry, IQ palettes, extra tiling, any change of the saved params, replacing the Voronoi facets.
A PACKING: unchanged — raw HDR display-history RGBA (pre-ACES rgb, coverage alpha); ACES on writeTexture only.
FORMULAE: none from the §12.2 table (the hypercycle identity is hyperbolic geometry itself); both ideas consume `localZ`, the seed-local coordinate the facet loop already produces.
RESCUES: R-H1 prelude migration (infra), R-H2 click ring centre uses the same curv + Möbius chain as the pixel (confirm with injected ripple first).
```

## §12.1 interrogation (tactics 1, 2, 3, 6)

**neuro-lattice.** T1 deepen kernel — the marcher is plain sphere tracing of a smooth-min of a folded box and a gyroid; the "next-better operator" for shading is not a new marcher but the curvature the six normal taps already imply (the Laplacian of the same SDF). T2 physics one step further — neurons: soma fires → spike propagates at finite speed along the link → depolarise, repolarise, then hyperpolarised undershoot (refractory period); crystals: arrises polish/chip while creases oxidise. T3 promote an intermediate — `d_crystal` (mapFull.z) is already evaluated for the pipes and is the natural conduction coordinate; the six `map()` evaluations in `calcNormal` already carry curvature. T6 history — C is read as HDR colour history at 6–13 %; there is no extra continuity to add without changing the packing, so neither idea uses it (stateless: wavefront position is closed-form from the per-cell phase, as the vesicle burst already is).

**hyperbolic.** T1 deepen kernel — the facet Voronoi is in hyperbolic distance (translate + atanh) with F1/F2; the next-better quantity of the *same* operator is the seed-local complex coordinate itself. T2 physics one step further — crystals: growth-sector (hourglass) zoning and cleavage planes; in hyperbolic space "parallel lines" are hypercycles. T3 promote an intermediate — `localZ = hyperbolicTranslate(z, seed)` of the winning seed: computed 7× per pixel, only its |.| kept. T6 history — C is colour history displaced by a rotating 2–4 px vector with 0.68 weight, which smears sub-10 px detail; therefore the new line idea must be wide enough (≥ ~0.1 in d⊥ steps) or it vanishes.

## Gate plan
Per file: precommit gate, `verify-naga-wasm --files`, `audit:dead-sliders -- --files <id>`, `audit:extrabuffer`. Visibility via `const IDEA_n: f32` switches on scratch copies (192 and 576, saved defaults). Timing: interleaved min-of-drained-frames, ≥ 4 rounds.
