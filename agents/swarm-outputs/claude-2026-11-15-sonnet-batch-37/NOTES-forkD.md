# NOTES — fork D (gen-chromatic-oracle-jelly, gen-liquid-cathedral-dream)

HEAD for every comparison = 8577b989 (these two files were not touched by the prelude commit). Both files were third-pass: their `Ideas:` lines were long and are appended to, not replaced. A packing on both = ACES display RGBA read back as colour history, **unchanged** (no new A channel, no new state, no new binding, no extraBuffer, no new param). JSON untouched (features/description/x-meta already correct; no tag would become newly true).

Harness notes: `agents/mr.mjs` defaults the four sliders to `[1,1,1,1]`, NOT the saved defaults, so every number below passes the saved defaults explicitly (jelly `0.5,0.55,0.65,0.7`, cathedral `0.5,0.55,0.6,0.45`). Idle = cursor (0.5,0.5,up); held = (0.4,0.6,down); audio = bass/mid/treb 0.8/0.5/0.9. Click case used a patched COPY of the harness in the scratch dir (`mr_rip.mjs`, ripples injected into `u.ripples`/`config.y`); `agents/mr.mjs` itself is unedited. Visibility = % of pixels whose max-channel |Δ| > 0.02 (and > 0.1) between the new file and the same file with that idea's contribution multiplied to zero (scratch copy), 20 frames, SRC=img. **All numbers below are for the final files (after the review round at the bottom).**

## 1. gen-chromatic-oracle-jelly (3rd pass)

KEEP VERBATIM held: yes. Every earlier idea (pulse-swim, pointer-tracking blinking eye, tentacle wake, click startle, audio pupil dilation, synapse sparks, bell frills), the bell/eye/tentacle/sigil masks and radii, palette, history mix 0.10+…, ACES, 4 params and their roles, A = ACES display RGBA. Existing `let hdr = palette(hue)*bell*…` gained only a `(1.0 - 0.5*canalTerm)` factor; everything else is added terms.

Idea comments in the file are numbered 6 and 7 because HEAD's comments already use "Idea 1…5" (with duplicates); card ideas 1 and 2 = file Idea 6 and Idea 7.

| card idea | where | what |
|---|---|---|
| 1 radial canals + excitation wave (native: medusa anatomy) | `gen-chromatic-oracle-jelly.wgsl` L130-135 (`canalR`, `canalTerm`, `canalFrontD`, `canalPulse`), applied L156 (dims bell under the canal) and L161 (tinted emission) | 8 constant-width lines (perpendicular distance, not angle) from the eye centre to the bell margin; a Gaussian front (`canalFrontD = canalR/0.30 − (swimPhase·2.6 − 0.4)`) leaves the eye margin at the contraction peak (phase ≈ 0.15), reaches the rim (R = 0.30) at phase ≈ 0.54 at full strength, and only then fades (`1 − smoothstep(0.55, 0.72, swimPhase)`); it starts behind the canal root so there is no pop at the swimPhase wrap. Plus a 0.30 resting level and the existing `startleKick` (clamped ≤ 1.5). |
| 2 frilled oral arms (native: medusa anatomy) | L140-153 (`armAcc` → `armTerm`), applied L162, alpha/depth below | 4 ribbons from the manubrium (centres ±0.0425, ±0.1275), base half-width 0.034 → 0.010 at the tip, ±35 % frill at 64 cycles/unit, sway in antiphase with the tentacle phase (`+π`), length × (1 − 0.28·contraction), faded in over the first 16 % so there is no flat cut. Gated by a cell-local box (|x| < 0.26, −0.03 < y < 0.33) so the 4-iteration loop only runs there. |

Measured (default sliders, new vs idea-off, % of frame > 0.02 / > 0.1):

| case | canals | arms | HEAD→new total |
|---|---|---|---|
| idle 192 | 3.63 / 0.77 | 4.40 / 2.35 | 7.56 / 3.10 |
| idle 576 | 3.58 / 0.76 | 4.29 / 2.31 | 7.41 / 3.07 |
| held 576 | 3.17 / 0.59 | 4.12 / 1.91 | 6.93 / 2.53 |
| audio 576 | 3.51 / 0.74 | 4.35 / 2.34 | 7.46 / 3.07 |

Ideas are not pointer-local; the frame-wide % is the honest figure. I looked at 3× crops of HEAD vs new: canals read as a clean 8-ray starburst inside each bell, arms read as ribbons below the bell margin and as tinted ribbons through the bell (translucent look). **Open/honest:** HEAD's small `oracleSigil` dashes (ring at eyeDistance 0.15) now overlap the canal starburst and are partly masked by it in pale bells; not removed, still additive. Many bells are near-white at the saved defaults (HEAD behaviour: `palette·bell·(0.6+oracleChroma·2.1)` ≈ 2.0 → ACES ≈ 0.92), which is why the canals dim the bell and add a tinted emission instead of only adding light.

Slider sweep (first round; each 0→1, others default, 192 px, % pixels > 0.02): swarm 88 %, drift 85 %, curl 60 %, chroma 67 % — all live (the review fixes do not touch slider wiring; dead-slider audit re-run on the final file: 0 new).
Click case (ripples at uv (0.3,0.4) t=0.9 and (0.62,0.55) t=1.25), final file, re-run after the review fixes with HEAD and new rendered identically (576 px, 20 frames, idle cursor, saved defaults): nan 0 / inf 0, max 0.98 (ACES ceiling), HEAD→new Δ 7.08 % / 2.78 % (vs 7.41 % / 3.07 % with no clicks) — the startle kick (clamped ≤ 1.5) brightens the canals without clipping or a blow-up. Not visually reviewed.
60 frames `A16=1` (384 px, held cursor + audio), final file: nan 0, meanL HEAD 0.348 → new 0.354, HEAD→new Δ 7.4 % / 3.8 % (flat vs the 20-frame number, no feedback drift).
Default look (meanL/stdL, HEAD→new): idle576 0.343/0.362 → 0.346/0.362; held576 0.391/0.342 → 0.393/0.342.
frameMs: interleaved HEAD/new pairs, held cursor, saved defaults, SwiftShader (CPU, shared machine at load average 14-29, so single samples scatter 12-67 ms): 14 pairs @192 px / 40 frames — lower-half-mean ratio 1.17, median ratio 1.15; 8 pairs @256 px / 30 frames — lower-quartile 1.10, median 1.00. Single-sample min ratios (1.50 / 1.29) are outliers (one lucky HEAD run) and not meaningful. Within the 1.3x cap on every aggregate; a real-GPU re-time is still needed.
Gates: precommit 1/1, verify-naga-wasm 1/1, dead-sliders 0 new, extrabuffer 0 new.

## 2. gen-liquid-cathedral-dream (3rd pass)

KEEP VERBATIM held: yes. arch/spire/window/rose/floorCaustic, all four earlier ideas (lead cames, molten drips, god-ray shafts, dichroic shift), palette, history mix, ACES, 4 params, A = ACES display RGBA read back as melt-offset history. Only the pane-colour term changed shape: `palette(hue + paneHue + dichroic)` → `palette(… + reamMod·0.25)` and `* (1.0 + reamMod)`; everything else is added terms.

File idea numbers 5 and 6 (HEAD had 1-4); card idea 1 = file Idea 5 (bubbles + cord), card idea 2 = file Idea 6 (motes).

| card idea | where | what |
|---|---|---|
| 1a seeded bubbles (native: pot-metal glass) | helper `glassSeeds` L44-57, used L164 (`seedGlint`), added L195 | at most one bubble per lattice cell; centre in [0.35, 0.65] and radius in [0.14, 0.27] so the profile is < 0.5 % at the lattice line (no D-shaped clipping); bright core + faint ring; two scales (34 and 15 per world unit, densities 0.30 / 0.12, the big layer ×1.2), in cell-local world units so they stay round and ride the melt (q is melt-warped); brightness `(0.9 + 1.8·shaftBand)·1.5` so they flash when a shaft crosses them. Salt uses a wrapped tier index (L159-160). |
| 1b reamy cord (native) | helper `vnoise` L33, used L165 (`reamMod`), applied L191 | value noise stretched along y (52 across × 2.8 along), crisped with `smoothstep(0.22,0.78,·)`, x coordinate `p.x + 0.3·melt.x` (keeps only 30 % of the melt shear so the streaks stay straight), ±0.65 on pane luminance **and** ±0.16 hue shift. |
| 2 Tyndall dust motes (native) | helper `dustMotes` L59-68, used L172-174 (`moteAmt`), added L196 | two parallax layers (22/11 per unit, rising at 0.35/0.18, centre+wobble kept in [0.27, 0.73] so < 1.3 % at the lattice line, twinkle `0.55+0.45 sin(t·1.7+h·50)` — continuous in time, **no floor(time) hashing**, cell index wrapped at 64), visible only where `smoothstep(0.04,0.45,shaftBand)·tier-fade` > 0. Uses the drag-warped `p`, not the melt-warped `q` (dust is not glass). |

The glass and mote work are gated (`if (window > 0.003)`, `if (moteFade > 0.002)`) so the nave pixels outside windows/shafts skip ~35 hashes; the gated render is bit-identical to the ungated one (0.00 % of pixels differ).

Measured (default sliders, new vs idea-off, % of frame > 0.02 / > 0.1):

| case | bubbles | cord | motes | HEAD→new total |
|---|---|---|---|---|
| idle 192 | 5.31 / 1.69 | 22.18 / 6.61 | 8.53 / 3.26 | 32.87 / 11.78 |
| idle 576 | 5.42 / 1.73 | 22.24 / 6.60 | 8.40 / 3.23 | 32.99 / 11.74 |
| held 576 | 4.36 / 1.13 | 18.26 / 3.80 | 7.14 / 2.44 | 27.77 / 7.70 |
| audio 576 | 3.72 / 0.98 | 20.20 / 5.86 | 8.00 / 2.92 | 29.74 / 9.95 |
| idle 576 @ T0 = 1500 s | 5.10 / 1.89 | – | 7.33 / 2.67 | – |

Not pointer-local; frame-wide figures. Looked at 3× crops and the full 576 frame (idle + held): the scene is unmistakably the same cathedral (same windows, same pink drag glow) with round ringed bubbles inside the panes, specks in the nave and vertical coloured cord streaks in several windows. **Open/honest:** the largest rare bubbles are fairly bright — trim the `1.2 *` on the big layer if a real GPU shows it hot; bubble lattice cells are cut at the window mask, not at pane (came) edges; the cord is now the strongest of the three (22 % of frame > 0.02) — if a real-GPU look finds the panes too streaky, lower the `1.3` factor on `reamMod` first.

Slider sweep (first round; 0→1, 192 px, % > 0.02): spire 93 %, melt 92 %, refraction 94 %, hue 78 % — all live (review fixes do not touch slider wiring; dead-slider audit re-run on the final file: 0 new).
Click case (same two ripples), final file, same recipe as the jelly click case: nan 0 / inf 0, max 0.98, HEAD→new Δ 32.32 % / 11.16 % (vs 33.0 % / 11.7 % with no clicks) — the ripple-driven drag warp composes with the new glass/dust terms without artefacts. Not visually reviewed.
60 frames `A16=1`, final file: nan 0, meanL HEAD 0.478 → new 0.486, HEAD→new Δ 22.5 % / 4.0 % (flat vs the 20-frame number, no drift).
Default look (meanL/stdL, HEAD→new): idle576 0.248/0.246 → 0.265/0.258; held576 0.416/0.229 → 0.428/0.235.
frameMs: interleaved HEAD/new pairs, held cursor, saved defaults, SwiftShader (CPU, shared machine at load average 14-29, so single samples scatter 12-67 ms): 14 pairs @192 px / 40 frames — lower-half-mean ratio 1.14, median ratio 1.17; 8 pairs @256 px / 30 frames — lower-quartile 1.24, median 1.04. Single-sample min ratios (1.25 / 1.41) are outliers (one lucky HEAD run) and not meaningful. Within the 1.3x cap on every aggregate; a real-GPU re-time is still needed.
Gates: precommit 1/1, verify-naga-wasm 1/1, dead-sliders 0 new, extrabuffer 0 new.

## Review round (coordinator relayed an independent reviewer's findings)

Each finding was reproduced at 576 / saved defaults BEFORE any edit (numpy replicas of the shader's own f32 hash for the lattice findings, the jelly formula evaluated directly, renders for the cord).

1. **Bubbles hard-clipped at the lattice line — reproduced.** HEAD-of-round code: centre ∈ [0.3, 0.7], r ∈ [0.17, 0.34]; 10.6 % (layer 1) / 10.8 % (layer 2) of present bubbles kept ≥ 0.25 of their profile at the nearest cell edge (reviewer: 11 %), 21.8 % ≥ 0.05; the ring *peak* itself crossed the edge only 0.4 % of the time (the reviewer's "17-19 % hard-clipped" is a lower threshold; the ≥ 0.25 figure matches theirs). Motes: residual at the edge up to 0.091 of peak (reviewer ≈ 0.09), 3.2 % ≥ 0.05. **Fixed:** bubbles centre = 0.35 + 0.3·h, r = 0.14 + 0.13·h → residual max 0.0046, 0 % ≥ 0.05; motes centre 0.35 + 0.3·j, wobble ±0.08 → residual max 0.0126, 0 % ≥ 0.05. Bubble visibility fell as expected (idle 576: 8.3 % → 5.4 % > 0.02; 2.8 % → 1.7 % > 0.1), still several %; I did not re-inflate the lattice scale.
2. **tierId growth hurting the hash — arithmetic reproduced, practical effect not.** tierId grows 0.446/s at the saved defaults (flowTime 1.24 t × 0.08 × 4.5 tiers); the sin() argument is ≈ 6e3 at t = 0, 2.6e5 at 60 s (ulp 0.016), 1.3e6 at 5 min (ulp 0.125) and 4.4e6 at 17 min (ulp 0.5) — the reviewer's number is right. But an f32 replica showed no degradation of the lattice statistics at t = 0 vs t = 1800 s (unique-hash 0.80–0.84 both, 0 argument collisions, present-fraction 0.27–0.37 throughout), and a render at T0 = 1500 s of the unwrapped code was not needed to see that. Done anyway as cheap robustness (GPU sin() range reduction at 4e6 is implementation-defined): `tierW = tierId − 64·floor((tierId + 8)/64)` before the salt, identity for tierId ∈ [−8, 56) (the first ~2 min), no pop (the wrap only changes the pattern of a tier cell at a cell boundary where the pattern changes anyway). Same-class growth also exists in HEAD's own `paneHue` / `dripHash` / `shaftHue` hashes (tierId·7, ·1.7, ·5.3 → smaller multipliers, ulp 0.5 after ≈ 1.9 h … 17 min for ·7) — **not touched**, flagged. The mote lattice index (grows with `time·speed`) is wrapped at 64 too. Verified: render at T0 = 1500 s shows bubbles 5.1 % / motes 7.3 % (vs 5.4 % / 8.4 % at t ≈ 0).
3. **Cord reads as mottling — reproduced qualitatively, not the number.** My own figure for the first-round cord was 2.4 % of pixels > 0.1 (idle 576; 1.0 % held, 2.0 % audio), not the reviewer's 0.76 %, but the look claim held: cord-only signed-diff correlation length 11 px along y vs 9 px along x (ratio 1.2) and a map shaped by the pane highlights. Cause: `q.x = p.x + melt.x` shears every vertical streak (melt.x has slope up to ≈ 1.35). **Fixed:** x coordinate `p.x + 0.3·melt.x`, streak length ×2 (q.y·2.8), `smoothstep(0.22,0.78)` crisping, wobble 0.7 → 0.3. Gradient anisotropy inside windows (mean |∂x| / mean |∂y| of `reamMod`) 1.40 → 2.92 with the same strength (std 0.336 → 0.325). Cord visibility now 22 % > 0.02 / 6.6 % > 0.1 at idle 576 (was 15 % / 2.4 %). Full-frame look: vertical streaks readable in several windows, panes not muddied.
4. **Jelly canalPulse wrap pop and truncated front — reproduced.** Old formula: pulse 0 → 0.67 / 0.49 / 0.33 at R = 0.06 / 0.08 / 0.10 across the swimPhase wrap; max pulse over a stroke at R = 0.26 only 0.81 and at R = 0.30 only 0.51 (front is at R = 0.21 when the fade starts at phase 0.35). **Fixed:** front `swimPhase·2.6 − 0.4`, fade `1 − smoothstep(0.55, 0.72, swimPhase)` → wrap jump ≤ 0.027, max pulse 1.00 at every radius 0.06 → 0.30 (peak phases 0.23 → 0.54), so the front now actually reaches the rim just after the stroke ends; the code comment states what it does. Header `Ideas:` wording ("rim-ward excitation wave") already did not claim more. Canal visibility after the change: 3.6 % > 0.02 / 0.8 % > 0.1 at idle 576 (was 3.8 / 1.0).

Reviewer's jelly "no should-fix defects otherwise": agreed, nothing else changed in the jelly except the `startleKick` clamp from round one.

## §12.2 rows / admission
No §12.2 row from the table was used (both files' ideas are native: medusa anatomy; pot-metal glass + lit-nave air). Admission: each idea consumes quantities the file already computes (`swimPhase`, `contraction`, `eyeLocal`, `oracleAngle`, `bellDistance`, `bell`, `startleKick` / `cellX`, `tierY`, `window`, `shaftBand`, `q`, `p`, `melt`, `columnId`, `tierId`) and adds no state, no new bindings, no new params. Deletion test: removing any idea leaves exactly the HEAD effect (verified by the idea-off renders above). Same-noun test: no foreign-family noun (no particles-as-sparkles on a distortion; the dust is native to a lit nave, and uses continuous drift).

## Not verified
Real-GPU look, thumbnails, cross-GPU timing (the machine load average was 20–29 during the final timings); click startle × canal glow only exercised by the two-ripple scratch case (not visually reviewed); the slider sweeps were not repeated after the review fixes (wiring unchanged, dead-slider audit 0 new).
