# sonnet/batch-20 — coordinator cards (shaders 4, 5, 6, 7: topological-acoustic-knots, acoustic-string-theory, gen-string-theory, gen-audio-spirograph)

Fork A (gen-grokcf-interference, gen-void-harmonic-cymatic-resonator, gen-stellar-acoustic-resonance-manifold) and Fork B (gen-quantum-superposition, gen-quantum-resonance-lattice, gen-acid-lissajous) write BRIEFS-forkA.md / BRIEFS-forkB.md.

Theme: wave interference, resonance, cymatics. Family: generative (§12.2E) + optical (§12.2F) + wave/sim (§12.2D) — ideas must extend each file's own wave/oscillator vocabulary.

Pre-state (minirender 192px, 24–90 frames, JSON defaults): see baseline/ montage. topological-acoustic-knots is BLACK with any audio ≥0.1 (meanA 0.004 at 0.1, 0 at 0.3+); grey slab in silence.

---

## SHADER: topological-acoustic-knots  (1st pass — no `Ideas:` at HEAD; RESCUE)

IDENTITY: a nematic liquid-crystal film under a polarizing microscope — Q-tensor director field with ±½/±1 disclination cores, a trefoil-knot constraint, schlieren brushes, bass quench nucleates defect pairs, mouse pins the director radially.

KEEP VERBATIM: 4 params and roles (p1 quench amplitude/defect density, p2 mobility, p3 annihilation + knot influence, p4 mouse anchor strength); A = SIGNED Q state (Qxx, Qxy, S, defectDensity) — never tonemapped; trefoilSDF; phonon (treble); homeotropic mouse anchor; ripple-spawned loops; annihilation (opposite-sign pair melts the core); red-integer / blue-half-integer core colours; +1 HDR bloom; chromatic aberration; ACES on display; alpha = S·(1+0.6·defect)·0.7; depth = defect·0.8+S·0.2.

MECHANISM INTERROGATION:
- tactic 2 (physics one step further): a nematic film is read through crossed polarizers; extinction brushes are sin²(2(θ−φ)) so a ±½ core shows 2 brushes and ±1 shows 4. HEAD used a single-polarizer term 1−cos²(θ−φ), giving one brush per core and no brush-count signature. The same instrument also shows birefringence colours (retardance Γ = Δn·d, Δn ∝ S).
- tactic 3 (promote an intermediate): `knotDist` and `S` are already computed and thrown away for colour; reuse them as the cell wedge and the order-dependent birefringence.
- tactic 6 (history the shader owns): C is read as a SIGNED field (Qxx, Qxy, S) — so the right read is exact textureLoad and a true Q→angle decode.
- tactic 4 (second-order the parameter): the quench noise amplitude `bass·0.18·(0.5+p1)` is white and temporally constant; the Kibble–Zurek noise is correlated and grows where order is low.

FLOOR / RESCUE (not counted as ideas — they are why the file shows nothing at HEAD):
 R1  S melt was an absolute per-frame subtraction (`S = relaxS − |disorder|`) against a 3 %/frame relaxation, so any bass > ~0.08 pinned S at 0 (alpha ≡ 0 → black). Now a fractional rate.
 R2  C was read with the FILTERING sampler at uv = gid/res (no +0.5): half-texel bilinear drift/blur of a signed field, and `n.r*2.0` treated Qxx as a director ANGLE. Now exact textureLoad + θ = ½·atan2(2Qxy, 2Qxx − S/3), S-weighted Q averaging, wrapped relaxation.
 R3  "charge" was d(Qxx)/dx-type, not a winding number. Now an 8-point plaquette winding Σwrap(Δθ)/2π → ±½ / ±1 (the red/blue colouring and +1 bloom now mean what they say).
 R4  Polarizer sweep (extraBuffer[136]) and cascade pulse (extraBuffer[135]) lived in zeroed-every-frame slots → never ran. Polarizer is now a stateless time + mids function; the pulse is a local annihilation flash.
 R5  Ripple age mixed ×0.8 time with raw start time. Bounds guard + centred uv added.

ADD (3 native ideas):
 1. Crossed-polarizer extinction brushes — I = sin²(2(θ−φ)) with the sweeping polarizer φ: 2 brushes at ±½ cores, 4 at ±1. Extends the existing schlieren term (same polarizer sweep, same director).
 2. Birefringence retardance tint (Michel–Lévy) — Γ = S·(d₀ + d·wedge(knotDist)); per-channel sin²(πΓ/λ) (650/550/450 nm). Melted cores (S→0) go isotropic-black; the trefoil shows up as a thickness wedge. Not the thin-film row (§12.2F) as an overlay: this is the polarized-microscopy artifact of the very device the file imitates.
 3. Kibble–Zurek correlated quench noise ∝ (1−S) — smooth value noise (≈1/23 screen cells) plus a pixel nucleation term replaces per-pixel white noise, amplitude grows where order is low (isotropic quench → domains freeze → defects remain).
FORMULAE: none from the §12.2 table (tactic-derived); idea 2 shares the sin²(phase) form with F "Thin-film phase" but is not an overlay.
FORBID: springs, IQ palettes, new params, ripple shock rings, tone-mapping A, changing the Q packing.
A PACKING: raw sim state (Qxx, Qxy, S, defectDensity) — unchanged; ACES on writeTexture only.

---

## SHADER: acoustic-string-theory  (1st pass — no `Ideas:` at HEAD; RESCUE of the Interactivist pass)
(Process note: this card was written while iterating on the render — the state rescue was designed first from the code read, the three ideas were fixed on the card before the renders, and pin size / ratio set were tuned afterwards. Honest order: code read → card → code.)

IDENTITY: a bank of plucked strings drawn as interfering standing/travelling waves with overtone lines, node glints, a spring-damped gravity well that bends string space under the cursor, a click that plucks the nearest string, spectrum-driven loudness.

KEEP VERBATIM: 4 params and roles (strings count / tension / harmonics / resonance); string + harmonic contour fields; bandWeight spectrum drive; bass envelope; node glints + treble sparkle; well spring constants (stiff 42, damping 7); click shock ring; pluck gaussian + decay `1.2 + 1.6·tension`; video-luma boost; ACES on display; alpha / depth formulas; A = (bass env, harmonicField, nodeField, alpha).

MECHANISM INTERROGATION:
- tactic 2 (physics one step further): a plucked string (a) stretches, so pitch starts sharp and glides down as amplitude decays; (b) drives open strings that share a low-integer partial ratio (sympathetic resonance — the shader's own slider is called "Resonance").
- tactic 3 (promote an intermediate): each string already carries `tension·(1+0.15·fs)` as its wavenumber; the nodes of that wave are free.
- tactic 6 (history the shader owns): its state (well pos/vel, last pluck) lived in extraBuffer[133..141], zeroed by the host every frame → never ran.

FLOOR / RESCUE:
 R1  Spring well + pluck state: extraBuffer[133..141] is overwritten with zeros each frame (writeExtraBuffer uploads the whole scratch) → well pinned at (0,0), pluckAmp ≡ 0, click shock centred at (0,0). Now: well pos/vel in A texels (0,0), lastTime + sentinel in (1,0); pluck = newest ripple in `u.ripples` (a click spawns one) – stateless.
 R2  `dt` was `clamp(u.config.y, …)` = the ripple count. Now dt from the stored last time.
 R3  `normalize(d)` of a zero vector (odd widths, well exactly on a pixel) → NaN; guarded.
 R4  C read exact (textureLoad) instead of sampleLevel; bass envelope read from texel (2,0) so the state texels never leak into it.
 Not changed: A.rgb being (bass, harmonicField, nodeField) is mixed into the colour as a 3–4.5 % trail — HEAD behaviour, documented on the `A packing:` line.

ADD (3 native ideas):
 1. Sympathetic resonance — string i is excited when (2+0.5i)/(2+0.5·struck) sits on 2:1, 3:2, 4:3, 5:4, 5:3 etc.; amplitude swells in over ≈0.15 s and spans the whole string (broad gaussian), scaled by the pluck envelope.
 2. Tension-modulation pitch glide — closed-form chirp `age + g(1−e^{−k·age})/k` replaces `age` in the ring phase, k = the pluck decay constant (pitch tracks amplitude); no state.
 3. Standing-wave nodal pins — zeros of sin(k_i x) with the string's own k_i, drawn as pins on the string row; brighten with mids and with sympathy. (Idle-visible; the other two act after a click.)
FORMULAE: none from §12.2 (tactic-derived).
FORBID: new params, springs beyond HEAD's, IQ palette, changing string / harmonic contour construction.
A PACKING: as HEAD + two state texels (0,0), (1,0) with sentinel 0.7371.

---

## SHADER: gen-string-theory  (2nd pass — HEAD Ideas: stiff-string inharmonicity; bridge reflection of the pluck)

IDENTITY: five rotated vibrating strings, each a sum of standing harmonics (sin(kx)·cos(ωt)) with a travelling term and a mouse pluck kink, hue-coloured partials, chromatic aberration, temporal trail, click resonance shells.

KEEP VERBATIM: 4 params and roles (fundamental / harmonic richness / damping / pluck strength); the partial series with HEAD's inharmonicity; bridge-reflection pluck; per-partial hue table; thin core + glow + sin(dist) ripple; chromatic aberration; background resonance / interference / bloom overlays; click shells; persistence trail `max(col, prev·0.4)`; ACES; A = display RGBA.

MECHANISM INTERROGATION:
- tactic 5 (artifact of the real device): a vibrating string photographed with a long exposure (Melde's experiment) is a lens-shaped ghost whose edges are brightest — the arcsine dwell of a sinusoidal oscillator. The shader draws only the instantaneous curve.
- tactic 4 (second-order the pluck): pressing the pointer is currently "pluck harder"; a held finger on a real string is a fret — it pins a node and the two sides ring as shorter, higher strings.
- tactic 3 (promote an intermediate): `amp·damp·|sin(kx)|` is already computed inside the partial loop — its sum is the envelope E(x).
- tactic 6: the sprung cursor (extraBuffer[133..138]) is zeroed every frame → cursor was the raw pointer.

FLOOR / RESCUE:
 R1  Sprung cursor state → A texels (0,0) pos/vel, (1,0) lastTime + sentinel (extraBuffer[133..138] never persisted). Trail read zeroed on those two texels.
 R2  JSON has no top-level `params` (only x-meta) → the app showed no sliders and fed 0.5 ×4. Added `params` mirroring x-meta.upgrade.params (ids/defaults 0.5, 0.6, 0.85, 0.5).

ADD (2 native ideas):
 1. Melde long-exposure envelope with arcsine dwell — E(x)=Σ 2·amp·damp·|sin(kx)| accumulated in the existing partial loop; ghost density ∝ 1/√(E²−y²) inside ±E, coloured by the strings' own partial colour; the pluck kink widens it.
 2. Fretting finger — while pressed, the string nearest the pointer is stopped at the pointer: x is remapped so each side behaves as its own shorter string (nodes pinned at the finger, pitch up by the length ratio); weight = pressed · proximity.
FORMULAE: none from §12.2.
FORBID: new params, springs beyond the HEAD cursor spring, IQ palette, changing partial construction, touching HEAD's two ideas.
A PACKING: display RGBA (unchanged) + two state texels (0,0), (1,0).

---

## SHADER: gen-audio-spirograph  (2nd pass — HEAD Ideas: additive gear glow; rolling-center hubs; stator ghost; cusp flash)

IDENTITY: a bank of epi/hypotrochoid spirograph curves drawn as 12-segment pen trails, audio-breathing pen arm length d, musical-ratio gear sizes, hue-cycling colour, accumulated history.

KEEP VERBATIM: 4 params and roles (base frequency / audio reactivity / trail length / line thickness); epi/hypotrochoid parameterisations and per-curve R, r, d; segment-sweep trail construction; additive gear glow; hubs, stator ghost, cusp flash; click chime shells; geo ring; history accumulation `col + prev·trail·0.78`; vignette; A = history RGB + coverage (HDR history read back as C colour), ACES on display only.

MECHANISM INTERROGATION:
- tactic 5 (artifact of the real device): a spirograph is a *mechanism* — a pen arm fixed to a rolling gear that meshes with a fixed ring. HEAD draws the pen's path, the fixed ring (stator ghost) and the hub dot, but never the rolling gear or the arm.
- tactic 2 (physics one step further): a no-slip rolling gear has teeth counts in ratio R : r and its teeth ticks rotate with the gear.
- tactic 3 (promote an intermediate): per-segment length (pen speed) is already computed in the nearest-segment search — ink pools where the pen is slow.
- tactic 6: the sprung lens (extraBuffer[133..138]) is zeroed each frame.

FLOOR / RESCUE:
 R1  Sprung mouse lens state → A texels (0,0)/(1,0) with sentinel; history read zeroed on those two corner texels (outside the vignette).
 Note: spirograph HDR history in A is already honest; ACES only on writeTexture.

ADD (3 native ideas):
 1. Rolling gear + pen arm — for the five epitrochoids draw the rolling circle (radius r, centre = the existing hub) and the arm from hub to the pen point (length d·audioMod, already breathing with audio): the mechanism that makes the curve, in the curve's hue.
 2. No-slip gear teeth — ticks on the rolling circle at N = 2πr/pitch teeth, phase locked to (k+1)·t (the gear's own rotation); the stator ring gets N·R/r teeth, so the teeth visibly mesh.
 3. Ink pooling by pen speed — the nearest segment's length gives the pen speed; ink weight ∝ 1/speed (clamped) so cusps and slow arcs pool brighter, fast sweeps go thin. Complementary to HEAD's cusp flash (flash = reversal event, pooling = continuous dwell).
FORMULAE: none from §12.2.
FORBID: springs/lens beyond the HEAD one, IQ palette, extra curves, changing the trail packing, hypotrochoid gears (kept as curves only).
A PACKING: history RGB + coverage (unchanged) + two state texels (0,0), (1,0).
