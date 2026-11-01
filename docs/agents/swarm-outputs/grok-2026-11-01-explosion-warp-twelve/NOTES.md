# Notes — explosion / warp twelve

Prelude migration ran before the idea edits on the ten pasted headers. `hyper-space-jump.wgsl` and `warp_drive.wgsl` already included `_prelude.wgsl`. Saved `params` were not renamed or re-defaulted.

## cmyk-halftone-explosion

- Kept: density / angle / spread / prism, screen angles 15/75/0/45, sqrt(ink) radius, subtractive composite, per-channel prism and shock phase.
- Ideas in the diff: K wavelength and K shock are a fraction of CMY (`0.45` vs `1.5`, shock `* 0.35`); `screenDot` ellipses along the summed shock and stays round when `shockLen` is quiet.
- A packing: ACES display RGBA. C is not read.
- Formula: none from §12.2.

## elastic-chromatic-explosion

- Kept: kernel roles x red lag, y blue lag, z prism, w saturation. JSON labels still say Explosion Force / Chromatic Spread / Elastic Snap / Trail Decay; they were not rewired. Spring `extraBuffer[133..138]`, exact C EMA, bounded shocks, caustic from |R−G| and |B−G|.
- Ideas: `spring_vel` smears red with the motion and blue against it; the caustic desaturates the lagged colour before the highlight is added.
- A packing: ACES display RGBA.
- Formula: none. Core-spend is this file and cursor-aura only.

## interactive-rgb-split-explosion

- Kept: Prism Strength / Falloff / Ripple Strength / Saturation Boost. Falloff 0 still skips the gate (`select` of the ungated prism). Tangential prism, per-channel shocks, mids corona. The corona `pow` of a possibly negative base is now a square.
- Ideas: radial offset along the pointer, same `amount`; a lip on the existing falloff window multiplies `amount`.
- A packing: ACES display RGBA. C is not read.

## cursor-aura-explosion

- Kept: Radius / Intensity / Prism Strength / Dispersion, disc mask, 4-tap edge colour, cosine ring, click shocks.
- Ideas: `dispAmt` peaks on the limb; the core mixes the photo toward a darker luma before the violet glow is added.
- A packing: ACES display RGBA. C is not read.

## chronos-brush-explosion

- Kept: Brush Size / Decay / Prism Strength / Dispersion. Deposit only while held and inside the brush. Alpha still multiplies by `mix(0.9, 1.0, Decay)` first. Live/frozen mix and shocks still scale with freeze.
- Ideas: `prismAmt` follows `rim` (the old edgeMask); after Decay, alpha drops faster where `rim` is high.
- A packing: raw freeze RGBA in A. ACES on `writeTexture` only. C is exact `textureLoad` (the filtering sampler on C is gone).

## circuit-breaker-explosion

- Kept: Grid Scale / Overload / Jitter / Prism Strength, grid, hash nodes, Sobel edge, spectral trace colour, scanline, click shocks.
- Ideas: trace glow falls with pointer distance and Overload shallows it; node flash is a Schmitt latch in A.a (`§12.2B`), with a buzz only while the contact is held.
- A packing: A.rgb ACES display; A.a latch. Only C.a is read back.

## mouse-chromatic-explosion

- Kept: one sample, tangential prism, one ripple offset, `wavelengthToRGB`, bass pulse, treble wobble, depth blend. No per-channel UVs.
- Ideas: radial push is `0.28` of the same deflection; wavelength follows `prismAngle`, and Dispersion still scales the span.
- A packing: ACES display RGBA. C is not read.

## chromatic-shockwave

- Kept: Wave Speed / Frequency / Aberration / Ring Count, 8-layer stack, spring `extraBuffer[133..138]`, click shells, Beer–Lambert alphas, sector `plasmaBuffer` voice.
- Ideas: summed `wave` becomes an N-wave (positive crest only); continuous-wave aberration is gated by `|nwave|`. Click shells keep full Aberration.
- A packing: ACES display RGBA. C is not read as a field.

## zoom-burst

- Kept: Burst Length / Sample Quality / Spin / Chroma, comet weights, end ghost, spring, click packets, exact C mix, speed-line tint.
- Ideas: the existing 8-blade phase darkens between spokes; taps mix toward luma as `t` increases. The head and the dwell ghost stay coloured. Chroma still boosts the composite.
- A packing: ACES display RGBA.

## hyper-space-jump

- Kept: 30-tap radial loop, brightness-weighted streak alpha, relativistic alpha, depth cleared to 0. Jump Strength still scales the offset (`* 0.1`), now with a small bass and held factor because the definition already claimed audio and held acceleration. Streak Decay, Chromatic Spread, and Vignette Size were multiplied by zero; they now drive decay (`mix(0.88, 0.99, y)`), the R/B offset (`mix(0, 0.012, z)`), and the vignette start (`mix(0.15, 0.85, w)` so the default still opens at 0.5).
- Ideas: rim blue-shift on the finished streak; 0.16 mix of exact C before ACES.
- A packing: ACES display RGBA.

## hyper-space-jump-blackbody

- Kept: temperatures, 24-tap loop, Lorentz `gammaStretch`, inward beaming, `blackbodyColor`, pre-ACES store.
- Ideas: Cauchy scales (`§12.2F`) on the existing chrom offset; exact C mixed in cooler and redder before the vignette.
- A packing: pre-ACES RGB + vignette alpha. ACES on `writeTexture` only.
- Formula: Cauchy on this file only.

## warp-drive (`warp_drive.wgsl`)

- Kept: Warp Speed / Prism Split / Core Glow / Blur Quality, Alcubierre sign change, star hash, oil-slick packet, click fronts.
- Ideas: a spike in the integral at `t = 0.5`, scaled by Core Glow; the doppler mix follows `t` (bow blue, wake red) instead of `dirSafe.x`.
- A packing: diagnostic `vec4(dist, warpFactor * 0.1, dopplerMag, finalAlpha)`. C is not read. Display is not written into A.
