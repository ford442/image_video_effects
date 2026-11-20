# NOTES — fork A (sonnet/batch-46)

VM = SwiftShader, no real GPU: structural + software-render evidence only, **no visual-QA claim**. Cards + interrogation are in `BRIEFS-forkA.md` (written before the first WGSL edit; §3 there records the two card revisions made after rendering).

---------------------------------------------------------------------
## gravitational-lensing-nlm  (first pass; `Upgraded: 2026-11-20`)

**ADD (as in the WGSL, each tagged `// ── Idea n`)**
1. **Buades-form NLM weights** (§12.2 "non-local-means / patch-similarity kernel deepening", this file only) — `patchDistance()`: Gaussian patch weights (σ = 1 px, sum 9 so `hParam = 0.015` keeps its HEAD scale), noise-bias term `exp(-max(pd − 0.22·h, 0)/h)` so near-identical patches reach weight 1, centre patch cached once, neighbour's centre tap returned with the distance. 456 → 225 texture loads.
2. **Disk g-factor** (tactic 2) — inside `renderAccretionDisk()`: emission × `gravitationalRedshift(r)·g³`, g = sqrt(1 − rs/r), blended by the Redshift slider (slider 0 ⇒ HEAD disk). Ablation vs same file without it: 38 % of pixels change, max 24/255 (disk dimmer/warmer toward the inner edge).
3. **Photon ring from closest approach** (tactic 3, §12.2E step-count-AO analogue) — `rMin` tracked in the march; escaped rays that grazed the horizon add `exp(-(rMin/horizon − 1)/0.05)` warm white; also nudges alpha. Ablation: 9.5 % of pixels, max 135/255 (thin rim on the shadow).

**Dropped idea (honest record):** "lensed second image of the disk" via bent-ray plane crossings — implemented, ablated, **0 pixels changed**: the file's own force law gives α = π·M/b², bending only matters for b ≲ 8 while the disk starts at 11.2. Code removed.

**KEEP VERBATIM (verified unchanged in the diff):** 4 params and roles; geodesic march/DT/MAX_STEPS; flat disk intersection + Doppler beaming + 3-tier colour; `gravitationalRedshift` on the far background; Einstein-ring glow; cursor mass + (inert) spring block; 5×5 search window, 3×3 patch, `hParam`; lensed colour as weight-1 sample; `mix(nlm, lensed, 0.65 + held·0.25)`; 7 % exact-C persistence; ACES on display; alpha = importance (adds a 0.25·photon term).

**A packing:** ACES display RGBA, unchanged (C is read as colour, exact `textureLoad`).

**Rescue (HEAD defect):** world rendered 180° rolled — `right = cross(up, forward)` is LEFT and `up * uvRaw.y` (y grows downward) is flipped, so the accretion-disk "floor" appeared overhead. Fixed with true right/up and `- up*uvRaw.y`; panorama lookup now uses `2(rd·f)f − rd` so the photo is displayed pixel-for-pixel as before (verified: bright/dark source discs sit at the same screen positions); cursor-mass world y negated so the lens still follows the pointer vertically. **Visible default change:** at default the saturated disk now fills the bottom half instead of the top half.
Not touched (HEAD look): the camera at r = 20 sits inside the disk annulus (2.8–14 rs), so the disk is near-saturated over half the frame at default mass; hairline seam at the horizon when the camera is exactly in the disk plane.

**Diff vs HEAD (256², defaults, image source):** 99.5 % of pixels differ > 2/255 — dominated by the roll rescue (disk moved top → bottom); per-idea ablations above.
**Timing (min-of-drained-frames, interleaved, load avg 11–22):** 192²/20 f × 8 rounds median **0.91×** (range 0.57–2.09); 256²/12 f × 4 rounds median 1.28×. Net ≈ 1.0× (NLM loads halved pay for the added ALU); box too loaded for tighter numbers.
**Gates:** `wgsl_precommit_gate` 1/1, `verify-naga-wasm` 1/1, `audit_dead_sliders` pass (0 new), `audit_extrabuffer` pass. NaN 0 over 3 stress configs (all sliders 0 / 1 / mixed, held mouse, audio 0..1).

---------------------------------------------------------------------
## distortion-gravitational-prismatic  (first pass; `Upgraded: 2026-11-20`)

**ADD**
1. **Dense, energy-normalised Cauchy spectrum** (§12.2F "Cauchy dispersion", this file only) — HEAD's four wavelengths (450/520/600/680) plus 485/560/640 → 7 bands; same `cauchyIOR(λ,1.5,B)` and `deflectScale`; each channel is now `Σ wl·sample / Σ wl` (identity at zero dispersion, white preserved). Smooths the four coloured ghost copies into a continuous spectrum.
2. **Spectral Einstein ring** (same row) — per band the ring sits at `θE·sqrt(deflectScale_λ)` (θE² ∝ deflection): blue outside, red inside, rainbow annulus; HEAD's time-cycled ring hue survives as a per-band emphasis (`ringHue`, Gaussian in λ).

**KEEP VERBATIM:** 4 params and roles; `deflectionAngle` law; mass layout (pointer + 4 orbiters); ripple deflection (`ripples[i].z` = birth time); `cauchyIOR`, `wavelengthToRGB`, original four wavelengths, `deflectScale`; accretion-disk tiers + swirl; redshift tint; 8 % exact-C persistence; ACES; alpha formula (ring term now spectral).

**A packing:** ACES display RGBA, unchanged.

**Rescues (HEAD defects):**
- **Red cast / non-conserved energy:** flat 0.6 grey source → sRGB (229,182,178) at HEAD; now (172,172,172) at every probed pixel. Required changing the band projection from `wl·dot(sample,wl)` (cross-mixes channels; pure red left as orange even after dividing the white point out) to the per-channel weighted mean. **Visible default change: every saturated colour in the lensed picture is now correct instead of orange/pink-shifted.**
- **Einstein "ring" was a dot:** `einsteinRadius(mass, distPrimary)` multiplied by the pixel's own distance (ring only inside dist ≈ 0.025). Now `sqrt(lensStrength)` = θE of the file's own deflection law.

**Flag for the user (not changed):** the deflection sign is *diverging* (`source = pos + n̂·|α|/2`, a negative-mass lens: no image inversion / real caustic). Flipping the sign would be a different look; left as HEAD. The Einstein ring is therefore a drawn feature at the intended radius, not a caustic of the mapping.

**Diff vs HEAD (256², defaults):** 100 % of pixels differ (colour-cast removal alone). **Timing:** 192²/20 f × 8 rounds median **1.02×** (very noisy, ~15 ms frames). **Gates:** precommit 1/1, naga-wasm 1/1, dead sliders pass, extrabuffer pass; NaN 0 over 3 stress configs incl. ripples, held mouse, audio.

---------------------------------------------------------------------
## JSON
- `gravitational-lensing-nlm.json`, `distortion-gravitational-prismatic.json`: `description` appended/updated (visible behaviour changed); `features`, `params`, `x-meta.upgrade.params` untouched (both already had `upgraded-rgba`, audio and mouse claims true).

## Could not verify
Real-GPU look and speed; whether the roll fix and colour fix match what the user expects from saved presets; thin-ring aliasing at 1080p (checked at ≤ 384²).
