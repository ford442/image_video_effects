# BRIEFS — Fork B (sonnet/batch-26): interactive-voronoi-lens (1st), refraction-shards (1st), crystal-refraction (2nd)

Written 2026-11-09 BEFORE any WGSL edit. HEAD renders: scratchpad/forkB/<id>_head_{192,576}_{idle,held}.png (+ .log), montages `<id>_head_m.png` (576, idle|held). Harness: `forkB/mrb.mjs` = `agents/mr.mjs` + `RIPPLES='[[x,y,tStart],…]'` (sets config.y and ripples[]; absolute start time) so click paths can be exercised; plain mr.mjs never sets ripples (config.y = 0), which is also why HEAD's `dt = u.config.y` looked "fine" in the base renders. A16=1 everywhere.
Shared A-texel state scheme (voronoi lens, shards): texel (0,0) = state, texel (1,0) = `(fract(lastTime),0,0,0.7371)` sentinel (tol 0.001); C reads masked on those two texels; dt = clamp(fract(time − st1.x), 0.001, 0.05); f16 rest-snap on the cursor spring. Reference: public/shaders/chroma-kinetic.wgsl.

---------------------------------------------------------------------------------------------------
## 1. interactive-voronoi-lens  (1st pass; compiles; real-app behaviour is badly broken)

### HEAD observation (192/576, idle|held — minirender has persistent extraBuffer so it hides most of this)
A field of "pebble" lenslets: every Voronoi cell magnifies around its own jittering centre (`bulge = 1 − sin(d·k)`), a blue body glow `neon ∝ cell_edge` (s_dist − m_dist is LARGE at the cell centre and 0 on the border, so it is a body glow, borders stay dark), bass-driven jitter, trail feedback in A. Healthy picture (meanL .447 / stdL .157 / meanA .471 idle).
In the real app (extraBuffer re-uploaded zeroed every frame; every thread read-modify-writes the same 8 floats) the interactive half is dead:
- `dt = u.config.y` is the ripple COUNT (0 until the first click, then 1..50): the spring `velocity += accel*dt` is frozen at 0 until a click and then integrates with dt up to 50 (blow-up). `smoothMouse` is ≈ 0 each frame, so the "gravity well" sits at the TOP-LEFT corner, not under the cursor.
- `prevPress`/`clickTime`/`clickPos` are zero every frame: `isPress>0.5 && prevPress<=0.5` is true on EVERY held frame (clickTime=time, age=0 → a static glow dot at the cursor while held), and with the button up `age = time − 0` is > 1.25 after the first 1.25 s of the app, so the shockwave never plays; for the first 1.25 s after load it plays from (0,0).
- `time*(1+chaos*2)*(1+treble*0.5)` inside the cell-centre phase: phase teleports by time·Δtreble (at t=60 s a 0.1 treble change = 6 rad → every cell jumps).
- `prev` (C) trusted raw: inherited C from another shader (up to 50.0) feeds `feedbackEnergy*0.02` offset → whole-frame smear for ~2 s on a direct switch.
HEAD has no chromatic, depth-of-field or parallax behaviour; `depth` is only used for a fog tint.

### Idea Card
```
SHADER: interactive-voronoi-lens
IDENTITY: a field of jittering Voronoi pebble-lenses — each cell magnifies the photo around its own centre, glows blue in its body, the cursor pulls the cell centres (gravity well), a click sends a shockwave, trails persist
KEEP VERBATIM: 4 params + roles (cell_density → cells, lens_strength → magnification/glow/gravity, chaos → jitter + speed, lens_curve → bulge frequency); 3×3 voronoi + smin second distance; bulge = 1 − sin(d·k) magnification around the (gravity-nudged) cell centre; cell_edge body glow; spring-damped cursor "lagging well"; shockwave push + neon ring; env (bass envelope in A.a); trail mix; ACES; semantic alpha; A = (trail rgb, env).
MECHANISM INTERROGATION (§12.1):
  tactic 1/2 (physics one step further): a lens ARRAY is a light-field camera / integral-imaging sheet — each lenslet sees the scene from its own viewpoint (parallax between neighbours that depends on depth), and every lenslet rim shows a thin Fresnel reflection seam where the surface curvature runs out; a light-field user REFOCUSES by picking a depth.
  tactic 3 (promote an intermediate): `depth` is already sampled (only for fog); `cell_edge` (0 on the seam → body) already exists and is exactly the lenslet radial coordinate; the spring (rescued) already yields the cursor position the focus can follow.
  tactic 6 (history): C stays (trail rgb, env); the only new history is the cursor spring in two masked A texels.
ADD (3 native ideas):
  1. Integral-imaging parallax — each lenslet's sample is shifted by (cellCentreUV − 0.5) × (cellDepth − 0.5) × k·strength: neighbouring cells show the scene from slightly different viewpoints, depth-dependent, growing toward the frame edge.
  2. Lenslet rim catch-light, energy-accounted (§12.2F Fresnel–Schlick, new use) — rn = 1 − smoothstep(0, 0.25, cell_edge) is the cell's radial coordinate, cosθ = sqrt(1 − rn²), F = Schlick(cosθ, 0.04); the seam REFLECTS F of the sky-white sheen and transmits (1 − F) of the magnified image (energy moved, not added) → a thin glassy rim between pebbles.
  3. Cursor refocus — the focal plane is the depth under the sprung cursor; each lenslet blurs by |cellDepth − focusDepth| (4-tap rotated diamond, radius ≤ ~0.012 uv) so pebbles at the cursor's depth are crisp and the rest soften, like re-focusing a plenoptic photo.
FORMULA ADMISSION: row used = Fresnel–Schlick (F), new use on this file (budget: voronoi lens + fractal-glass only). 1 and 3 are tactic-derived. All consume quantities HEAD computes (cell centre, depth, cell_edge, smoothMouse). Deletion test: remove any → still the pebble-lens field; the field alone is not.
FORBID on this file: IQ palette, extra neon outlines, a second shockwave motif, chromatic split (Cauchy row is not on this file's budget), hologram/scanline costume, any new param.
A PACKING: (trail rgb, env) display-ish history (unchanged); texels (0,0),(1,0) = spring state (masked on read).
```
### RESCUE list
- R1 dead extraBuffer[0..7] state + per-thread race + `dt = u.config.y` → spring (k 70, d 12 as HEAD) in A texels with real dt, f16 rest-snap. Default look changes in the real app: the well now sits under the cursor (HEAD: top-left corner). In minirender HEAD (persistent extraBuffer, dt = 0) the spring is frozen → the well sat at (0,0) too.
- R2 dead shockwave/click state → shockwaves from `ripples[]` (`age = time − r.z`, age < 1.25, count = min(u32(config.y), 50u); every click within 1.25 s rings, instead of one latched click).
- R3 treble inside the time multiplier → bounded additive `treble*0.9` phase offset (identical at audio 0).
- R4 inherited-C clamp on `prev` (rgb ≤ 2, a ∈ [0,1]) so a direct switch cannot smear the frame; state texels masked.

---------------------------------------------------------------------------------------------------
## 2. refraction-shards  (1st pass; compiles)

### HEAD observation
Voronoi shards over the photo; each pixel's `shardNormal = normalize(bestDelta + toSpring·…)` is a UNIT vector pointing from the pixel to its shard point, so the deflection has the same magnitude `refraction` everywhere and flips direction through the shard centre — the sunburst/pie look (visible in the montage). White hairline edge glint (palette), iridescent blobs near strong features, cursor flare, ripple fronts. meanL .519 / stdL .168 / meanA .838 idle, .533/.166/.852 held. Healthy.
- Spring: single-writer extraBuffer[133..138] → zeroed per frame; in the real app `spring = mouse` for every thread except one (race) → raw cursor; the "smoothed cursor" is a lie (in minirender it works, hence looks fine).
- `binA = plasmaBuffer[3].y`, `binB = plasmaBuffer[7].x` are always 0 → `prism*(…+binB*0.3)` and `facetGlint*(…+binA*0.5)` carry dead terms.
- Header says "A packing: ACES display RGBA" but A stores `hdr` (PRE-ACES `mix(color, hist.rgb, w)`, can exceed 1) and C is read back as that HDR history → the header lies; the packing itself is consistent (HDR trail, ACES on writeTexture) — keep, fix the header.
- `hist` (C) trusted raw (inherited C poison).
- "Cauchy 3-band" comment but it is a symmetric fixed ±1.2·dispVec; and with `centerUV + dispVec*1.2` for RED (i.e. red deflects MORE than green) — backwards vs glass (blue bends most).

### Idea Card
```
SHADER: refraction-shards
IDENTITY: voronoi glass shards that bend the photo along their own normals, white iridescent edge glint, cursor flare, fracture wavefronts after clicks
KEEP VERBATIM: 4 params + roles (scale → shard size, refraction → deflection amount, roughness → per-shard wobble, chromatic → prism dispersion amount); hash22 layout + smooth drift; facetEdge/edgeLine hairline + glint palette; shardNormal direction (bestDelta + cursor + ripple); mouseInteraction flare; HDR trail feedback; ACES; semantic alpha; depth blend.
MECHANISM INTERROGATION (§12.1):
  tactic 1/2: the unit-normal deflection is the linearised, constant-tilt cartoon of a facet. A real glass shard has a TILT; deflection angle follows Snell (δ = θ − asin(sinθ/n)) so steeper shards deflect more, disperse more (Δn between colours multiplies the same angle) and have a longer path through the glass (Beer–Lambert).
  tactic 3: the pixel's distance to its shard point |bestDelta| is already computed — it is the cone/pyramid slope coordinate (apex flat, rim steep); cellSeed gives a per-shard tilt.
  tactic 6: C stays an HDR trail; only the cursor spring is new state (masked A texels).
ADD (2 native ideas):
  1. Per-shard tilt → Snell deflection with Cauchy-weighted dispersion (§12.2F Snell vector refraction + Cauchy dispersion, both budgeted to this file) — θ = (0.30 + 0.45·seed)·(0.7..1.2 across the shard); `refract(−z, n(θ), 1/1.5)` gives the deflection gain (normalised to 1 at θ = 0.55 so the mean look and the refraction slider keep their meaning); the R/G/B split follows the Cauchy ratio n(λ)=A+B/λ² (650/550/450 nm → −0.73 : 0 : +1.27, blue bends most) and scales with the shard's own gain, so steep shards fringe harder; prism slider keeps its magnitude role.
  2. Oblique-path Beer–Lambert tint (§12.2F Beer–Lambert, budgeted to this file) — the refracted ray's path through the glass is 1/cosθt (from the same Snell result); only the EXTRA path over normal incidence absorbs, exp(−σ·T·(path−1)) with σ = (0.11, 0.04, 0.17): flat shards stay clear, steep shards go sea-green.
FORMULA ADMISSION: rows Snell + Cauchy + Beer–Lambert (F) — all on this file's budget; each consumes bestDelta/cellSeed/shardNormal that exist. Deletion test: remove either → still sunburst shards with hairline glint. Honest limit (NOTES): Snell is nearly linear at these tilts (≤ 10 % off linear at 0.85 rad) — the visible change is mostly per-shard tilt variation + tilt-scaled dispersion + path tint.
FORBID on this file: new motif (cracks, lightning), IQ re-palette, springs beyond the cursor spring HEAD claimed, any new param, TIR (crystal-facets owns it).
A PACKING: HDR (pre-ACES) trail RGB + semantic alpha (header corrected from "ACES display"); texels (0,0),(1,0) = cursor spring state (masked on read).
```
### RESCUE list
- R1 dead cursor spring → A-texel spring (ω 14 critical damping, velocity clamp ±4, f16 rest-snap) — pointer-led shader, native. Default look unchanged at idle (cursor 0.5,0.5 is the spring rest); only the lag is new.
- R2 dead `binA`/`binB` (plasmaBuffer[3..7]) removed; audio stays on bass/mids/treble.
- R3 header "A packing" lie corrected; `hist` inherited-C clamp (rgb ≤ 4).
- R4 dispersion sign: blue now bends most along the deflection (was red); the fringe colours swap sides (documented default-look change, luma-neutral).

---------------------------------------------------------------------------------------------------
## 3. crystal-refraction  (2nd pass: Ideas = table window; per-facet spectral fire flashes)

### HEAD observation (576 montage)
A cursor-centred stone (radius 0.4 of uv): octagonal flat table, angular facet wedges (numFacets 3..13), per-wedge displacement `displacementDir·dist·strength·falloff`, symmetric dispersion offsets (R ×(1+d), B ×(1−d)), facet-edge highlight, fire flashes. BUT a full-screen concentric RAINBOW RING pattern (`clockRings = sin(|screenUV − 0.5|·95 − time·…)` → `spectral·|clockRings|·0.1`) is stamped over the whole image regardless of the stone, centred on the screen, not the cursor — the generic "clock rings" overlay (batch-25 cut the same block from crystal-illuminator). `toCenter`/`dist`/`atan2` are in plain uv (not aspect-corrected) → on 16:9 the lens is a 1.78× wider ellipse and the wedges are squashed. meanL .469 / stdL .148 / meanA .137 (alpha is transmission, 0 outside the stone — semantic).
mids and treble are used ONLY by the clock rings.

### Idea Card
```
SHADER: crystal-refraction
IDENTITY: a cut-gemstone lens under the cursor — octagonal table window, angular facet wedges, dispersion-fringed refraction, spectral fire flashes
KEEP VERBATIM: 4 params + roles (facetScale → wedge count, dispersion → IOR + fringe + fire amount, strength → refraction, thickness → transmission/alpha); brilliant-cut table (Idea 1 of 2026-10-04); per-facet fire flash with facetSeed (Idea 2 of 2026-10-04); stepped-angle wedge displacement; ±dispersionAmt offsets; Fresnel + Beer–Lambert alpha; ACES; A = display RGBA.
MECHANISM INTERROGATION (§12.1):
  tactic 5 (artifact of the real device): a faceted stone has a FROSTED GIRDLE — the thin rough rim band where the crown meets the pavilion — which is what draws its outline and sparkles with a different (granular) character from the facets.
  tactic 8 (energy accounting): a facet that flashes is, at that instant, MIRRORING light that it is not transmitting — the flash should be taken from the facet's own image and its glow spills into the neighbouring facets (scintillation bloom), not just be added on top.
  tactic 2: the real trigger of fire is the stone moving/being struck by light — a click is a light strike: facets should ignite one after another in their own random order, not an unrelated rainbow ring.
ADD (3 native ideas):
  1. Frosted girdle — a thin rim band at 0.90–1.0 of the stone radius: granular value-noise sparkle (treble-lifted) that whitens/frosts the image (blend toward a pale grey of the local luma), outlining the stone where HEAD's refraction just faded to zero.
  2. Energy-conserving fire with facet spill (§12.2F Energy-conserving bloom) — transmitted light is dimmed by the flash (`color·(1 − 0.55·flash)`), and the flash value is spilled 0.3 into the ±1 neighbouring wedges (their own seeds/phases), so a flash is a soft-edged glint between facets instead of an additive wedge.
  3. Click strike ignites facets in sequence — every ripple ignites each wedge after its own delay (facetSeed·0.45 s) with a decaying spectral flash in that wedge's fire colour, inside the stone only; replaces HEAD's rainbow ring.
FORMULA ADMISSION: row used = Energy-conserving bloom (F) (budget: crystal-refraction + crystal-facets); 1 and 3 are tactic-derived. All consume facetSeed / steppedAngle / sweep / falloff / ripples that HEAD has. No new Fresnel/Cauchy/Beer–Lambert (file already owns them).
FORBID on this file: ambient full-screen rings, springs, IQ palette, TIR/crown–pavilion tiers (crystal-facets' ideas), new param.
A PACKING: ACES display RGBA (unchanged; C not read).
```
### RESCUE list
- R1 full-screen rainbow `clockRings` overlay CUT (generic, not crystal; changes the default look: removes concentric rings everywhere; measured before/after in NOTES).
- R2 aspect: lens distance/angle in aspect-corrected space, displacement converted back to uv — square renders unchanged, wide frames get a round stone with true wedges.
- R3 audio: with the rings gone mids/treble would be unused → treble lifts the girdle sparkle, mids add a bounded (non-time-multiplied) shift to the fire hue.

---------------------------------------------------------------------------------------------------
## Revisions after measuring (written AFTER the first WGSL pass; cards above stay as the pre-edit record)

- **refraction-shards, Idea 2** — the original "only the EXTRA oblique path absorbs" version was invisible (the refracted-ray cosine is 0.92–0.98 at these tilts, extra path ≤ 9 %). Shipped version: each shard is a slab of its own thickness (`mix(0.4, 1.6, cellSeed.x)`), the ray crosses it along `1/cos θt` (θt from the same `refract()` result as Idea 1), absorption `exp(−σ·1.25·max(path − 0.4, 0))`, σ = (0.16, 0.04, 0.10) → teal-green on thick/steep shards, thinnest shards clear. Costs −0.024 meanL at default (all of the default-look change; see NOTES).
- **refraction-shards, aspect** — an isotropic-shard fix (`uv * aspectVec`) was tried and REVERTED: on 16:9 it raises the shard count by 78 % (cells are per frame-height instead of per axis). HEAD's stretched cells kept; flagged as an open item in NOTES.
- **crystal-refraction numbering** — shipped comment labels are Idea 1 (table, 2026-10-04), Idea 2 (fire, 2026-10-04), **Idea 3 = energy-conserving fire with facet spill, Idea 4 = frosted girdle, Idea 5 = click strike** (the card's order was girdle / energy / strike). Also fixed: the facet seed was keyed on the raw `atan2` index, so the wedge straddling the −x axis had two different seeds (R4: index wrapped modulo numFacets via `facetSeedOf`).
- **crystal-refraction, Idea 5 strength** — first pass was too faint against the already-busy fire wedges; gain raised to `0.9 + dispersion·0.8`, dimming 0.5, decay `exp(−4·t)·exp(−0.6·age)`.
- **interactive-voronoi-lens** — rim weight lowered to `0.15 + 0.65·strength` (first pass read as a pale web over the whole frame); inherited-C rgb clamp 1.5 (not 2).
