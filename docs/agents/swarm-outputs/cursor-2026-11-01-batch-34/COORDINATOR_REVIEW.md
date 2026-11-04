# Coordinator review — cursor/batch-34 slit-scan and time-delay (2026-11-01)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea is marked in the shader with a `// ── Idea` comment.

| Shader | Verdict | Why |
|---|---|---|
| chrono-slit-scan | pass | Jaw lip is folded into the existing mask. Transport weave offsets only the live sample inside that mask. Sweep, smin field, and early-exit stay. |
| cyber-slit-scan | pass | Crush contour uses the bit-crush residual. Field interlace (§12.2B) offsets odd rows of the write head only. Scroll, second head, and tears stay. |
| spectral-slit-scan | pass | Cauchy (§12.2F) scales the existing curve per channel. Second order is one fainter tap at 2× the chromatic offset. Stagger and luma-hold stay. |
| temporal-slit-paint | pass | Gaussian exposure falls across the existing slit. Stroke integration averages the live frame back along the velocity the state texel already stores. |
| temporal-slit-scan | pass | Reciprocity widens the existing shutter by the center sample's luma. Spatial width mixes the neighbor column by Temporal Spread. Ring wrap stays. |
| time-slit-scan | pass | Jaws follow Slit Width. The streak is a second exact history load along the existing drift. Age tint runs along the slit and still uses the slit index. |
| time-lag-map | pass | Iso-lines are level sets of the existing mapping. Smear direction is ∇lag; the motion gate stays. Feedback Mix now drives the history write. |
| phantom-lag-history | pass | Neighbor glow uses the four luma taps the diffusion already loads. Attack flash is the rising edge of the stored luma. A.a stays luminance. |
| temporal-distortion-field | pass | Ghost step uses Depth Weight on the existing taps. Beer–Lambert (§12.2F) darkens the bubble after the stasis mix, so a held frame is still the held frame. |
| temporal-phosphor-burn-motion-adaptive | pass | Grain is spatial and only on burn minus live. Bleed is a 4-tap of last frame's burn, gated by the existing trail. A stays the linear burn. |
| hyper-chromatic-delay | pass | Cauchy (§12.2F) replaces the linear λ step inside the existing 7-tap loop. Chroma delay (§12.2B) splits Trail Decay across R/G/B against the same C frame. |
| rgb-delay-brush | pass | Blue and green read C behind the existing spring velocity. Wet-edge thickens the absorption the mask already had. Wavelength absorption stays. |

Formula check: no §12.2 row appears on more than two files. Cauchy is the only shared row, and only on the two spectral delays. No new spring. No shared ripple stamp.

- [x] Idea Cards and mechanism notes exist in `BRIEFS.md`
- [x] Each idea is pointable in the WGSL
- [x] KEEP VERBATIM still holds
- [x] Diffs are the ideas plus the floor (prelude migrate, ACES where history must stay linear, exact C on `time-slit-scan`)
- [x] A packing matches how C is read
- [x] Saved params unchanged
- [x] Naga 12/12, extraBuffer, dead sliders
