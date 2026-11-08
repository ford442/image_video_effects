# sonnet/batch-21 — fork A briefs (written before any WGSL edit)

Shaders: chromatic-ghost-tunnel (1st pass of §12 ideas, `Ideas:` absent), gen-feedback-echo-chamber (2nd pass), gen-psychedelic-layered-time-stamps (2nd pass).
HEAD diagnostics were done on scratch copies only (forkA/scratch/), not on the real files.

Minirender caveat found: agents/minirender*.mjs allocate `extraBuffer` once and never re-upload it, so shaders that keep state in
extraBuffer[133..] appear to *work* there while the app zeroes it every frame. Anything judged from minirender that uses
extraBuffer is invalid; the tunnel spring is therefore removed from extraBuffer entirely so the render is honest.

---

## 1. SHADER: chromatic-ghost-tunnel

IDENTITY: perspective tunnel of concentric chromatic ghost-echo rings, OkLab+blackbody palette, spiral streaks, treble flashes, mouse-steered flight.

KEEP VERBATIM: 4 params + roles (tunnel speed -> moveZ, spiral twist -> twist, echo count -> nRings, flash -> treble strobe); z=1/(dist+0.01) tunnel mapping and the implicit ring radius `ringPhase*0.6`; per-ring cosine hue + OkLab mix of cool/warm blackbody; echoFade; click z-band shockwaves; spiral streak; C chromatic history taps; fog; two-ended tint; `hue_preserve_clamp(5.0) -> ACES -> IGN dither -> gamma` (the header's declared signature chain).

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): the ring is a Gaussian in screen-space `|dist - radius|` with constant width. A real tunnel's rings are constant-z-thickness slabs, so projected thickness follows r^2 — the constant width makes the centre a moire lattice (seen in the HEAD render).
- Tactic 2 (physics one step further): chromatic split currently exists only when audio is non-zero (`bass*0.03`...), and all three channels read the same ring phase, so there is no ghost at silence. A ghost is a delayed copy: G and B should read the ring phase at their own delayed tunnel-time. Also: a tunnel has a light at the end — the vanishing point is the only light source and is currently just where the fog is thinnest.
- Tactic 3 (promote an intermediate): `z`, `moveZ`, `fi`, `dist` and `ringRadius` are already computed per ring; both ring ideas consume them. `warmCol/coolCol/bass` already exist for the glow.
- Tactic 6 (history): C is read as colour history, 3 chroma-split taps. HEAD writes the *post-ACES, dithered* colour to A, and ACES'es it again next frame (ACES-in-C). No new history idea — only the packing is made truthful.

RESCUES (not ideas; documented as such)
- R1 double tone map: `aces()` -> gamma -> `aces_tonemap(outRGB * a)` with a premultiply by coverage. Measured on HEAD: meanL 0.05 at default, every ring grey/tan — the OkLab/blackbody palette is invisible. Single display chain restored (hue clamp -> ACES -> dither -> gamma), straight alpha as in the other generative files, A = raw pre-ACES trail (C is then read in the same domain). Scratch test: meanL 0.42, amber outside / cool mid / magenta core.
- R2 dead inertial-flight spring: state is in extraBuffer[133..136], zeroed per frame, so steering is 1.25% of its goal. Moved to the A-texel scheme (texel (0,0) = pos+vel, texel (1,0) = (fract(time),0,0,0.7371) sentinel, C read zeroed on those two texels, every thread integrates the same dt). Idle cursor (0.5,0.5) gives goal 0, so the default look is untouched.
- R3 dead per-bin voices: `plasmaBuffer[1 + i%8]` is never uploaded (always 0). Ring i now listens to band i%3 (bass, mids, treble) — a live version of the same "rings flare individually" feature using the three bands that exist.

ADD (3 ideas):
1. Per-channel ghost lag (§12.2B "Chroma delay line") — R is the lead (HEAD's phase), G and B read the ring phase at `moveZ - lag*speed` with lag 0.12 s / 0.25 s, same per-channel slot as the audio offsets. Exists at silence, the echo trails the lead like a ghost. REPLACES the earlier Cauchy idea (Cauchy was on 3 files in the batch; coordinator review).
2. Perspective-correct ring thickness (tactic 2, not a §12.2 row) — ringWidth scaled by `clamp(0.55 + 1.6*dist, 0.6, 1.2)`: mildly thinner toward the vanishing point, at most 1.2x HEAD outside (first draft 0.3..1.5 read as heavy bands).
3. Vanishing-point glow, soft inverse-square (§12.2F "Soft inverse-square", `I r0^2/(d^2 + r0^2)`) — warm blackbody core at the tunnel mouth, radius and heat ride bass. Native: light at the end of the tunnel.

FORMULA ADMISSION: Chroma delay line row — family sentence: a *ghost* tunnel's echoes are delayed copies, and the ring R/G/B split is the slot where the delay goes; consumes `z`, `moveZ`, `fi`, `tunnelSpeed` already computed; deletion leaves HEAD's audio-only split. Inverse-square row — consumes `dist`, `warmCol`, `coolCol`, `bass`; deletion leaves the tunnel. Idea 2 is geometry from existing `dist`. Two §12.2 rows; chroma delay line is on 2 files in the batch (psychedelic + tunnel), soft inverse-square on 1. Cauchy removed.
FORBID: new springs/ripples (the existing click shockwaves stay), IQ-palette stamp, anything touching the OkLab/blackbody chain, new params.
A PACKING: raw pre-ACES hue-clamped RGB in A.rgb, coverage alpha in A.a; texels (0,0),(1,0) carry flight-spring state (C read masked there).

---

## 2. SHADER: gen-feedback-echo-chamber (2nd pass)

IDENTITY: video fed through a temporal echo room — fBM-warped history taps, mouse gravity well, psychedelic palette blended in, ghost trails.

KEEP VERBATIM: 4 params + roles (echo count, decay -> echo weight/ladder/wall gain/accMix, spacing -> taps/comb/wobble, colour shift); `loadHistoryExact`; fBM drift; wobble; echo loop; the 4 existing Ideas (harmonic ladder, standing-wave nodes, first-order wall reflections, comb notches); gravity well; click rings; treble sparkle; chromatic aberration + ACES on display.

MECHANISM INTERROGATION
- Tactic 1: echo taps are a geometric weighted average of history. A real room's decay is frequency-dependent (air + wall absorption kills highs first) — HEAD's decay is one scalar for all colours.
- Tactic 2: first-order wall reflections exist (L/R/T/B mirror taps). Physics one step further = the second-order image sources (corner images, both axes mirrored, gain squared) of the image-source method.
- Tactic 3: `echoWeight`, `wallGain`, `wobble` are all already computed; both ideas reuse them.
- Tactic 6: C is read as colour history. HEAD stores ACES display RGB in A and then applies `acesToneMap(color*1.1+)` on an already-ACES'd accumulation every frame — measured flat grey wash (stdL 0.01, meanL 0.67) regardless of source. Packing is changed to raw (see R1).

RESCUES
- R1 ACES compounding + double decay: A held display colour, the next frame mixed it and ACES'd again, with an extra `* trailFade` (steady-state gain only 0.13-0.28 of the input, pumped back up by the compounding). Now: A.rgb = raw pre-ACES accumulation, `accColor = mix(prev, color, accMix)` (convex, unity DC gain, stable because `color` is itself a convex blend), ACES only on writeTexture. Decay slider keeps every role (echo weights, ladder, wall gain, accMix length). Scratch test: video + psychedelic hues visible, meanL 0.67 -> stdL 0.06.
- R2 dead bass envelope: `extraBuffer[133]` envelope never persists (bass = 0.8*raw always). Envelope now lives in A.a (each pixel replays the same recurrence from its own C.a; no single writer needed; C.a is not used for anything else). feedbackPacking string updated.

ADD (2 ideas):
1. Frequency-dependent echo decay — per-channel weight `exp(-n * vec3(0.0, 0.05, 0.12))` on the n-th echo and per-channel normalisation: highs (blue) are carried by the early echoes only, red carries the tail, so ghost trails go warm and blue fringes the leading edge. Native: RT60 per band. Energy-neutral (normalised).
2. Second-order image-source corner reflections — 4 corner taps (x and y both mirrored) at `wallGain^2` (+ `wobble`), extending the existing first-order mirrors. Native: image-source method.

FORMULA ADMISSION: neither is a §12.2 row (the file is a generative feedback shader; the rows nearest are D "Damped wave" / B "Chroma delay line", neither fits). Both are tactic 1/2 outputs that consume existing quantities, no new state or binding. 0 rows used.
FORBID: re-adding ladder / standing-wave / comb ideas, springs, new palettes, new params.
A PACKING: A.rgb = raw pre-ACES accumulated colour, A.a = bass envelope (HEAD: ACES display RGBA — stated as packing change).

---

## 3. SHADER: gen-psychedelic-layered-time-stamps (2nd pass)

IDENTITY: stack of time-delayed video copies, each tinted by its own OkLab ink x blackbody, wobbled by the distortion field, pointer-anchored postmark rings, feedback clock in A.a.

KEEP VERBATIM: params-as-wired (x -> layer count, y -> delay scale, z -> distortion amp, w -> chroma shift; JSON has no `params` and stays that way so defaults stay 0.5 x4); layer loop, `layer_weight`, `lag_dt` echo taps, postmark ring (dash, age envelope, warp), delay-clock wavefront in A.a, rim glow, feedback mix, `applyGenerativePrimaryControls`, A packing (raw pre-ACES feedback RGB + wrapping clock in A.a).

MECHANISM INTERROGATION
- Tactic 1: the echo tap is one (clamped) video sample per channel.
- Tactic 2: a post office stamp is a double-circle with uneven ink; analog video delay lines delay chroma separately from luma.
- Tactic 3: `lag_dt`, `t_i`, `wob`, `rp`, `ring_d`, `mixed` already exist per layer.
- Tactic 6: C.rgb feedback + C.a clock already owned; no new history idea.

RESCUES
- R1 OkLab is broken: `oklab_to_linear` multiplies by the *forward* M2 matrix (not its inverse) and `linear_to_oklab` starts from the XYZ M1, not the linear-sRGB one; `stamp_ink` and `oklab_mix` therefore return a constant green. Measured: HEAD renders a flat green wash with dark dots (meanL 0.42, stdL 0.03). Replaced with the standard linear-sRGB OkLab pair (same matrices as chromatic-ghost-tunnel).
- R2 edge-clamp smear: default distortion slider 0.5 gives `wob = +-0.5 uv`, and every sample is `clamp(uv + wob)`, so most of the frame is edge-column stripes. Boundary handling changed from clamp to a mirror fold (ping-pong); the warp field and amplitude are untouched.

ADD (2 ideas):
1. Per-channel time lag (§12.2B "Chroma delay line") — R samples the distortion field at `t_i + 0.18*lag_dt`, B at `t_i - 0.18*lag_dt`, G at `t_i`: each channel is a slightly different time-stamp, fringe grows with layer index. Native: the layers *are* time-stamps; HEAD's R/B shift is a tiny fixed spatial offset.
2. Double-circle datestamp with ink dropout — second concentric thin ring at 0.84 of the postmark radius (the classic circular date postmark) and a value-noise ink dropout mask (uneven rubber-stamp pressure) on both rings. Native extension of the existing postmark (Idea 2 of the earlier pass).

FORMULA ADMISSION: Chroma delay line is in the distortion/glitch table; family sentence: layered delayed copies with per-channel offsets *is* an analog video delay line; consumes `lag_dt`, `t_i`, `amp`, `chromatic_shift` that already exist; deletion leaves HEAD. Idea 2 is geometry on `rp`/`ring_d`. One §12.2 row.
FORBID: springs, extra ripples, IQ palette, new params, touching the A.a clock.
A PACKING: unchanged (raw pre-ACES feedback RGB in A.rgb, wrapping delay clock in A.a).

---

## Batch de-duplication (fork A)
No two of my files share a §12.2 row. Tunnel: chroma delay line + soft inverse-square. Echo: none. Psychedelic: chroma delay line (2 files total with the tunnel). The A.a trick (echo envelope, psychedelic clock) is storage plumbing, not an idea.
