# sonnet/batch-22 — fork B briefs (written before any WGSL edit)

Shaders (all 2nd pass; every file already has an `Ideas:` line): gen-radiant-quantum-crystalline-forge, gen-resonant-quantum-obsidian-scarab-engine, gen-kryonic-quantum-aether-fractal-core.
HEAD diagnostics were done on scratch copies only (`$SCRATCH/forkB/`), not on the real files. Renders: single-frame time sweeps (`T0=<t> … frames=1`) at 192 px, idle cursor, audio 0.

JSON note (affects all judgements): scarab + kryonic have **no top-level `params`** (x-meta only), so the app feeds 0.5 x4 (scarab authored defaults 4/1.5/0.8/2.0, kryonic 1.5/0.5/1.0/0.2 are NOT what users see). Per COMMON.md I do not add `params`. I render at 0.5 x4 AND at the x-meta defaults. The forge has real `params` (0.5, 1, 0.8, 0.5).

Row use across my three files (§12.4, ≤2 per row): fold count as material = forge (R2) + kryonic (I1); SDF curvature = kryonic (I2) + scarab (I1). No orbit trap, no over-relaxed tracing.

---

## 1. SHADER: gen-radiant-quantum-crystalline-forge

IDENTITY: a KIFS crystal mass (6 abs-fold iterations, density slider = fold offset) flown into through iridescent fog, with twin-facet tints, glowing weld seams and razor cleavage glints.

KEEP VERBATIM: 4 params + roles (density → fold offset, chroma → twin tint / fresnel weight, fog → fog+seam glow, mouse influence → gravity-well uv push); the KIFS loop (offset `(1.2,0.8,1.5)*density*(1+bass*0.2)`, rotations, scale 1.8) and `d=(length(p)-1)/scale`; seam distance `(plane+edge)/scale`; iridescent baseCol; blackbody ramp; weld palette; cleavage glint; fog accumulation; hit/alpha/depth semantics; ACES on display; A = display RGBA.

MECHANISM INTERROGATION
- Tactic 2 (physics one step further): a forge is struck — a hammer blow sends a heat/shock front through the mass and the metal behind the front cools along the blackbody ramp. HEAD's seam heat is `exp(-dO*0.07)`, i.e. only camera distance, static in time. A twinned crystal also has a real optical signature: alternate twin lamellae flash at different crystal angles (albite twinning).
- Tactic 3 (promote an intermediate): `twin` is computed per fold and thrown away (R2 makes it real); world `p` at every march step and at the hit is already available and gives the radius from the forge centre; `g_seam` is the weld mask.
- Tactic 6 (history): C is not read; A = display RGBA (unchanged). No history idea.
- Measured while diagnosing: `g_seam = min((plane+edge)/scale)` is tiny nearly everywhere at the finest generation (plane+edge is in scaled coordinates, /34), so the weld glow is a near-uniform gold dusting rather than lines; I leave that look alone (identity) and ride it.

RESCUES (documented as such, not ideas)
- R1 **fly-through never returns**: `ro.z = -8 + 2*time` — measured at HEAD: t=0..3 fly in (blob fills frame at t≈2.5), t≈3.5..4.7 camera INSIDE the solid (flat beige, stdL 0), t>=5 camera is past the mass forever → permanently blank dark purple (meanL 0.065, stdL 0, meanA 0.000 at t=5,6,8,12,30). The shader is blank after 5 s of any session. Fix: the dolly breathes (cosine, period 12.6 s) between z=-8 (HEAD's start frame, identical at t=0) and a stand-off that scales with the density slider (blob radius ≈ 3.5·density, solid out to ≈ 4·density·… measured) so the camera never enters the solid.
- R2 **dead twin facets (HEAD idea 1)**: `twin = f32(i & 1)` is assigned every iteration, so the value returned is always `f32(5 & 1) = 1.0` → `twinTint` is always twinB (orange), the cool/warm twin split never existed. Replaced by the reflection-parity of the fold loop (count of `p.x<0`, `p.y<0`, `p.z<0` before each `abs`, mod 2) — this is §12.2E "fold count as material" used to restore the existing idea, not a new idea.

ADD (2 ideas)
1. **Hammer-strike heat front with cooling tail** (tactic 2, arrival-gated wave, not a §12.2 row) — a spherical front leaves the forge centre every 4.5 s (`front = fract(time*0.22)*Rmax`, `Rmax ∝ density`); world radius `length(p)` at each march step / at the hit decides arrival. Weld glow and the blackbody seam-fog heat are boosted at the front (gaussian shell) and decay behind it (cooling tail, envelope fades before the wrap so there is no pop). Bass/treble keep their HEAD roles; no new param.
2. **Albite twin flash** (tactic 5, device artifact: twin lamellae flash alternately as the crystal turns) — the specular half-vector is tilted ±δ about the facet's dominant axis by the (now live) twin parity, so the two twin domains catch the key light at different instants as the mass rotates; weighted like the existing spec (treble keeps its role).

FORMULA ADMISSION: R2 uses the §12.2E fold-count row (family: KIFS — row names KIFS explicitly), consumes `p` reflection signs already inside the loop, deletion leaves HEAD's constant tint. Ideas 1–2 use no §12.2 row; idea 2 consumes R2's parity + the existing half-vector, idea 1 consumes `g_seam`, world `p`, the existing blackbody ramp.
FORBID: springs/ripples, IQ palette, new params, changing the fold offset/scale/rotation (the identity), changing the iridescent baseCol or blackbody ramp constants.
A PACKING: ACES display RGBA (unchanged).

---

## 2. SHADER: gen-resonant-quantum-obsidian-scarab-engine

IDENTITY: a black obsidian KIFS carapace with glowing cyan breathing torus core; plate seams carry the core's pulse outward; the core shows in the glass and leaks between plates.

KEEP VERBATIM: 4 slider roles (x complexity → fold offset `0.5*x`, y plasma intensity, z reflectivity, w core pulse rate); torus core (`sdTorus` with `1+0.2 sin(t*rate)`), 4-iteration KIFS with its in-place x/y shear (replayed in `scarabPlates`; geometry stays), `smin(…,0.5)`; the three existing ideas (plate seams + breath wave, plasma mirror, corona); mouse offset of the core `(2mx, 2my)`; temporal feedback mix 5%; chromatic aberration; dust; ACES; A = display RGBA.

MECHANISM INTERROGATION
- Tactic 2: a polished carapace has wet joints — hydraulic fluid pools where two plates meet (concave) and the convex crowns are worn bright. HEAD's seams are lit but the *valley itself* has no material change.
- Tactic 2 / 8 (energy): the core breathes (`1+0.2 sin(t·rate)` torus radius) and the seam wave is delayed from it, but the shell it sits in is rigid. A breathing engine flexes its shell by the same pulse.
- Tactic 3: `sin(u.config.x*corePulseRate)` is already evaluated inside `map()` for the torus — the same scalar can drive the shell with no extra transcendental.
- Tactic 6: C is read as colour history (5%); no new history idea.

RESCUES
- R1 **upside-down camera / inverted pointer**: `rd = normalize(vec3(uv,1))` with `uv.y` increasing DOWN the screen, so world +y is screen-down. The core centre is `p.y += mouse.y*2` → moving the pointer down moves the core UP (measured: pointer y=0.1 core low, y=0.9 core top), and the key light `(2,4,-2)` lights the carapace from below. Fix: `rd.y = -uv.y` (world +y up). Pointer x unchanged; pointer y now natural; idle cursor puts the core at lower-right instead of upper-right (default composition changes — stated, not hidden). All replays (`scarabPlates`, `coreDist`) use world coordinates and are untouched.

ADD (2–3 ideas)
1. **Joint-fluid curvature** (§12.2E "SDF curvature") — 6 map() taps at the hit: `κ = (Σ d(p±e·axis) − 6d)/e²`, e = 0.012. Concave (κ<0) creases where bead spheres meet carry a thin wet film: the diffuse is darkened toward black and the specular exponent tightens (32 → 96) with a faint cyan core reflection; convex crowns (κ>0) get a worn edge polish term on the spec. Native: it is the valley the carapace plates already have.
2. **Carapace flex** (tactic 2/8) — the KIFS fold offset is scaled by `1 + 0.08*sin(t*rate)` in `map()` and in the `scarabPlates` replay (same scalar as the torus pulse; the seam wave delay stays measured from `corePos`). Shell and core breathe in the same cycle; amplitude 8% of the offset, bass already modulates the rate.
3. (optional, decided from renders) **Snowflake-obsidian spherulites** — per-plate radial blotches from `plates.y` and the folded coordinate on the existing plate shell; only if it reads as obsidian not noise.

FORMULA ADMISSION: curvature row — family: raymarched hard-surface SDF (the row's "hard-surface SDFs, crystals" fits an SDF carapace); consumes `map()` the file already owns; deletion leaves HEAD obsidian. Idea 2 is tactic-derived (no row).
FORBID: springs, ripples, IQ palette, new params, changing the KIFS shear, replacing obsidian with chrome, thin-film "rainbow obsidian".
A PACKING: ACES display RGBA (unchanged, C read as colour at 5%).

---

## 3. SHADER: gen-kryonic-quantum-aether-fractal-core

IDENTITY: a frozen fold-fractal (sorted-abs fold, scale s, 5 iterations) glowing with aether fog, frost-rimed at its tips, cracked with plasma veins along the fold planes, melting into a smooth sphere under the pointer.

KEEP VERBATIM: 4 slider roles (x fractal scale, y shatter, z glow, w thermal melt); `fold()` + the 5-iteration loop and the `length(q)/scale_factor - 0.02` DE; shatter noise term; the `smin` melt sphere under the pointer; mouse orbit rotation; the two existing ideas (frost-rime orbit trap, aether shatter veins) and `foldTraps`; display chain; A = display RGBA.

MECHANISM INTERROGATION
- Tactic 3: `fold()` sorts axes with up to three swaps per iteration; the number of swaps/reflections a point went through is computed implicitly and thrown away. Frozen water's grade follows how often it was fractured.
- Tactic 2: ice edges are thin and let light through (translucent ridges) while thick flanks are opaque; curvature is what separates them. Meltwater: where ice melts, a wet meniscus forms at the blend between the fractal and the melt sphere.
- Tactic 3 again: `smin`'s blend weight `h` (how far into the melt blend a point is) is computed inside `map()` and only used to bend the distance.
- Tactic 6: C not read; A = display RGBA. No history idea.

RESCUES (measured at HEAD, default 0.5 x4, idle cursor)
- R1 **scale < 1 collapses the fractal**: the app feeds `zoom_params.x = 0.5` (no top-level params), so `s = 0.5` — the fold *contracts*, `scale_factor = 0.5^5`, the DE is inflated 32x and the march steps through everything. The default picture is a smooth cyan disc with a few hairlines (meanL 0.52, stdL 0.24 but no fractal). The authored default is 1.5 (x-meta, shader comment `// default 1.5`). Fix inside the shader without touching JSON: `s = 1 + scale` (domain [1.5, 6] for the authored [0.5, 5] range), so the fed 0.5 gives the authored 1.5 fractal. Saved JSON untouched; flagged as a mapping change in NOTES.
- R2 **step-count glow wash**: `glow += 0.02*…/(1+d²·50)` adds a full term per march step, and steps shrink toward surfaces, so up to 80 steps near a surface saturate the cyan (meanL 0.71–0.81, stdL 0.07 at s=1.5). Fix: weight by the step length (`dt`, as the scarab corona does) so haze depends on distance travelled, not step count.
- (R3 idle-cursor melt: the idle cursor parks at 0.5,0.5 = frame centre, so the thermal melt sphere always swallows the middle. Decision after renders; the hover melt itself is native and stays.)

ADD (3 ideas)
1. **Fold-count ice grade** (§12.2E fold count as material) — `foldTraps` also counts swaps in a replay of `fold()`; few folds = clear glacial ice (deeper blue, tighter spec, stronger Fresnel), many folds = fractured white snow-ice (opaque, broad spec). Material, not colour wash.
2. **Ridge translucency** (§12.2E SDF curvature) — 6 taps at the hit; convex ridges (κ>0) let the aether core light through: warm-cyan emissive rim ∝ clamp(κ)·back-light; thick flanks stay opaque.
3. **Meltwater sheen** (tactic 3) — at the hit, blend weight `h` of the melt smin (call map once with melt = 0 for the pure fractal distance) becomes a wet mask: tight highlight + slight darkening where ice is turning to water, only inside the hover melt zone (it is zero elsewhere, so idle cursor look only changes at the melt rim).

FORMULA ADMISSION: fold-count row — family: kaleidoscopic fold fractal (the row names KIFS/Menger/kaleidoscopic SDFs; this is a sorted-abs fold IFS); consumes the fold loop; deletion leaves HEAD's rime/veins. Curvature row — fractal SDF surface the file already marches. Idea 3 is tactic-derived. Orbit trap is NOT used (HEAD owns it).
FORBID: a second orbit trap, springs/ripples, IQ palette, new params, touching the frost-rime or vein constants.
A PACKING: ACES display RGBA (unchanged).

---

## Revisions made during implementation (cards above were written first; these are the deviations, with the measurement that forced each)

- **Forge idea 1** first shipped as a radial front from the forge centre: every visible surface point sits at nearly the same radius, so it flashed the whole mass white at once (measured: meanL 0.31–0.66 whiteouts at t=3, 8, 30). Reworked to a point strike on the camera-facing side (spherical front around the strike point, 4.5 s cycle) — the front now crosses the visible surface as a spreading flare. Idea 2 (the "weld-scale quench shoulder") was dropped before coding: g_seam is ≈0.01 everywhere at the finest generation so there is no line to put a shoulder next to; replaced by the albite twin flash that is on the card above.
- **Kryonic R2**: the card's "step-count glow wash" was wrong. Re-weighting glow by step length (K = 0.4 / 0.8 / 1.6) left meanL/stdL unchanged (0.75 / 0.07): the wash comes from the rim term `(1 - n.z)`, which the camera at -z turns into a camera-FACING term (x2 on face-on surfaces). R2 is now the rim fix (`1 - max(dot(n, -rd), 0)`), the glow loop is untouched.
- **Kryonic R3 (idle-cursor melt)**: left alone. With R1/R2 the parked cursor melts the middle into a smooth dark-blue cavity inside a visible fractal rosette; that reads as the Thermal Melt effect, not a bug, and is where idea 5 (meltwater sheen) acts.
- **Kryonic fold-count thresholds**: first draft `smoothstep(8,22,folds)` saturated (measured fold count p10 18.8 / median 21.8 / p98 23.6); now `smoothstep(17.5, 23, folds)`. Idea strengths were raised after measuring (grade 50% of pixels >20/255 changed at first draft strength 0 → 2% only; final: ice grade ~50%, ridge ~14%, wet ~9% of pixels differ by >20/255 at idle cursor, 288 px, t=3).
- **Scarab**: only 2 ideas shipped (joint fluid, carapace flex); the optional snowflake-obsidian idea was not needed and was not written. Curvature probe radius changed 0.012 → 0.04 after a κ debug render (0.012 only found hairlines on the seams; 0.04 resolves the valleys between plate layers). Strength raised once (wet highlight exponent 160 → 48, weight 1.5 → 2.5, core-mirror weight x1.2 → x2.5) because the first version was invisible at 384 px even brightened x2.2.
- **Idea numbering**: HEAD already used `Idea 1..4` (forge), `IDEA 1..3` (scarab), `Idea 1..2` (kryonic) in comments, so new comments continue the numbering (forge 5–6, scarab 4–5, kryonic 3–5).
