# sonnet/batch-22 — fork D notes

Files touched (only these): `public/shaders/gen-chromatic-singularity-loom.wgsl`, `public/shaders/gen-sentient-holographic-neuro-lace-matrix.wgsl`, this notes dir. No JSON edits (no new audio/mouse claim, `params` byte-exact, lace JSON description already long — left alone). No commits, no generated lists, no ledger.
Idea numbering continues the in-file `// Idea n` comments (loom had 1–5, lace had 1–7), so BRIEFS' "ADD 1/2" are Idea 6/7 (loom) and Idea 8/9 (lace) in the WGSL.

---

## gen-chromatic-singularity-loom (2nd pass)

KEPT VERBATIM: 4 params + roles (x = mass + primary intensity, y = fold count + weave rate, z = accretion bloom + detail pow, w = chromatic shift + mouse influence — HEAD's dual use untouched); `map()` untouched (1/r² warp, tidal thread neck, continuous folds, parity flips, sphere union); Lipschitz-relaxed march + late-hit slack; cos palette on hit z + time + family phase; tidal striation/heat; shear bands; photon ring; `applyGenerativePrimaryControls`; depth write; decay constants, 1.012 infall push, max-composite.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha in A, C read as the same domain (unchanged, still truthful).

IDEAS IN THE DIFF (formula names: none are §12.2 rows → 0 rows used)
- Idea 6 relativistic Doppler beaming + gravitational redshift — lines 176–205 (D = 1/(1+β cos az), β = 0.5/√r; full D² on the additive orbiting emission: bloom, shear bands (l.250), photon ring (l.255); half strength on the sphere face `dopplerBody` l.193/244; hue-only luma-normalised tints; redshift `g = √(1 − 0.5/r)` hue-only on `c_shift` l.205). Approaching limb is x<0 (the shear bands rotate toward +azimuth).
- Idea 7 chord-length emission profile — lines 225–241 (4-tap tetrahedral normal from the file's own `map()`, threads only, hit pixels only; `body *= 0.35 + 0.65·√|n·v|`).
RESCUE R1 infall-trail copies — lines 264–283. HEAD stepped `0.035/(rr+0.15)` rad/frame with nearest loads (4–14 px/frame at 192–576 px) → ~10 stacked rotated copies with sawtooth edges merging into filled polygons ("blocky streaks"); history disabled in a scratch copy = crisp weave. Now `0.014/(rr+0.15)`, bilinear reconstruction of the same exact `textureLoad`s, and the total history displacement is capped at 3 px/frame (the step is angular, so without the cap it was ~6 px at 576 px and ~11 px at 1080p and the stacked copies came back at high resolution). Decay, push, packing unchanged. A few small sawtooth patches remain at 576 px near thread corners (moved-cursor frame, top-right) — open item.
Not found: per-block hash mosaic, early return on C≈0, ACES-on-ACES (A is pre-ACES, C read in the same domain), upside-down camera (y already flipped at HEAD), camera inside SDF.

DEFAULT-LOOK CHANGE: YES (rescue + redshift tint). 576 px idle, t 2–5, params 0.5×4: meanL 0.549 → 0.447, stdL 0.124 → 0.191, meanA 0.578 → 0.476 (cleaner weave, more contrast; sphere/inner threads shift lime → yellow-green by the redshift: sphere mean B 0.52 → 0.44). 192 px with audio (0.4,0.3,0.2): meanL 0.599 → 0.538, stdL 0.100 → 0.151, meanA 0.689 → 0.621. Moved cursor (0.3,0.4) + audio at 576 px, T0=10: meanL 0.607 → 0.493, stdL 0.086 → 0.171, meanA 0.695 → 0.597. NaN 0 everywhere.
Doppler asymmetry is a bias, not a spectacle, at default: left/right mean luminance ratio 1.06 on the sphere disc and 1.13 on the surrounding ring (HEAD 0.99/1.00); larger on the shear bands/ring under audio and when the camera is nearer the limb, compressed by the tone curve on the sphere. Not claimed as a strong visual.
GATES: wgsl_precommit_gate pass (naga OK, bindgroup compatible, extraBuffer 0), `audit:extrabuffer` pass, `audit:dead-sliders` 0 new (all four sliders still read: l.14/16/18/38/64/68/173/207).
TIMING: 5 interleaved HEAD/cur pairs at 192 px, 24 frames, load average ≈ 20 (other forks): HEAD 164/157/387/270/181 ms, cur 167/399/304/333/152 ms. Pairwise ratios 1.02/2.5/0.79/1.23/0.84 — load noise dominates; min-of-5 157 vs 152 ms. The only added per-pixel work is 4 `map()` calls on thread hits (≈ 3–7 % of a march). Coordinator should re-time at low load.
OPEN: HG / energy-conserving-bloom (Fork D budget) deliberately unused — HG on the loom's `bloom` (≈ 0.07 at r = 1) is invisible. `params.w` still doubles as chromatic shift and mouse influence (HEAD).

---

## gen-sentient-holographic-neuro-lace-matrix (2 new ideas; cap respected)

KEPT VERBATIM: 4 params + roles (x scale, y colorShift, z flight/wave speed, w specular); gyroid DE + breathing wave; pull node, hover/held behaviour; step-count AO; bioluminescent haze/fog; node glow; vortex loops (shape + colour); bead colour, amplitude gate `0.1 + mids·0.2`, `strand` mask; holographic scanline overlay; block glitches; camera path (`ro.z = −3 − t·z·0.5`, rd +z); ACES display; all 7 existing ideas.
A PACKING: ACES display RGBA (alpha = fogged lace coverage raised by node glow); C not read (unchanged).

IDEAS IN THE DIFF (0 §12.2 rows)
- Idea 8 scan-lit lace with trailing wake — lines 197–206 (+ `laceLit` carried out of the hit block l.132/144). Bar over the void is HEAD's flat bar; over the lace it is modulated by `diffuse·AO + spec/2`; exponential afterglow `exp(−(0.95 − phase)·9)` trails above the sweep (the bar moves down-screen).
- Idea 9 saltatory conduction with refractory tail — lines 158–170. Same internode length (2π/16 along z) and mean speed (0.25 u/s) as HEAD; time quantised through `floor + smoothstep(0.55, 1)` (dwell then hop); bead = sharp front (`smoothstep(0, 0.05, lag)`) × `exp(−7·lag)`, normalised ×1.4 to HEAD's peak; refractory dip `col *= 1 − 0.15·refractory·strand`.
RESCUE R1 audio-multiplied time phases — l.153–155 (vortex loops) and l.163–165 (beads). HEAD: `t·(5 + 3·bass)` and `t·(4 + 2.5·bass)` — any bass change moved the phase by tens of radians, so loops/beads strobed with the music. Constant rates now; the audio keeps its amplitude role. At silence the loops are bit-identical; the beads change by Idea 9 only.
Not found at HEAD (576 px idle + held + audio): NaN, blank/inverted frame, camera inside lace; black region right of centre is the real open channel axis (fogged-out rays), HEAD's design.
OPEN (not changed): `ro.z` decreases while `rd.z = +1` → the camera moves backwards relative to its view; the lace is z-homogeneous so stills cannot show it. Flipping it changes the whole motion feel and the wave-vs-camera closing speed — left for a decision.

DEFAULT-LOOK CHANGE: small. 576 px idle, t 2–3, params 0.5,0.5,1,1: meanL 0.250 → 0.243, stdL 0.178 → 0.170, meanA 0.877 → 0.877. Held cursor (0.35,0.4) + audio (0.6,0.4,0.2): meanL 0.290 → 0.286, stdL 0.182 → 0.178. 192 px with audio: 0.221/0.187 → 0.220/0.187. Visible change: a soft cyan wake behind each scan bar that reveals lace structure, and bead arcs with tails.
GATES: precommit gate pass (naga OK), extraBuffer audit pass, dead-sliders 0 new (all four sliders still read: l.55/61/95/127/138). No per-pixel cost added to the march (changes are post-hit scalar math).
