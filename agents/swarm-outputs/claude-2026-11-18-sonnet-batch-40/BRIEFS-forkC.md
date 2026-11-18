# BRIEFS — fork C (gen-liquid-neon-cyber-metropolis, gen-cyber-organic-liquid-neon-pulsar)

Written BEFORE any WGSL edit. HEAD = origin/main 0761b6b9. Scratch: `/tmp/claude-0/-root-image-video-effects/914950b4-f44b-4d87-a537-edda39759ec7/scratchpad/forkC/`.

## HEAD render table (SwiftShader, saved defaults 0.5,0.5,0.5,0.5; harness SRC=img)
| file | case | meanL | stdL | frameMs @192 | look |
|---|---|---|---|---|---|
| metropolis | idle t≈0–1.5 | 0.426 | 0.309 | 209 | street-level; saturated magenta "sky" wall of accumulated glow, dark trunk, blue-grey crowns |
| metropolis | held (0.4,0.6,1) | 0.610 | 0.250 | 145 | magenta wall + one tower edge |
| metropolis | audio .8/.5/.9 | 0.440 | 0.268 | 267 | tower closeup, magenta |
| metropolis | T0=12 | 0.669 | 0.266 | 338 | **flat lilac wall** over the whole top 60 % of the frame |
| metropolis | T0=30 | 0.674 | 0.188 | 430 | **flat cyan wall** — frame is mostly one colour |
| pulsar | idle | 0.121 | 0.082 | 1131 | dark brown/blue petals, readable but dim |
| pulsar | held (0.4,0.6,1) | 0.122 | 0.080 | 1320 | as idle; dent near cursor |
| pulsar | audio .8/.5/.9 | 0.200 | 0.134 | 990 | orange/blue petals, brighter |
| pulsar | T0=40 held (0.8,0.5) | 0.144 | 0.062 | 665 | smooth flat brown ball; dent NOT at cursor |

nan = 0 everywhere. All four sliders passed through as saved defaults (metropolis has no `params` in JSON; the host falls back to `zoomParams = [0.5,0.5,0.5,0.5]` and `x-meta.upgrade.params` documents the same 0.5 defaults).

## HEAD defects found by reading + measuring (rescues, not ideas)

### metropolis
**R1 — camera sits inside the tower field (CONFIRMED, CPU port + renders).** `ro.y = 14 + 3 sin(0.3 t)` orbiting radius 28. Towers are `boxSDF(q − (0, h/2, 0), (0.36 rep, h, 0.36 rep))`, i.e. they span y ∈ [−h/2, 1.5 h] with h up to 11.5 (neon shell to 1.65 h ≈ 19, KIFS crowns to ≈ 25). A numpy port of `map()` (`forkC/metro_cam.py`) sampled along the orbit: camera is **inside** the SDF (d < 0.05) in **23 % of the period** and within 1.5 of a surface 55 % (mouse extremes included); the renders at T0=12/30 are the consequence (rays start with d<0 → one flat neon/lilac/cyan wall). Fix: orbit altitude 28 ± 2 (scan `metro_cam3.py`: 0.00 % inside idle, 0.2 % only at bass 1.5 + Audio Reactivity 1.0, min d 3.5 idle).
**R2 — `pow(negative, 2.0)` in both traffic-lane profiles (CONFIRMED by reading).** `exp(-pow((cl.x - 0.45) / 0.09, 2.0))`: `cl.x ∈ (0, 3.25)` so the base is negative for half the street-edge ground. WGSL `pow` with x<0 is indeterminate (NaN on NVIDIA/AMD via exp2(y·log2 x)); SwiftShader happens to return the even-power value (nan = 0 here) so the gates do not see it. Fix: `d*d`.
**Not rescued, flagged:** the towers are fully skinned by the neon shell (`neonSize` > concrete box on every axis, margin 0.03·rep > the ±0.08 rib), so `mat < 0.5` only ever occurs on the KIFS crowns and the ground; the window lattice (Idea 5) and the ground ideas (apron / traffic / wet reflections / warp ring) therefore live on a small part of the frame, and more so from the lifted camera. I add the new ideas where the pixels are (neon skin) rather than re-plumb the material split (that would change the identity).

### pulsar
**R1 — the pointer dent, the lighting and the beam axis mix the rotating object frame with the fixed screen frame (CONFIRMED by test).** `main()` rotates every march sample (`p = rotY(0.1 t)·rotX(0.05 t)·p`), but `map()` computes the cursor dent from `p.xy − mouse_p.xy` as if `p` were screen-aligned, `view_dir = normalize(ro − p)` / the light use the rotated `p`/normal against an unrotated `ro`, and the lighthouse beams use `magAxis.xy` (object frame) as a screen direction while the hotspots use `normalize(p)·magAxis` (object frame). Test at T0=40 with the cursor held at x=0.2 vs 0.8: the dent centroid lands at x=136 px for the LEFT cursor and x=48 px for the RIGHT cursor (192 px frame) — mirrored — while at T≈1 it lands within 22 px of the cursor. So the pointer stops following the cursor after a few seconds, the rim/spec drift, and the beams no longer pass through the hotspots. Fix: one pair of helpers `spinObj` / `unspinObj` (the exact HEAD rotation and its transpose); the dent is computed in screen space and re-rotated; diffuse/spec/rim use the screen-frame normal and position; `magAxisS = unspinObj(magAxis)` drives the beam direction and facing. At t = 0 the frames coincide so the first second is identical.
**Not rescued, flagged (magnitude rule):** `col = mix(bg, col, clamp(t / 10, 0, 1))` has the sense inverted: the sphere is hit at t ≈ 2.4, so the surface keeps 24 % of its colour and 76 % is `bg`, while rays that miss (t > 10) get weight 1 and never show `bg`. Correcting it (scratch `v/pulsar_fadefix.wgsl`) takes idle meanL 0.12 → 0.44 and turns the body cream-pastel. That is a 3.6× change of the default exposure of every tuned term, so it is the owner's call; the new ideas are added AFTER the fade (like the HEAD beams) so they are not attenuated by it.

## Mechanism interrogation (§12.1)

### metropolis
- Tactic 1 (kernel): the tower skin is a ribbed `boxSDF` shell with a per-tower height hash; the skin shading is flat `neonCol·(1.8±0.6)` + packets — the next better approximation of "a neon-clad tower" is a *panelled* skin with signage.
- Tactic 2 (physics one step further): real towers carry (a) aircraft-obstruction lights on the roof, (b) tiled roof plant / panels, (c) vertical sign columns on the facade.
- Tactic 3 (intermediate thrown away): the hit normal `n` already separates roofs (n.y>0.75) from walls; `hHash` (per-tower id) and `qxz` (position inside the cell) are computed and used only for window flicker/apron.
- Tactic 6 (history): C is read as persistence colour with `max(col, prev·0.3)`; the new ideas ride the same persistence for free (a blinking beacon leaves a 1-frame afterglow, which is physically right for a lamp).

### pulsar
- Tactic 2: a pulsar's cap is not a single blob — the polar-gap sparks circulate around the magnetic axis (drifting subpulses, "spark carousel") and the dipole footpoints are concentric L-shells about that axis.
- Tactic 3: `magAxis` and `normalize(p)·magAxis` (the cap cosine) are computed already; the azimuth around `magAxis` and `1/(1−c²)` (the L-shell label) come for free from the same vectors.
- Tactic 6: C history already blends at 0.25–0.33 per frame with decay 0.96, so a circulating spark leaves a short comet tail without any new state.

## IDEA CARDS

```
SHADER: gen-liquid-neon-cyber-metropolis
IDENTITY: a raymarched infinite grid of neon-clad towers and dark crowns under a ribbed liquid-neon skin, with orbiting camera, neon rivers down the walls, wet ground, traffic and a pointer gravity warp.
KEEP VERBATIM: map()/boxSDF/KIFS crown/neon rib shell/smin joins; cityRepSize + density slider; audio extrusion (plasmaBuffer[0].x · Audio Reactivity); gravityWarp + horizon ring; liquid packets (Idea 1), wet-street reflections (Idea 2), warp ring (Idea 3), traffic (Idea 4), window lattice (Idea 5), apron; neon persistence `max(col, prev·0.3)`; ACES then 0.4545; 4 sliders (x neon, y density, z audio, w warp) and the x-meta.upgrade.params block; alpha/depth formulas.
RESCUES: R1 camera altitude clears the skyline (14±3 → 28±2); R2 pow(neg,2) → square.
ADD (3 native ideas, all on the neon skin where the pixels are):
  6. Neon sign columns — one vertical LED sign strip per face on ~1 in 3 towers: a column of 0.4×0.55-unit glyph cells whose on/off bits scroll downward (the same direction as the neon packets), dark mullions between cells, hue per tower, bass flicker. Belongs: a neon-skinned city's faces carry signage, and it reuses the packet flow direction.
  7. Roof panel seams — on up-facing neon skin (n.y > 0.75) a tiled panel lattice: per-panel brightness from the tower hash, dark seams. Belongs: from the lifted camera the roofs are ~30 % of the frame and were flat slabs.
  8. Obstruction beacons — a red aircraft-warning lamp on one roof corner per tower, blinking with a per-tower phase (hHash), glow halo on the roof. Belongs: the skyline's most recognisable physical detail; leaves a one-frame afterglow through the existing C persistence.
FORBID: springs, extra ripples/shockwaves, IQ palette on the whole look, rain/ground-only ideas (invisible from the camera), re-plumbing the material split, changing the neon palette.
A PACKING: unchanged — ACES then gamma display RGBA; C read as persistence history.
FORMULA ROWS: none from §12.2 (native city nouns); no row used twice in the batch.
```

```
SHADER: gen-cyber-organic-liquid-neon-pulsar
IDENTITY: a hyper-viscous liquid-neon core wrapped in Voronoi metallic fibres, pulsing with bass, with a precessing magnetic axis whose polar hotspots and lighthouse beams sweep the frame (Crab pulsar, 30.2 Hz).
KEEP VERBATIM: map() (field warp, fBM core, Voronoi fibres, smin), the rotating scene, palette, fibre current packets (Idea 2), polar cap hotspots (Idea 3), lighthouse beams (Idea 1) + `facing` flare, Crab strobe/field-line glow, ripple wavefronts, C temporal blend, chromatic aberration, ACES, 4 sliders, saved params, the `mix(bg, col, t/10)` fade (flagged, not touched).
RESCUES: R1 screen/object frame consistency (dent follows the cursor, lighting + beams in the screen frame).
ADD (2 native ideas, both on the core surface, added AFTER the bg fade so they are not attenuated 4×):
  4. Spark carousel (subpulse drift) — six hot sparks circulate about the magnetic axis on a ring around each polar cap, at a rate tied to the Pulsation Speed slider, hot-white/base-hue, bass-boosted. Belongs: the polar-gap sparks of a real pulsar circulate around the cap (carousel model); it fuses to the existing cap and axis.
  5. Dipole L-shell rings — thin glowing rings at geometrically spaced L-shells (L = 1/(1−c²)), c the same cap cosine, slowly drifting poleward; fade out inside the hotspot and at the equator. Belongs: the "10^8 Tesla magnetic field topology" claim in the header becomes visible as the dipole's own footprint, concentric on the same axis the hotspots use.
FORBID: a new torus/jet SDF, springs, replacing the beams, thin-film/oil-slick colour, touching the Voronoi fibres, changing exposure.
A PACKING: unchanged — HDR display RGB + alpha (C colour history), ACES on writeTexture only.
FORMULA ROWS: none (Airy disc left unused — the body fills the frame so a point-source PSF would be a costume).
```
