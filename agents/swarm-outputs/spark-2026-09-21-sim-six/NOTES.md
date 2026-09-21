# Stateful-simulation six — NOTES

Saved `params` / `updatedParams` are byte-identical everywhere. The only JSON change is `"upgraded-rgba"`
prepended to features on 3 files (sim-ink, sim-fluid, photonic-caustics), each of which has ACES and
now its ideas. `public/shader-lists/simulation.json` regenerated.

CPU harnesses (numpy ports of the update rules) are in this folder: `mt_*.py` (multi-turing),
`lenia*.py`, `ink.py`, `steam.py`.

## boids
- Kept: row-0 state packing, sep/ali/coh weights, speed limits, wander, splat, tone map, params.
- Idea 1 (blind spot): `behind` test in the neighbour loop. Neighbours whose direction is more than
  130° from the heading (dot < −0.643) are ignored.
- Idea 2 (predator): hover = HEAD attraction; held = flee (1.6) plus a sideways dodge (0.9) within 0.22,
  choosing the side away from the predator.
- Not CPU-simmed: both are bounded additive forces under HEAD's speed clamp.

## ion-stream
- Kept: lanes, packets, curl flow, magnetic UV bend, C wake, clicks, params. A = display RGBA.
- `fieldB = exp(-5d)·(1 + held)·0.5` is shared by both ideas.
- Idea 1 (charge split): `charge` alternates per lane; `deflect` stays below half a lane width, so a
  core never leaves its lane cell. Charge biases the existing blue↔violet mix.
- Idea 2 (cyclotron): helix frequency ×(1 + 4B), phase speed ×(1 + 2B), amplitude ÷(1 + 3B).

## sim-ink-diffusion-rgba
- Kept: the whole state rule verbatim (diffusion, mixing, brush, clicks, evaporation, grain).
  A = raw (pigment rgb, water a), unchanged.
- Idea 1 (edge darkening): `edgeDark` from the pigment-density gradient × (0.35 + 0.65·dryness).
- Idea 2 (granulation): `valley` = fibre hash at 1 and 3 texels plus photo tone; `granulate` scales
  with dryness.
- Floor: writeDepthTexture was never written; now a pass-through.

## steamy-glass
- Kept: steam relaxation, droplet growth, wipe/click clearing, blur/refraction, params. A packing
  unchanged (steam, droplets, runoff, wipe).
- Idea 1 (rivulets): sparse `site` hash (0.35% of texels), burst `release` above 0.28, bead transport
  `max(top.b·0.975, b·0.90)`, droplet pickup, and a `track` that clears steam. Display: the runoff
  gradient joins the refraction, plus a bead highlight. CPU results: onset about 10 s at default; tracks
  cover 1–4% at default and about 5% at max fog/fade; none at fog 0.4.
- Idea 2 (beaded rim): `wipeRim = 4·w·(1−w)` adds droplets in 3-texel beads along the wipe border.
- Note: HEAD's runoff line (`mix(b, top.b, 0.08) + droplets·0.0008`) was replaced by the bead transport.
  In HEAD it built a uniform ~0.04 haze that nothing displayed.

## sim-fluid-feedback-coupled
- Kept: the solver and the packing (vel.xy, pressure, density), confinement, stir, fronts, spectral().
- Idea 1 (buoyancy): `velocity.y += max(density − 1.2·ambient, 0)·0.0003`, before HEAD's clamp.
  Ambient = 0.002 / (1 − fade) is HEAD's own background-density equilibrium.
- Idea 2 (schlieren): `gradP` offsets the photo sample by 0.08·∇p, and `knifeEdge` shading is
  clamped to ±0.35.

## photonic-caustics
- Kept: height-from-depth normal, bend, aperture, bands, click light, persistence formula, ACES, params.
- **Packing floor fix:** A was ACES display (photo included), read back as irradiance, so the photo fed
  the light every frame. A = (irradiance, causticAlpha) now. Steady state is bounded:
  I ≤ 0.32·fresh / (1 − 0.68·0.96) ≈ 0.92·fresh. **Expect the image to look less washed out than HEAD.**
- Idea 1 (Jacobian caustics): `detJ` per channel from the 2-texel depth Laplacian (clamped ±6) plus an
  analytic ripple Laplacian; gain = 1/|det| clamped to [0, 4]. It adds light where focusing and removes
  a little where spreading.
- Idea 2 (glint): Blinn-Phong, n = 60, light at the cursor 0.35 above the surface; display only.

## Rescue list (found this batch, not changed)
| Shader | What's wrong | Evidence |
|---|---|---|
| physarum | agents in extraBuffer[0..] (overwritten each frame, holds audio); writes only agent pixels | code read |
| navier-stokes-dye | A written as velocity then overwritten with colour; palette from unwritten plasmaBuffer; dead entry point | code read |
| multi-turing | unstable Gray-Scott (DA = DT = 1, unnormalised laplacian) → per-pixel checkerboard; stable version is uniform at default params | `mt_head.py`, `mt_fix.py`, `mt_seed.py` |
| lenia | stores thresholded state → frozen binary stamps; continuous state floods at HEAD params | `lenia.py`, `lenia2.py` |
