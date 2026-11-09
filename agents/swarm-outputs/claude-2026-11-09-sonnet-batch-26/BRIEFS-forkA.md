# BRIEFS — Fork A (sonnet/batch-26): glass-shatter (1st, non-compiling), crystal-facets (2nd), glass-brick-wall (2nd)

Written 2026-11-09 BEFORE any WGSL edit. HEAD renders (A16=1, SRC=img, T0=2, 24 frames/3 s, defaults; `_a` idle cursor .5,.5 up audio 0, `_b` cursor .3,.6 held audio .4/.3/.2): scratchpad/forkA/out/<id>_head_{192,576}_{a,b}.png (+ .log). glass-shatter has no real HEAD render (does not compile): `gs_head_fixed.wgsl` = HEAD with `target`→`tgt` ONLY, to see the intent; in minirender extraBuffer persists, so its held-spring looks alive — judged by reading.
HEAD stats (192, idle / held): glass-shatter(fixed copy) meanL .530/.510 stdL .151/.184 meanA 1.00/.998; crystal-facets .655/.607, .112/.186, A .370/.467; glass-brick-wall .365/.430, .177/.175, A .413/.428.

---------------------------------------------------------------------------------------------------
## 1. glass-shatter (1st pass; does not compile at HEAD)

### HEAD observation
- `let target` (reserved) → whole file fails naga (on the knownFailures ratchet).
- The "held spring" (`heldState`, tension 150 / damping 12, target = mouse down) is written by thread (0,0) into extraBuffer[133..134] and read by every thread in the same dispatch; extraBuffer is re-uploaded ZEROED every frame → in the app `heldState` ≈ 0/racy, so `repelMask`'s `mix(0.18, 1.0, heldState)` is stuck at the 0.18 idle strength and the 0.15 C-ghost never engages. Held-drag is dead in the app (minirender hides it). `dt` is the constant 0.016.
- C ghost: `finalColor = mix(finalColor, prevColor, 0.15*held)` happens BEFORE `aces_tonemap`, but C = A = ACES display RGBA → display colour re-tone-mapped (packing inconsistency; brightens/compresses the ghost share).
- Alpha: `transmission + (shardRunner+clickFront)*0.5 + dot(finalColor, 1/3)` saturates (meanA 1.00): the luma term makes coverage depend on brightness; alpha carries no information.
- Click front uses `distance(uv, ripple.xy)` (not aspect-corrected) → elliptical on non-square canvases. (minor)
- There are NO visible crack lines: `edge` only scales a tilt-based Fresnel rim, glass density and specular; `v.dist` is the distance to the SEED, so `edgeRunner` runs rings around seeds, not along borders. The JSON description promises "stress birefringence … per-wavelength polariscope fringes along the cracks"; the code has none (and no crack memory in C — the JSON `temporal-crack-memory`/`stress-birefringence`/`crack-propagation` tags are false at HEAD).

### Idea Card
```
SHADER: glass-shatter
IDENTITY (one sentence): a pane of glass seen as Voronoi shards that are pushed away from the cursor (more when pressed), each shard tilted, tinted and Fresnel-rimmed with chromatic aberration, click fronts racing through it.
KEEP VERBATIM: 4 params + roles (scale → shard count, displacement → repel distance, edge → rim/density/specular, aberration → R/B split along shard tilt); voronoi seeds (hash22, 3x3); repel-from-cursor offset + per-shard random offset; held-strength mix(0.18,1.0,held) and spring tension 150 / damping 12; Fresnel + Beer-Lambert absorption + glassTint; shardRunner / edgeRunner; amber click front; bass/mids/treble modulation; ACES; depth blend; A = display RGBA.
MECHANISM INTERROGATION (§12.1):
  tactic 2 (physics one step further): glass that is struck does not shatter uniformly. Fragment size grows with distance from the impact (tiny crush zone, radial wedges, big outer plates). Under polarised light the stressed fracture boundaries show retardation fringes.
  tactic 3 (promote an intermediate): the voronoi loop already holds the nearest-seed distance d1 and could hold the second d2 and both seed vectors: d2-d1 is the distance to the shard border and normalize(p2-p1) is the border normal (this is the crack's orientation) — all of that is thrown away today.
  tactic 4 (second-order the parameter): `scale`/ShardSize is one scalar for the whole pane; its spatially varying version that still matches its name is shard size growing with distance from the impact point while pressed / just after a click.
  tactic 6 (history): C stays the display ghost (decoded in display space); the held-envelope moves from extraBuffer to A texels.
ADD (3 native ideas):
  1. Impact fragmentation gradient — while pressed (spring envelope) and for ~2 s after a click, the lattice is radially warped about the impact point r' = R*(r/R)^q, q = 1-0.5k, so shards are small near the impact and grow outward, radially elongated (radial cracks). Idle (k=0) = HEAD lattice exactly.
  2. Fracture lines that catch the light — hairlines on the real shard borders (F2-F1), width from `Edge`, brightness by how much the border normal faces the existing lightDir, brightened by the pressed zone and flaring amber where the click front passes (crack propagation made visible).
  3. Photoelastic stress fringes — a retardation band at the borders, strongest at the line and falling off with border distance, per wavelength I(λ)=sin²(π·Δ/λ) at 650/550/450 nm, Δ grows with the shard's displacement tilt (stress under load) — the "polariscope fringes along the cracks" the JSON already describes.
FORMULA ADMISSION: no Snell row used (budget slot unused by this fork). No Cauchy (file owns its aberration slider). Idea 3's cos² phase form is the photoelastic stress-optic law, NOT the §12.2 thin-film row — coordinator may count it, flagged. All three consume quantities the voronoi loop / lightDir / tilt / clickFront already provide. Deletion test: remove any → still a displaced-shard pane; cracks alone are not a shatter without the repel.
FORBID on this file: IQ palette, extra springs beyond the held envelope, a second ripple system, glow rings, new params, replacing the shard displacement.
A PACKING: ACES display RGBA (unchanged). Texels (0,0) = (held pos, held vel, 0, 0) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE in A only; C masked on those two texels.
```
### RESCUE list
- R1 compile: `target` removed with the dead extraBuffer spring block.
- R2 dead held spring (extraBuffer race + zeroed per frame) → A-texel state, real dt (clamp(fract(time−st1.x),0.001,0.05)), f16 rest-snap, 0.7371 sentinel, shared by all threads. Spring constants kept (150 / 12).
- R3 C ghost mixed in display space after ACES (was mixed pre-ACES with display colour). C read masked on the two state texels, `min(prev, 1)` clamp for inherited-C safety.
- R4 alpha no longer carries a luma term (was saturated at 1.0): transmission + runner/front glow + crack coverage.
- R5 click front aspect-corrected.
Default look: R1–R3 do not move the idle look (held=0); crack hairlines + fringes (Idea 2/3) are an intended visible default change; alpha moves 1.0 → ~0.9.

---------------------------------------------------------------------------------------------------
## 2. crystal-facets (2nd pass; existing Ideas: TIR flash; Beer-Lambert body colour; crown/pavilion rings)

### HEAD observation
- Healthy gem centred on the cursor (centre = mouse). Raw pointer already (a previous pass removed the racy spring); display C ghost mixed after ACES (consistent); alpha semantic (meanA .37/.47).
- BUG (visible at default, 576 px, left of the gem at screen angle ±π): `sector = floor(angle/sw + ring*0.5)` comes from `atan2` whose branch cut jumps `rawSector` by exactly `facetCount`, so `facetID = sector + ring*37` hashes differently on the two sides of ONE facet → a seam through a facet (different tilt/fracture on either half; visible horizontal discontinuity at the gem's left).
- BUG (time-growing): `angle = atan2(dir) + rotation` with `rotation = time*0.1`, but `offsetDir = (cos(sectorAngle), sin(sectorAngle))` uses the angle-space value, not the screen azimuth, and uses the facet's LOWER edge, not its centre. The offset direction drifts relative to its facet by `rotation` (a full turn after ~63 s: fringes eventually point tangentially / inverted).
- Scintillation: the gem turns (rotation) but nothing flashes with the turn; flashes are TIR (static per facet) and a treble-gated `hash11(facetID + time*12)` strobe. FractureDensity only tints/absorbs (alpha), cloudy facets don't exist.

### Idea Card
```
SHADER: crystal-facets
IDENTITY: a faceted gem centred on the cursor — kite-cut crown/pavilion tiers, per-facet RGB offsets, Beer-Lambert body colour, TIR flashes past the critical angle.
KEEP VERBATIM: 4 params + roles (FacetCount 3–16, RefractiveIndex glass→diamond (also critical angle), FractureDensity → purity/absorption, CrystalThickness → path length); crown/pavilion ring + half-offset sector layout; facetID hash; per-facet tilt offsets (r/g/b); TIR flash (critical angle, mirrorUV); Beer-Lambert bodyTint; edge lines; Fresnel; bass → causticPulse; treble sparkle; semantic alpha; ACES-then-C mix 0.06; A = display RGBA; held/ripple response.
MECHANISM INTERROGATION (§12.1):
  tactic 2: a diamond's brilliance is a bright/dark CONTRAST pattern: as the stone turns, each facet that mirrors the lamp flashes and the next one goes dark (extinction), and impurity kills it — a cloudy stone is dull.
  tactic 3: `facetFracture` (hash) is already computed per facet but only feeds `purity`; the facet's true azimuth is a by-product of `sector`, `ring`, `sw`, `rotation`.
  tactic 6: C is a 6 % display ghost; unchanged.
ADD (2 native ideas):
  1. Scintillation sweep — each TIR facet mirrors a fixed lamp azimuth: its flash follows cos^8(facet azimuth − lamp) as the gem rotates, so mirrored facets alternate bright flash ↔ dark extinction (mean brightness kept near HEAD). Non-TIR facets get a faint lamp glint.
  2. Cloudy inclusion facets — FractureDensity now also decides WHICH facets are cloudy (facetFracture over a density-driven threshold): a cloudy facet shows the picture through 4 wide milky taps and loses its TIR flash/sparkle (inclusions kill brilliance). 0 → none, default 0.2 → ~1–2 of 9 per ring, 1 → most.
FORMULA ADMISSION: tactic-derived, no §12.2 row (bloom slot unused). Same-noun: lamp, facet, extinction, inclusion — all gem vocabulary. Deletion test both ways OK.
FORBID: springs, IQ palette, glow rings, a girdle/outline that changes the full-frame identity, more cracks (glass-shatter owns the crack motif in this fork).
A PACKING: ACES display RGBA (unchanged).
```
### RESCUE list
- R1 seam: wrap the sector index modulo facetCount before hashing (facetID continuous across the atan2 cut).
- R2 offsetDir = facet's screen azimuth centre `(sector + 0.5 − ring*0.5)*sw − rotation` (was angle-space lower edge). Idle look at t≈2–5 s changes a little (≈9°–20° rotation of every fringe direction), later times much more.

---------------------------------------------------------------------------------------------------
## 3. glass-brick-wall (2nd pass; existing Ideas: dome dispersion; dome caustic; green block edges; wall reflection)

### HEAD observation
Healthy: domed blocks, per-brick fbm normal, mortar, caustic spot at a fixed (0.10,−0.08)+fbm point in EVERY block, green edges, wall band, pointer halo (flat blue additive disc by ptr_influence), click fronts. Raw pointer; C display ghost after ACES (consistent); alpha semantic (0.3 glass / 0.85–0.95 mortar). All blocks are identical copies (only fbm differs) and the lamp-less caustic never moves with the pointer; hollow-core structure of real glass blocks is absent.

### Idea Card
```
SHADER: glass-brick-wall
IDENTITY: a wall of domed glass blocks over the photo — dome dispersion, a caustic hot-spot per block, bottle-green edges, internal wall reflection, dark mortar.
KEEP VERBATIM: 4 params + roles (BrickSize → grid, Distortion → dome refraction, MortarSize, GlassDensity → path/absorption); fbm dome normal; mortar mask; the four existing ideas; pointer halo + click fronts; ACES-then-C mix 0.07; semantic alpha; A = display RGBA.
MECHANISM INTERROGATION (§12.1):
  tactic 5 (artifact of the real device): a technician of a glass-block wall names three things: blocks are cast individually (each a bit different in iron tint and dome tilt), the block is two fused halves around a HOLLOW CAVITY (a frame-in-frame outline with a refractive step), and a light source focuses on the FAR side of each dome from the lamp.
  tactic 3: `cellId` + `edgeMax` + `normalNoise` are already per-block quantities; the pointer is already a light-ish halo (ptr_influence).
  tactic 6: C = ACES display ghost, unchanged.
ADD (3 native ideas):
  1. Cast-block variation — a per-cellId hash gives each block its own dome-tilt offset of the caustic focus and a small iron-tint shift (green↔blue), so the wall reads hand-cast, not stamped.
  2. Hollow-core cavity — an inner square outline at |cell|≈0.33: inside it the ray crosses an air gap, so the dome refraction is weaker (step), and the cavity wall catches a thin bright line (frame-in-frame signature of glass blocks).
  3. Lamp-driven caustic focus — inside the existing pointer halo radius, each block's hot-spot slides to the far side of the dome from the cursor (focus opposite the source), blended by ptr_influence so far blocks keep HEAD's fixed focus.
FORMULA ADMISSION: tactic-derived; no HG (budget slot unused), no new Cauchy/Beer-Lambert.
FORBID: springs, new ripple systems, IQ palettes, changing mortar/dome geometry, new params.
A PACKING: ACES display RGBA (unchanged).
```
### RESCUE list
None expected (HEAD healthy). Will re-check the reversed `smoothstep(0.35+held*0.15, 0.0, d)` on real naga/Tint (HEAD already ships it).
