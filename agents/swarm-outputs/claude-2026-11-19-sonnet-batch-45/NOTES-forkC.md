# NOTES fork C — crt-phosphor-decay, rgb-glitch-trail (second pass)

Cards + mechanism interrogation: `BRIEFS-forkC.md` (written before any WGSL edit).

## crt-phosphor-decay
SHADER: crt-phosphor-decay
IDENTITY: source re-drawn as a CRT raster — phosphor persistence in C, scanline + triad mask, halation, interlaced fields
KEEP VERBATIM: 4 params + roles; two-rate knee; triad-aligned grain bleed; interlaced field parity; per-channel decay 0.97/0.94; triadMask; mouse static + click bloom; ACES on display; A = ACES display RGBA read as colour history
ADD (new this pass):
  4. Beam-current scanline bloom (§12.2B scanline masks) — `beam = smoothstep(0.35,0.95,luma(boosted))` (luma of the line being drawn, already computed); the sine scanline profile slides toward its square root (flatter, wider line) and the triad-mask depth is eased by 0.4·beam. Bright lines swell into the gap, dark/mid content keeps the full raster. Rides the existing scanline slider.
  5. Dynamic convergence error (§12.2B CRT glass, radial r² term only — no geometry warp) — R sampled at `uv − s`, B at `uv + s`, `s = (uv−0.5)·0.004·r²ₙ·scanline_slider` (0 at centre, ~2 px at a 1080p corner at default). Raw slider, not the audio-boosted `scanlineStr`, so it does not pump with mids.
FORBID honoured: no barrel curvature (would break integer-coord C history), no new spring/ripple/palette, no new params.
A PACKING: ACES display RGBA (unchanged).
Where in the diff: `// ── Idea 5` (before `halo`), `// ── Idea 4` (scanline block).
Cost fix: HEAD sampled `readTexture` at `uv` twice (`fresh` and the halation centre tap). The halation helper now takes the centre as an argument, so the two extra convergence taps net +1 sample; the exp2/log2 profile was swapped for a sqrt blend.
RESCUE: none — HEAD renders (0 NaN, not blank, 4/4 sliders read). Left alone: the spring read at extraBuffer[133..138] is zeroed by the per-frame re-upload so `smoothMouse` is always the raw mouse (pre-existing, harmless, not an upgrade target).
Diff vs HEAD (SwiftShader, 192², SRC=img, 16 frames): default params 0.0% px >12/255 (max local diff 0.43 on the bright disc edge) — the synthetic scene is mid/dark so beam bloom barely engages and convergence is sub-pixel at 192²; scanline=1.0 + audio 0.6/0.4/0.4: 14.9% px >12/255, bright disc visibly de-rastered. 512², scanline=1.0: convergence isolated (new vs same file with coefficient 0): mean|Δ| 0.0000 r<0.3, 0.0005 r 0.3–0.6, 0.0015 r 0.6–0.85, 0.0020 r>0.85 — grows radially as designed, ~1 px at 512 wide. Real content with bright areas will show idea 4 far more than this test scene.
Timing (min-of-drained-frames, 384², 40 frames, 8 interleaved rounds, load avg 13–21): trimmed version median per-round ratio 0.93, min-of-mins 1.10× (untrimmed, first measurement: ~1.2–1.5× in the quiet rounds → trimmed). Very noisy; head mins ranged 21–106 ms.
Gates: wgsl_precommit_gate 1/1; verify-naga-wasm --files 1/1; audit_dead_sliders 0 new; audit_extrabuffer pass; JSON `params`/`features` byte-identical, description appended.

## rgb-glitch-trail
SHADER: rgb-glitch-trail
IDENTITY: pointer-left intensity trail (A.r) displacing the picture through a warped FBM field with R/B channel lag, spectral tint, streak rows and a persistence comet
KEEP VERBATIM: 4 params + roles; intensity accumulation (stamp + ripple spikes); warpedFBM/turbulentFBM displacement; channelLag idea (R +, B −0.65, magnitude 0.35+chaos); persistenceComet idea; spectral tint; streak rows; alpha = displacement·intensity; depth passthrough
ADD (new this pass):
  3. Per-primary decay order (§12.1 tactic 2) — lag magnitude per primary: R `mix(i, √i, 0.6)`, B `i·mix(1, √i, 0.7)` (both = 1 at i = 1). As the trail decays the blue ghost collapses first and a red-only fringe outlasts it. No new state.
  4. Tail-aligned fringe (§12.1 tactic 7) — central difference of C.r (±`max(2, 0.012·H)` px, exact `textureLoad`) gives the trail gradient; `−normalize(g)` points down-trail; weighted by `smoothstep(0.02, 0.12, |g|)` ×0.8 and added to the lag vector, so R drags toward the tail and B leads toward the head. Flat stamp interiors (g≈0) keep HEAD's warp direction.
FORBID honoured: no spring/ripple/IQ palette, no block quantisation (fork B's data-moshing), no Schmitt latch (would need to repurpose A.a), no new params.
A PACKING: raw sim (intensity, blendedHue.rg, persistence) — unchanged; ACES only on writeTexture.
Where in the diff: `// ── Idea 4` and `// ── Idea 3` just above `lagR/lagB`; `channelLag` replaced by `channelLagR/B`.
RESCUE: none — HEAD renders (0 NaN, trail visible, 4/4 sliders read). Not touched: `temporalDecay`'s `fract(time*0.1)` sawtooth on the decay exponent (small, pre-existing).
Diff vs HEAD (192², SRC=img, mouse path 0.15,0.3→0.85,0.65 held, 30 frames, t=2): default params 1.5% px >12/255 (edges of the trail and the fringe on the bright disc); decay 0.8/radius 0.6/shift 0.8/chaos 0.9 + audio: 10.4% px >12/255. Full-strength trail interior matches HEAD by construction.
Timing (same method, 384², mouse path, 8 rounds, load avg 13–21): median per-round ratio 1.06×; min-of-mins 1.31× (HEAD's best round fell in a quiet moment — 79 vs 105 ms in the same round — so treat 1.06–1.3× as the range). Added work is 4 `textureLoad` + one sqrt pair against ~30 value-noise evaluations of the FBM.
Gates: wgsl_precommit_gate 1/1; verify-naga-wasm --files 1/1; audit_dead_sliders 0 new; audit_extrabuffer pass; JSON `params`/`features` byte-identical, description appended.

## Batch notes
- §12.2 rows used here: crt → scanline masks + CRT-glass radial term; rgb → chroma-delay-style per-primary decay + gradient direction. No row shared between the two files; no latch/chroma-delay-line on both.
- Header lines: both `Upgraded:` extended with `, 2026-11-19`; both `Ideas:` lines extended (earlier ideas intact).
- Not done: real-GPU visual QA, `upgrades:record`, shader lists / search index (coordinator). Not committed.
- Scratch (renders, compare script, perf logs): `/tmp/claude-0/-root-image-video-effects/140df3c2-dd7d-47ec-b7ce-bccd640c64bc/scratchpad/forkC/`.
