# BRIEFS — fork E (sonnet/batch-53): gen-velocity-bloom, hybrid-sdf-plasma

Written before any WGSL edit. HEAD = worktree file at start (copies in scratch `e/<id>_head.wgsl`). Both files are 2nd+ pass.
Harness notes: gen-velocity-bloom has `params: []` in its JSON; the four slider roles/defaults live only in `x-meta.upgrade.params` (0.3, 0.7, 0.5, 0.85), so HEAD was re-rendered at those, not the harness's 1,1,1,1 (the 1,1,1,1 render is more washed out: meanL 0.84 vs 0.77). The stock harness source is a static image, so velocity = gradient only; I use a scratch copy (`e/mr_move.mjs`, `MOVE=1`) that moves the bright/dark discs per frame so `lumaDiff` (C.a vs current luma) is live.

---

## SHADER: gen-velocity-bloom

IDENTITY: motion-sensitive bloom — a multi-octave disc bloom + a flow-aligned anamorphic streak whose radius/stretch grow with velocity, accumulating into a curl-advected, diffusing trail kept in C.
KEEP VERBATIM: `velocityField` (|lumaDiff|·1.7 + gradient·0.5, perpendicular-gradient + curl flow), 4-octave × 8-direction bloom, 16-tap streak with Doppler fringe (Idea 1), `velocityColor`, curl-advected + Laplacian-diffused feedback with cooling afterglow (Idea 2), slider roles (threshold / intensity / radius / decay), bass→intensity, mids→radius, treble+FFT[6..8]→shimmer, generated depth, A packing (rgb = raw accumulated bloom trail, a = previous source luma; read back as `C.a` luma and `C.rgb` trail), semantic alpha.

### HEAD defect verification (checklist)
1. **No display ACES / clip.** `finalColor = mix(screen, add, …)·(1+0.3v)` is stored raw; screen blend of base with an accumulated bloom that is ~1.5× a full-frame blur exceeds 1 → hard clip. Verified: HEAD render meanL 0.77 (static) / 0.75 (moving) at the saved defaults; whole frame veiled, not just moving regions (screen blend runs at `velocityMask = 0`; the "bloom" has no bright-pass — by design in the 2026-03 original; NOT redesigned here, see open call). → **display ACES on writeTexture only**, input clamped ≥ 0; A keeps the raw HDR trail.
2. **Audio.** `plasmaBuffer[0].xyz` live (bass, mids, treble) ✓; `extraBuffer[6..8]` are FFT bins 1..3 (read-only, guarded `nExtra > 13`) ✓.
3. **C/A.** `textureLoad(dataTextureC, coord, 0)` exact, clamped; A write matches how C is read; no early return (zero-C starts fine; frame 0 shows one velocity flash because C.a = 0 — left, decays) ✓.
4. **extraBuffer state — DEAD (rescue).** `extraBuffer[133]` (energy) / `[134]` (prevDown) are in the zone `writeExtraBuffer` zeroes every frame (`audioDepth.ts:56` writes the full 256-float scratch; the harness re-zeroes `[133..255]` the same way). Consequence: `prevDown` is always 0 → `energy = 1` on every frame the button is held, never decays after release (the 0.93 decay multiplies a zero), and the single writer at (0,0) races every other workgroup's read. So the "click pulse spring" is a held-only, unsynchronised flicker. → **stateless pulse from `u.ripples`** (rising-edge clicks are already in the ripple table with absolute start time on the `config.x` clock; position = where the click landed).
5. Others: no `pow` negative base, no `ripples.w`, no dead mask, mouse y not flipped, alpha semantic. `IDEA_1/IDEA_2` ablation constants left as is.

### §12.1 interrogation
- Tactic 3 (promote an intermediate): `velocityField` computes the SIGNED temporal luma difference (current − previous source luma) and throws it away with `abs()`. The sign says "light arriving" vs "light leaving".
- Tactic 8 (energy accounting): the composite screens/adds the bloom on top of the full-strength base — the scattered energy is never taken out of the source. A real veiling glare steals what it spreads (pp-bloom shipped the same row: `take`).
- Tactic 6 (history): C is read as colour trail + luma; the one extra bit of continuity it affords without repacking is a decay that depends on whether the pixel just lost light.

### ADD
1. **Signed-motion flare & wake** — arrival (luma rising, `smoothstep(0.03, 0.25, +Δ)`) multiplies the bloom feed up to ×1.6 (the leading edge flares); departure (luma falling) pushes the trail decay toward 1 (the trailing edge leaves a longer wake). Uses the sign HEAD discarded; inert on a perfectly still source, like HEAD's own `lumaDiff`.
2. **Energy-conserving composite (§12.2F)** — `take = clamp(luma(accumulatedBloom)·0.28, 0, 0.45)`; the base gives up that fraction before screen/add blend, so glow does not double the exposure. Admission (§12.4): row owned by this file; same-noun ✓ (bloom), deletion test ✓ (remove it → still the same bloom, a bit hotter), expert test ✓ (energy conservation in lens scatter).
RESCUES: click pulse → stateless ripples (+ a soft held glow at the cursor); display ACES.
FORBID: bright-pass redesign (the veil is the shipped look), springs/shock rings beyond replacing the pulse, IQ palettes, Gray-Scott beyond the existing diffusion.
A PACKING: unchanged — rgb raw HDR bloom trail (never tone-mapped), a = previous source luma.

---

## SHADER: hybrid-sdf-plasma  (halftone ink-edge print; the "plasma/SDF/raymarch" names are legacy — the shipped description and code are a print filter)

IDENTITY: a photo as an offset-printed plate — posterized flat colour, 45° anti-aliased black-plate halftone dots with dot gain, Sobel-hypot ink outlines, paper-tooth ink starvation, pointer vignette; alpha = ink coverage.
KEEP VERBATIM: slider roles (p1 dot size 2..22 px, p2 edge threshold, p3 posterize levels 2..12, p4 ink density — all four live, JSON names are stale legacy and stay), 45° screen + AA + dot gain (Idea 1), Sobel hypot line (Idea 2), static tooth starve (Idea 3), pointer vignette, alpha = ink coverage, depth = ink coverage, A/C unused (display RGBA, nothing stored).

### HEAD defect verification (checklist)
1. **ACES: not owed.** Output is a display-referred print: posterized colour ≤ 1, ink multiplies down. Nothing exceeds 1, nothing is negative; ACES would move the posterize band levels and the black plate. Said here instead of stamped on.
2. **Audio / C / extraBuffer:** JSON claims none, WGSL uses none (no plasmaBuffer, no C, no extraBuffer) ✓ nothing to fix; `mouse-driven` is true (vignette).
3. **Posterize is dark-biased — DEFECT (rescue).** `floor(c·L)/L` can never reach 1 (max (L−1)/L). Verified on HEAD with a flat source: flat 0.97 → raw output max 0.859 (L = 7), flat 0.60 → 0.571; at Glow = 0 (L = 2) colour channels collapse to {0, 0.5}: harness meanL 0.136, white disc → mid-grey, frame mostly black. Highlights never reach paper white, and the cost grows as the slider goes down. → `floor(c·L)/(L−1)` (clamped), same band count, full range. Default picture changes (brighter, whiter highlights); said loudly in notes.
4. Other: no `pow`, no `ripples.w`, mouse y not flipped; the `paper_tex` hash of `uv·time·0.001` is near-constant (5 % alpha wobble) — harmless, left.

### §12.1 interrogation
- Tactic 5 (name the artifacts of the real device): an offset-litho press: dot gain ✓(have), highlight dropout, ink squash (dot rim denser than its core), plate misregistration, trapping. HEAD has gain + paper tooth only; the colour and black plates are perfectly registered, which is the one thing a real press never does.
- Tactic 2 (physics one step further): dot gain is the squeeze of ink under pressure → the squeezed ink concentrates at the dot's periphery (ink squash / "doughnut" dots at coarse screens).
- Tactic 3: the centre Sobel tap is the same sample as the dot luma (HEAD re-samples it) — so shifting the key plate costs no extra taps.

### ADD
1. **Plate misregistration (key plate off the colour plate)** — the key plate (outline taps, dot luma, dot lattice) is evaluated at `uv + reg/res`, the posterized colour plate stays at `uv`. `reg = (0.32, −0.20)·dotSize` px: a coarse screen is a crude press, so misregistration scales with dot size; static (one press run, no strobing). Black outlines slide off their colour boundaries, the classic off-register comic/screen-print look. No new taps (Sobel taps move with the key plate; dot luma reuses the centre tap). Row: none (§12.1 tactic 5).
2. **Ink squash** — inside a dot, ink density rises toward the rim: `rim = smoothstep(0.55·r, r, dist)`; the 0.7 ink multiply becomes `0.7 − 0.13·rim`, dot alpha ×(1 + 0.2·rim, ≤ 1). Visible as darker rings on big dots, flat dots on fine screens. No taps, no new motif.
RESCUE: posterize range (above).
FORBID: ACES, plasma/SDF/raymarch revival, IQ palette, springs, shockwaves, new sliders, per-plate CMY rosette (that replaces the colour mechanism → reimagining).
A PACKING: display RGBA, alpha = ink coverage; A/C untouched.

---

## Amendments made after implementation (the cards above were written first; these are what changed and why)

- **gen-velocity-bloom, Idea 3 mechanism.** First cut slowed the trail decay at departing pixels; ablation showed it touched 0.7 % of pixels (a pixel's luma only changes for one frame as an edge sweeps over it, so a one-frame decay tweak has no reach). Reworked: the luma that *left* (`max(-Δ, 0)`) is deposited into the trail (`tint · 1.4 · departed`), so it then decays, advects and diffuses with the existing trail dynamics; arrival gain is ×(1 + arrive), `smoothstep(0.02, 0.2, ±Δ)`. Ablation after the rework: 3.0 % (slow) / 8.9 % (fast) of pixels differ, max Δ 0.30 / 0.37.
- **gen-velocity-bloom, ACES placement.** Whole-frame `aces(finalColor)` (variant A) dulled the display-referred photo and capped whites at 0.80, losing the highlight disc entirely (the narkowicz fit expects scene-linear input). Shipped variant F instead: ACES maps the **bloom light** (`aces(accumulatedBloom)`) into display range before the screen/add blend, the photo stays display-referred, final is clamped 0..1. The A trail stays raw HDR. Open call: if the user wants whole-frame ACES per the letter of §3, variant A is `vb_variant_a.wgsl` in scratch `e/`.
- **hybrid-sdf-plasma, registration constant** (0.42, -0.27) → (0.32, -0.20) × dotSize (the coarsest screen put the key plate 11 px off on a 256 px frame, more than half a cell).
