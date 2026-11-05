# Sonnet batch 19 — polyhedra, tiling and topology ten — Idea Cards (written before any WGSL edit)

Batch: `claude-2026-11-01-sonnet-batch-19` · 2026-11-01 · explicit list from the task (sonnet/batch-19): gen-aperiodic-monotile, gen-islamic-star-rose, gen-quasicrystal,
gen-quasicrystal-iridescence, gen-hopf-fibration-fiber-bundle, gen-neon-stellated-octahedron, gen-rainbow-icosahedron-cascade, gen-chromatic-zonohedron,
gen-hyper-dimensional-tesseract-labyrinth, gen-fourier-epicycles. Theme: geometric (polytopes, tilings, fibrations, harmonic circles): ideas are the geometry's own
vocabulary (vertices, struts, support functions, inflation levels, star polygons, perspective). None is multipass.
Ledger: gen-aperiodic-monotile 2026-10-11, gen-islamic-star-rose 2026-10-12, gen-hopf-fibration-fiber-bundle 2026-10-12 and 2026-10-17 (third pass),
gen-chromatic-zonohedron 2026-10-12, gen-hyper-dimensional-tesseract-labyrinth 2026-10-17, gen-fourier-epicycles 2026-10-11; the other three have no event.
HEAD `Ideas:` lines are NOT re-added. Six files already include the prelude; four (quasicrystal ×2, neon-stellated-octahedron, rainbow-icosahedron-cascade) still paste it.
Pre-state: naga-wasm 10/10 valid on main. SwiftShader harness baseline measured (below).

## Findings that shape the cards

1. **gen-rainbow-icosahedron-cascade renders essentially nothing.** It builds `p = (uv·2.2, 2.8)`, rotates it, and evaluates a 3-D SDF of nested icosahedral shells at that single point — a plane 2.8 from the origin, farther than every shell's circumradius (0.55 … 1.15 at default). So every edge/facet/dual-spark term is ≈ 0. Measured on SwiftShader at default sliders: **display max 0.084, alpha max 0.002** (all nine others render: alpha mean 0.11–1.0). The "ideas" shipped in 2026-09-27 are therefore invisible. Its edge table is also wrong: of the icosahedron's 30 edges, six (0-2, 1-3, 4-6, 5-7, 8-10, 9-11) are missing and six others are listed twice ((8,2),(9,2),(10,3),(11,3),(4,1),(6,1) duplicate (2,8),(2,9),(3,10),(3,11),(1,4),(1,6)). Repair (floor, required before any idea can show): orthographic wire projection of the rotated vertices and 2-D segment distance (the shell/face/dual/core logic is kept), and the corrected edge table.
2. **gen-islamic-star-rose re-tonemaps its own history.** It stores ACES output in A, reads C as colour, mixes `prev·0.96` into the *pre-ACES* colour and applies ACES again, every frame — iterated tone-mapping. Measured on SwiftShader (30 frames): display range only 0.63 … 0.80 (mean 0.69), a washed grey. Packing fix (stated here per §8): A stores the **linear mix**, ACES applies on `writeTexture` only.
3. **gen-fourier-epicycles' "cusp ink" almost never fires.** It tests `exp(−penSpeed·2.4)` with `penSpeed = Σ|freq|·radius` — a sum of magnitudes (≥ ~1 at default), not the pen's velocity; the real velocity vanishes only at true cusps and is computable from the phases the loop already has.
4. gen-islamic-star-rose has no top-level `params` in its JSON (only `x-meta.upgrade.params`); sliders are `zoom_params.x..w` = complexity, rotation, zoom, colour shift. Left as is.
5. Third-pass restraint: gen-hopf-fibration-fiber-bundle already carries seven ideas and a 40×32 segment loop per pixel; its two additions are per-sample multipliers, no new loops.
6. Tone curves: all ten already use ACES.

---

## SHADER: gen-quasicrystal
IDENTITY: n-fold quasicrystal from layered plane-wave sums with gem Fresnel surfaces, Voronoi crackle, phason strain and Ammann bars, with a bass-envelope trail.
KEEP VERBATIM: 4 params (symmetry, density, colour cycle, projection angle); quasicrystal/quasicrystal2; phason field; Ammann bars; gem colours; trail in A (rgb) + bass envelope in A.a; B = pre-trail colour + bloom.
MECHANISM INTERROGATION: tactic 3 — `qc` (the plane-wave sum) is already computed: its maxima are the points where all n waves are in phase, i.e. the quasi-lattice vertices, which are never drawn. The phason field `ph` is known analytically; where it varies fastest the tiling is flipping.
ADD:
1. Lattice-node pinpoints — `smoothstep(0.82, 0.98, qc)` marks the constructive-interference maxima; small bright nodes (size tied to treble) show the quasi-lattice vertices the waves build.
2. Phason-strain energy glow — the finite-difference gradient magnitude of the slow strain noise (two extra noise pairs) lights a warm glow where tiles are flipping fastest.
FORBID: springs, new shockwaves, palettes.
A PACKING: unchanged — rgb = display trail, a = bass envelope; B pre-trail + bloom.
FLOOR: migrate pasted header.

## SHADER: gen-quasicrystal-iridescence
IDENTITY: 5..13-fold quasicrystal depth drives thin-film thickness, giving soap-bubble spectral colours with gold/silver/bronze base, Ammann lines and mouse-pressed film bumps.
KEEP VERBATIM: 4 params with their HEAD double mapping; quasicrystal with phason offsets; thin-film spectral integral; Fresnel mix; metals; Ammann lines; mouse bump; A = ACES display RGBA.
MECHANISM INTERROGATION: tactic 2 — a real soap film drains: it is thicker at the bottom than the top. And a film thinner than ~λ/4 is a black film (the two reflections cancel), not a bright one; HEAD's thinFilmColor never darkens at small thickness.
ADD:
1. Gravity drainage — film thickness × mix(0.72, 1.28, uv.y) (uv.y = 0 at the top, so the top is thin, the bottom thick).
2. Black-film fade — the interference term is faded to zero for thickness below ~140 nm (smoothstep 40 → 140), so the thinnest, highest regions go black as a draining soap film does.
FORBID: springs, new overlays.
A PACKING: unchanged — ACES display RGBA.
FLOOR: migrate pasted header.

## SHADER: gen-neon-stellated-octahedron
IDENTITY: a neon slice through the stella octangula (two tetrahedra) with a 6-fold kaleidoscope, solid section fills, Kepler cube frame and parity beacons.
KEEP VERBATIM: 4 params; tomographic slice; six-fold fold; stellatedOctaSDF; tetraSolid compound/core; Kepler hull + beacons; click slice dents; A = ACES display RGBA.
MECHANISM INTERROGATION: tactic 5 — a neon tube's glow is not a Gaussian: it has a white-hot core and a long 1/r² halo. Tactic 3 — `tetraSolid` takes the max of four face half-spaces; which of the four wins is the face the section boundary lies on, and it is discarded.
ADD:
1. Face-identity rim — the argmax of the four half-space distances for each tetrahedron names the boundary face; the section rim takes one of eight hues (4 faces × 2 tetrahedra).
2. Neon tube profile — a soft inverse-square halo 0.0015/(d² + 0.0006) around each edge tube plus a white-hot core exp(−|d|·300) (§12.2F soft inverse-square), added to the Gaussian glow.
FORBID: springs, extra shockwaves, new palettes.
A PACKING: unchanged — ACES display RGBA.
FLOOR: migrate pasted header.

## SHADER: gen-rainbow-icosahedron-cascade
IDENTITY: nested icosahedral wireframe shells with spectral edge glow, dual-dodecahedron sparks, silhouette orbit trap, click shell pulses; mouse orbits the structure.
KEEP VERBATIM: 4 params (shell count, spacing, edge glow, hue drift); icosahedron vertices and the face table; shell scale/gap/pulse logic; golden-angle yaw per shell; dual sparks; silhouette term; spectral palette; core glow; linear HDR history in A, ACES on writeTexture.
MECHANISM INTERROGATION: finding 1. Tactic 3 — a wireframe icosahedron has 12 five-fold vertices where five edges meet, and they are never marked (HEAD marks only the 20 three-fold face centres).
ADD:
1. Five-fold vertex beads — a bead at each of the 12 vertices of every shell (Gaussian in projected distance), brighter on the front side.
2. Signed depth cue — the nearest edge point's signed depth makes front edges brighter/warmer and back edges dimmer/cooler (HEAD's silhouette term is symmetric in z).
REPAIR (floor, required for any output): orthographic wire projection — rotate the vertices, take 2-D segment distance to the projected edges and 2-D distance to the projected dual centroids; corrected 30-edge table.
FORBID: springs, new overlays; keep the shells/dual/silhouette identity.
A PACKING: unchanged.
FLOOR: migrate pasted header.

## SHADER: gen-chromatic-zonohedron
IDENTITY: a spinning rhombic-zonohedron tiling projected to 2-D from four generator axes, jewel-coloured facets, neon edges, zone belts and vertex stars.
KEEP VERBATIM: 4 params; 4 generators; zonoSDF/zone/inset/diagonal/star; spectral hue lock; axis shade; shimmer; C blend; A = ACES display RGBA.
MECHANISM INTERROGATION: tactic 2 — a zonohedron is a Minkowski sum of segments, so its silhouette is the zonogon with support function h(n) = ½ Σ|a_k·n|: HEAD tiles the whole plane and has no outline. Tactic 7 — the generator directions are fixed 2-D vectors, so as the solid "spins" only the pattern turns in the plane; a real 3-D spin foreshortens the rhombs.
ADD:
1. Zonogon silhouette — the exact projected outline from the support function (8-gon for four generators), drawn as a bold gold edge, with the tiling outside it dimmed to 40 %.
2. Tumbling generators — the four axes are rotated about the screen x axis by 0.35·sin(0.3t) before projection (`y × cos tilt`), so rhombs foreshorten and breathe as a 3-D zonohedron would.
FORBID: springs, new palettes.
A PACKING: unchanged — ACES display RGBA.

## SHADER: gen-hopf-fibration-fiber-bundle
IDENTITY: 40 Hopf fibres (circles in S³) stereographically projected, with knot gaps, beads, S² inset, horizon, hot crossings.
KEEP VERBATIM: everything in HEAD (third pass: seven ideas stay).
MECHANISM INTERROGATION: tactic 2 — a tube seen in perspective gets thinner with distance; the glow radius here is constant in screen space although `depth4` (1/(2.5 + rz)) is computed per sample. Tactic 3 — the same `depth4` also gives aerial perspective.
ADD (per-sample multipliers only, no new loop):
1. Perspective tube thickness — glow radius × clamp(depth4 / 0.4, 0.55, 1.6) per segment.
2. Aerial cooling — distant strands (small `depth4`) shift toward a cool desaturated tint, near strands keep their fibre colour.
FORBID: new loops, springs, new overlays.
A PACKING: unchanged — ACES display RGBA.

## SHADER: gen-hyper-dimensional-tesseract-labyrinth
IDENTITY: a raymarched maze of 4-D-rotated glowing hypercube cells (frame, glass faces, W-slice ghost frame, corridor midplanes, parity cells).
KEEP VERBATIM: everything in HEAD; params as saved.
MECHANISM INTERROGATION: tactic 3/5 — a tesseract is two nested cubes joined by eight edges; here the main frame and the w-shifted ghost frame exist but are not connected. The fourth coordinate `q4.w` is used for the perspective divide and the ghost shift but not for colour; 4-D visualisations colour by w.
ADD:
1. Hyper-edge struts — eight capsules joining each main-frame corner to the corresponding ghost-frame corner (material 4, folded by the octant so one capsule is evaluated).
2. W-coordinate colour — the cell's `q4.w` (packed into the map's fourth output with the parity) tints the edge/ghost glow: warm for +w, cool for −w.
FORBID: springs, new loops in the march, palettes.
A PACKING: unchanged — ACES display RGBA.

## SHADER: gen-fourier-epicycles
IDENTITY: rotating epicycle chain with rim/arm glow, a glowing pen, a three-channel trail packed in A, mouse gravity well.
KEEP VERBATIM: 4 params; chain construction; rim/arm/tick/hub glow; pen glow; trail packing A = (bassEnv, trail.r, trail.g, alpha) and its read-back; gravity well; treble sparkle.
MECHANISM INTERROGATION: finding 3. Tactic 7 — a rotating wheel has a direction; the rim glow is uniform around each circle.
ADD:
1. True pen velocity — accumulate Σ freq·radius·(−sin phase, cos phase) in the loop (the pen's actual velocity), thin the pen ink with it (w = w0/(1 + k|v|), §12.2C speed-thinning) and drive the cusp blot from the real |v| (replaces the magnitude-sum bound).
2. Rim comets — each rim glow is weighted by a decaying tail behind the arm tip (angular distance behind the phase), so every wheel shows which way it turns.
FORBID: new packing, springs, palettes.
A PACKING: unchanged.

## SHADER: gen-aperiodic-monotile
IDENTITY: a hat-tiling-inspired hex-cell pattern (reflected hats, brim, notch, metatile outline, crown, substitution tint) plus a raymarched relief sculpture.
KEEP VERBATIM: everything in HEAD (stylized motif; relief; C blend).
MECHANISM INTERROGATION: tactic 3 — the cell's `localQ/R/S` are computed; the hat is a polykite (8 kites), and the hexagon's cube coordinates already give its kite seams. Tactic 2 — substitution tilings are hierarchical; HEAD marks one inflation level (the 4-cell metatile) only.
ADD:
1. Kite seams — thin lines where |dq − dr| / |dr − ds| / |ds − dq| vanish, the kite subdivision inside each hat.
2. Second-generation supertile outline — a fainter outline at the 16-cell level (`fract(hex_q·0.25)`), the next inflation.
FORBID: springs, new params, replacing the relief.
A PACKING: unchanged — ACES display RGBA.

## SHADER: gen-islamic-star-rose
IDENTITY: hex-cell girih tessellation of stars and n-gons with strapwork, nested φ pentagrams, a 10-fold rose, a central pentagram rosette.
KEEP VERBATIM: sliders (complexity, rotation, zoom, colour shift); hex tiling; star/n-gon selection; pentagram φ ratio; strapwork rings; nested star; rosette and rose; shadows; chromatic bias.
MECHANISM INTERROGATION: finding 2. Tactic 1 — a star polygon {n/2} has inner radius R·cos(2π/n)/cos(π/n); HEAD uses a fixed ratio 3/7 for every star that is not the 5-point one. Tactic 5 — strapwork bands interlace: they pass over and under the outline at crossings; here the rings run straight through the stars.
ADD:
1. True {n/2} star ratio — for stars with n ≠ 5 the inner radius is R·cos(2π/n)/cos(π/n) (clamped 0.2…0.9 for n = 4), so 6-, 7- and 8-point stars have their real proportions.
2. Interlace gaps — strapwork rings are suppressed (pushed 0.12 away) inside a shape, so each ring shows outside the star and is hidden inside it, alternating over/under at every crossing.
PACKING FIX (floor, stated): A stores the **linear** temporal mix; ACES only on writeTexture (HEAD tone-mapped its own history each frame).
FORBID: new params, springs, palettes.
A PACKING: **changed on purpose** — linear mix in A, read as C colour.

---

## Formula / mechanism ledger (≤ 2 files per §12.2 row)

| row / mechanism | files |
|---|---|
| F soft inverse-square | gen-neon-stellated-octahedron |
| F thin-film (existing mechanism, drainage + black film) | gen-quasicrystal-iridescence |
| C speed-thinning | gen-fourier-epicycles |
| Minkowski support function (zonogon) | gen-chromatic-zonohedron |
| star polygon {n/k} geometry | gen-islamic-star-rose |
| hierarchical inflation | gen-aperiodic-monotile |
| none (tactic-derived) | quasicrystal, rainbow-icosahedron-cascade, hopf, tesseract-labyrinth |
