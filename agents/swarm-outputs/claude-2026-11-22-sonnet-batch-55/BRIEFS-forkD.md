# BRIEFS — fork D (sonnet/batch-55): gen-aetheric-tachyon-lattice, gen-ethereal-neon-bismuth-origami

Written BEFORE any WGSL edit. HEAD copies: `/tmp/claude-0/-root-image-video-effects/741dbe8f-87a6-4dc9-8039-cfc9fd9fdfde/scratchpad/d/*_head.wgsl`. Both are 2nd+ passes (both already have `Ideas:`). Both are generators (render without source; also checked with SRC=img — they ignore it).

## HEAD verification (what the checklist actually found)

| checklist item | gen-aetheric-tachyon-lattice | gen-ethereal-neon-bismuth-origami |
|---|---|---|
| ACES on display, non-negative input | yes, `aces(max(col,0))` | yes, but input is `col` (additive, ≥0 by construction: palette ≥ 0, `max(dot,0)` terms); then `pow(col,0.4545)` — same ACES→sRGB-encode chain as ~20 other `gen-*` files (catalog convention for generators, physically right: Narkowicz ACES is linear-out) → NOT a defect |
| audio via plasmaBuffer[0].xyz | **present** (`plasmaBuffer[0].x` bass → emission, colour, junction); mids/treble unused | none, and none claimed in JSON (descriptive `features`) |
| dataTextureC load | none. A (ACES display RGBA) is read downstream by the next slot as display colour — a legitimate reason for the write. No native idea needs feedback (stateless ray-marched lattice; tachyon wake is analytic) → **decision: no C read** | none. Same decision: A write is for the downstream slot, no native feedback idea |
| dataTextureB | `textureStore(dataTextureB, id.xy, vec4(0.0))` — zeros, undocumented; B has NO read binding in the single-pass contract (docs/BINDING_CONTRACT.md: "write (secondary / detail)"; only multipass graphs read it) → **removed** (hygiene, not an idea) | not written |
| extraBuffer | none touched | none touched |
| alpha | semantic coverage (0.04 void → 0.35+ on struts) | `hit + glow*0.04` — HEAD **meanA 1.000 is honest**: debug render (red=hit, green=glow, blue=t/10) gives hit fraction **1.0**, mean hit distance t≈0.77: the camera at z=−3 sits inside a dense KIFS shell so every ray hits within ~1 unit; there is NO dark expanse at default (`scale` 0.5 → fold offset 0.5) |
| uv centring | `(id − 0.5·res)/res.y`: row 128 luma 0.604 vs 0.576/0.617 neighbours (row-diff 0.009, below the 0.025 baseline noise) → no seam artefact | same formula: **row 128 luma 0.749 vs 0.858 above / 0.819 below** (row-diff 0.118 vs 0.001 baseline) — a one-pixel pink seam across the middle. Root cause: integer pixel coords make `uv.y == 0.0` exactly for row res.y/2, so the ray (ro.y=0, rd.y=0) lies IN the `abs()` fold plane y=0: finite-difference normals straddle the kink and `tang = cross(n,(0,1,1e-4))` degenerates → crease glow fires on the whole row. **+0.5 centring fixes it** (row-diff 0.024 after; verified `o_v2_center.wgsl`). The remaining top/bottom step (0.858 vs 0.819) is real geometry (fold plane) |
| why meanL 0.82 | n/a (meanL 0.084 is a void with thin lit wires — by design) | NOT clipping and NOT the gamma alone: gamma removal only takes 0.82 → 0.67 (`o_v1_nogamma`). The rest: palette is a half-intensity cosine (mean 0.5) lit by 0.2 ambient + 0.8 diffuse + additive edge (0.5) + crease (0.8) + glow veil (mean glow term 0.22 · purple), and every pixel is a lit front surface. → the picture lacks depth/occlusion: that is what Idea 2 (AO) targets |
| other HEAD defect found | none | `p.x = p.x*c − p.y*s; p.y = p.x*s + p.y*c` (and the y/z pair) reuses the already-updated component: a NON-orthogonal map, so the SDF is not a distance bound. Fixing it (`o_v3_orth.wgsl`) gives a completely different, much busier picture (meanL 0.82→0.80, stdL 0.107→0.141, new facet structure). **NOT fixed** — it IS the folded-paper identity of the HEAD picture; flagged as an open call |

## Idea Card — gen-aetheric-tachyon-lattice

```
SHADER: gen-aetheric-tachyon-lattice
IDENTITY: a ray-marched cubic lattice of glowing tubes (kaleidoscopically folded space) that the camera
  flies down, with cyan/magenta tachyon-checker emission on the struts, ember-hued deep folds and
  bright junction nodes, in a black void.
KEEP VERBATIM: 3 params (foldCount → fold iterations, tachyonSpeed → emission phase, latticeThickness → tube radius);
  abs-fold + rot2D(0.5)/rot2D(0.3) loop; three-axis tube SDF (dmin/dmid/dmax); Idea 1 fold-count material
  (foldAmt ember mix); Idea 2 junction nodes (exp(-dmid*14)*exp(-dmin*6)); sin·sin·sin tachyonVal checker
  with cyan/magenta/blue states; bass emission/colour/junction terms; mouse-down rd twist; camera drift
  z = −3 + 0.2·t; ACES; coverage alpha; depth t/20; A = ACES display RGBA.
MECHANISM INTERROGATION:
  tactic 1 (deepen kernel): sphere tracer is plain `t += 0.7d`; no occlusion/participating medium — the void is pure black.
  tactic 2 (physics one step further): a beam of superluminal particles in a conduit is a *stream* with a
    direction. HEAD's emission is an isotropic 3-D standing checker (sin·sin·sin) — nothing flows ALONG a strut.
    The real side effect of a charged stream in a medium is a luminous aura around the conduit (Cherenkov-like halo).
  tactic 3 (promote an intermediate): `mapEx` computes d1/d2/d3 (distance to the three tube families) and throws
    away WHICH tube is nearest and the coordinate along it. That is the strut's axis + position along it.
  tactic 6 (history): C is never read; A is display RGBA for the next slot. A feedback trail would be a generic
    overlay and the stream wake can be analytic → not used.
  tactic 7 (direction): the nearest tube's axis is exactly the missing direction.
ADD (2 native ideas):
  1. Axial tachyon packets — bright packets of light that travel ALONG each strut (phase = axial·7 − t·speed·2.5,
     axial = coordinate along the nearest tube, `pow(0.5+0.5 sin, 10)` for tight beads). Uses the promoted
     argmin intermediate (mapEx.w). Blue-white core that warms to the ember hue with fold count. Mids set the
     packet brightness. The existing checker emission stays; packets ride on top. A mirrored fold reverses the
     packet direction across a fold plane — which is what "folded space" should do to a flow.
  2. Soft inverse-square aether halo (§12.2F "Soft inverse-square", I/(d²+r₀²)) — accumulated along the existing
     march from the tube-distance `d` the tracer already computes, step-length weighted so it is a ray integral.
     Lights the black void around every conduit with a teal aura whose reach is set by foldCount's own tube radius
     (core r₀ ∝ latticeThickness), gives the lattice depth and the otherwise-0.04 coverage a semantic halo.
     Treble lifts the aura; bass already drives emission.
FORMULA ADMISSION: idea 1 is NOT a §12.2 row (domain mechanism, needs no ownership). Idea 2 = §12.2F Soft inverse-square
  (D owns it for aetheric only): family match = the struts are glow sources; consumes `d` the march already
  computes; deletion test: removing it leaves exactly HEAD (black void), keeping only it is not the lattice.
FORBID on this file: new params; C feedback trail; spring/ripple/IQ palette; additive domain twist (changes strut
  straightness = identity); thin-film; replacing the sin·sin·sin checker; any change to the fold loop or the SDF.
FLOOR: remove the zero-write to dataTextureB; mids/treble now read (all three of plasmaBuffer[0].xyz used);
  treble also lifts junction flash. No Upgraded bump for the B removal alone — bumped because ideas ship.
A PACKING: ACES display RGBA (unchanged; says so on the header).
RESCUE LIST: none visual (B zero-write removal is hygiene).
```

## Idea Card — gen-ethereal-neon-bismuth-origami

```
SHADER: gen-ethereal-neon-bismuth-origami
IDENTITY: an iterated-fold (KIFS) cube-shard scene lit as thin-film-iridescent bismuth: palette-by-Fresnel, stepped
  oxide terraces, neon edge lines, magenta crease glow along normal discontinuities, a purple volumetric
  glow veil; mouse-down blooms the folds open.
KEEP VERBATIM: 4 params (scale → fold offset, bloom-strength → mouse unfold, iridescence-rate → Fresnel palette
  phase, time-speed → clock); the `map()` KIFS loop INCLUDING the sheared rotation (see open call); cos palette;
  world-axis oxide terraces (Idea 1 of 2026-11-10); neon edge `fract(p·5)` lines; origami crease glow (normal
  vs normal at +0.03 tangent); glow accumulation; ACES + sRGB encode; coverage alpha (hit + glow); depth write; A = display RGBA.
MECHANISM INTERROGATION:
  tactic 2 (physics one step further): hopper crystals grow fastest at the edges, so each face is a recessed
    staircase of concentric rectangular steps, and the oxide film is thicker on exposed rims than in the recesses.
    HEAD's terraces are world-axis slabs `(p.z + 0.35 p.x)·9` that ignore the facets; and nothing is occluded —
    the picture has no recesses at all (all lit front surfaces, meanL 0.82).
  tactic 3 (promote an intermediate): the cube SDF `q = abs(p) − 0.5` in map() is exactly each facet's local
    frame, and its *median component* is the Chebyshev inset from the facet edge — computed and discarded.
    Also: the march step count/occlusion is discarded (no AO).
  tactic 1/6: n/a (kernel is a one-shot SDF; no history).
ADD (2 native ideas):
  1. Hopper stair-step rings — concentric rectangular terraces that follow each cube facet. Inset from the facet
     edge = −median(q) (normalised by the cube half-size 0.5 so every iteration level gets 4 steps); stair
     = floor(inset·4)/4, shadowed riser band at each step. Lighting only (step brightness + riser shadow) so it
     does NOT fight the existing colour terraces; the world-axis oxide bands keep the colour.
  2. Step-count ambient occlusion (§12.2E) — 5 taps of map() along the normal darken the recesses between shards
     (the hopper recesses), and the same occlusion grades the oxide film: exposed rims keep the thick-film
     palette, recesses slide toward thin-film (a +0.18·occlusion phase shift). Gives the shard field depth.
FORMULA ADMISSION: idea 1 is NOT a §12.2 row (domain mechanism). Idea 2 = §12.2E Step-count AO (D owns it for origami
  only): family = raymarched SDF; consumes the file's own `map()`; deletion test passes both ways (HEAD without
  AO = same shards, flatter; AO alone is not a bismuth crystal).
FORBID on this file: new params; changing the KIFS fold/rotation (identity — flagged as open call);
  removing the sRGB gamma (catalog convention); IQ palette swap; springs/ripples; thin-film as the whole look;
  SDF curvature (duplicates the crease glow); over-relaxed tracing (SDF is not a distance bound — would overshoot).
FLOOR / RESCUE: R1 +0.5 pixel centre (kills the seam row; row-diff 0.118 → 0.024). Audio floor: bass breathes the
  unfold (scale += 0.06·bass — the shader's own `fold/unfold` clock), treble lifts the crease neon (×(1+0.5·treble));
  bass=0 reproduces HEAD exactly → `audio-reactive` added to JSON features/tags (true: plasmaBuffer modulates the
  folds and the creases). No C read (decision above).
A PACKING: ACES display RGBA (unchanged).
```

## Cross-fork row ownership used here
Step-count AO (origami), Soft inverse-square (aetheric). No other §12.2 row. Idea 1 on each file is a domain mechanism.

---

## ADDENDUM (written after implementing; the card above is superseded where it differs)

**Decision change on the origami rotation.** The card said "NOT fixed — open call". After implementing, a debug render of `ex.y` (hopper inset) and `ao` on HEAD's sheared map showed **inset = 0.504 ± 0.009 everywhere** and AO flat (0.64–0.75): on the sheared (non-orthogonal) map the folded cube frames collapse into slabs, so Idea 1 cannot exist and Idea 2 only dims the whole frame. A time strip (t = 1,3,6,9,12,16,22,30) shows HEAD degenerating to a plaid grid at t = 1, 6, 9, 16 while the orthogonal variant stays a faceted shard field. The rotation fix is therefore shipped as **rescue R2** (4 lines, marked in the loop comment); after it inset std = 0.243 (spread 0..1) and AO ranges 0.45..1.0 with structure. To revert: restore the two `p.x/p.y` + `p.y/p.z` lines from `d/gen-ethereal-neon-bismuth-origami_head.wgsl` — but Ideas 1 and 2 then become invisible (a global 0.85× dim), so a revert means dropping both.
**Aetheric ideas are numbered 3 and 4** in the WGSL (the file already carries Idea 1 fold-count material and Idea 2 junction nodes): Idea 3 = axial tachyon packets, Idea 4 = soft inverse-square halo.
**Origami hot-path split:** `map()` is now a distance-only copy of the `mapEx()` loop (marked KEEP IN SYNC) so the 100-step march, the 12 normal taps and the 5 AO taps skip the inset bookkeeping; `mapEx()` runs once at the hit point. 0 px differ >2/255 vs the single-function version; timing 0.79–0.88× HEAD vs 1.37–1.64× before the split.
