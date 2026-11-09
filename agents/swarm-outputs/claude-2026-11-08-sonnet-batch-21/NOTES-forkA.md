# sonnet/batch-21 — fork A notes

Files touched (uncommitted): public/shaders/{chromatic-ghost-tunnel,gen-feedback-echo-chamber,gen-psychedelic-layered-time-stamps}.wgsl,
shader_definitions/generative/{gen-feedback-echo-chamber,gen-psychedelic-layered-time-stamps}.json (chromatic-ghost-tunnel.json untouched: features/description/params still truthful).
Renders: agents/swarm-outputs/claude-2026-11-08-sonnet-batch-21/forkA/ (final_<id>_<default|audio0|audio9|mouse|s576>.png; PNG = [raw | over white | alpha]).
Gates: naga/bindgroup/extraBuffer/pasted-header 3/3 via wgsl_precommit_gate; audit_extrabuffer PASS; audit_dead_sliders PASS (scans 2 defs — psychedelic has no `params`, checked by hand: zoom_params x/y/z/w all read, twice each); minirender: 0 NaN, no validation errors at 192/224/576.

Tooling notes: agents/minirender_img.mjs now also synthesises a depth map (SRC=img); agents/minirender_mov.mjs (MOV=1) re-uploads a moving two-disc source every frame — needed to judge anything that echoes video. minirender never re-uploads extraBuffer, so extraBuffer-state shaders look alive there but are dead in the app. Feedback shaders need ~20+ frames to converge: 8-frame renders are darker (psychedelic 192x8f meanL 0.195 vs 24f 0.418; same at 576/384, so it is frame count, not resolution).

---

## chromatic-ghost-tunnel (first §12 pass; header already carried Batch 17 notes)

Kept verbatim: 4 params and roles; z=1/(dist+0.01) mapping and implicit ring radius; cosine hue + OkLab cool/warm blackbody mix; echoFade; click z-band shockwaves; spiral streak; C chroma taps; fog; two-ended tint; hue_preserve_clamp(5.0) -> ACES -> IGN dither -> gamma.
A packing: raw pre-ACES hue-clamped RGB in A.rgb, coverage alpha A.a; texels (0,0) and (1,0) carry spring state (HEAD: post-ACES dithered RGB).

Ideas (findable by `// ── Idea n` comments):
1. Per-channel ghost lag — `ghostLag = (0, 0.12, 0.25) * tunnelSpeed`; `radG`/`radB` = the ring phase at `moveZ - lag` (R is the lead, HEAD's phase exactly); ringG/ringB use them, audio offsets unchanged. §12.2B chroma delay line. (Replaced the earlier Cauchy dispersion: Cauchy was on 3 batch files.)
2. Perspective-correct ring thickness — `perspW = clamp(0.55+1.6*dist, 0.6, 1.2)` multiplies ringWidth (first draft 0.3..1.5). Tactic 2 (not a §12.2 row).
3. Vanishing-point glow — `core = r0²/(dist²+r0²)`, r0 = 0.045+0.04*bass, warm/cool OkLab mix, added after the spiral streak. §12.2F soft inverse-square.

Rescues (not ideas):
- R1 double tone-map + coverage premultiply: HEAD meanL 0.054 / 0.086 / 0.115 at audio 0 / 0.4 / 0.9, every ring grey-tan. After: meanL 0.31 / 0.53 / 0.70, amber outer -> cool mid -> warm core. Straight alpha (HEAD's premultiply then compositing again darkened it twice). `aces_tonemap` deleted.
- R2 dead spring: HEAD steering reached 1.25% of its goal in the app. A-texel scheme (sentinel 0.7371, fract(time), dt clamped 0.001..0.05); `trailTap()` masks the two state texels and clamps. Idle cursor = goal 0 so default look is unchanged. Verified with held mouse at t=2 and t=5000.
- R3 dead per-bin voices (plasmaBuffer[1..8] = 0): ring i listens to band i%3. Raises audio response a little (those bands were already in the offsets).
- negative colour clamped before ACES (shockwave chroma term could go negative; catalog ACES fit maps negatives bright).
Formula names: chroma delay line (§12.2B), soft inverse-square (§12.2F). No spring/ripple added; the click shockwaves are HEAD's.
Revision 2 (coordinator review): Cauchy -> ghost lag; width cap 1.5 -> 1.2. Ablation at 288 px: the fat pale outer bands exist even with HEAD widths and no lag (they come from R1's single ACES + 5 stacked echoes, HEAD hid them by premultiplying); with ghost lag the bands split into thin R/G/B lines, so the fine ghost-line structure reads again (checked 192 and 576, quadrant crop vs HEAD). Final meanL 0.28 / 0.50 / 0.70 at audio 0 / 0.4 / 0.9 (HEAD 0.05 / 0.09 / 0.12). Clicks (u.ripples) are not exercised by minirender; that code is untouched apart from the colour clamp.

## gen-feedback-echo-chamber (2nd pass; 4 earlier ideas untouched)

Kept verbatim: params and roles, loadHistoryExact, fBM drift, wobble, echo loop (same taps/offsets), harmonic ladder, standing-wave nodes, first-order mirrors, comb notches, gravity well, click rings, CA, ACES on display, semantic alpha.
A packing: A.rgb = raw pre-ACES trail, A.a = bass envelope (HEAD: ACES display RGBA + envelope in extraBuffer[133]). JSON `feedbackPacking` and description updated (256 chars, was ~230).

Ideas:
5. Frequency-dependent echo decay — `ECHO_ABSORB = (0, 0.5, 1.2)`, per-channel weights `echoWeight*exp(-n*k)` and per-channel normalisation in the echo loop (energy-neutral).
6. Second-order image-source corner reflections — four taps with both axes mirrored, `cornerGain = 2*wallGain`, after the first-order mirrors.
Formula names: neither is a §12.2 row (tactic 1 / tactic 2); 0 rows used.
Honest visibility: on a moving test source the ablation difference (ideas on vs off) is only ~1/255 (absorption) and ~2.5/255 (corners) mean at default, and not larger at extreme sliders — the echo taps average an already smooth history, same as HEAD's ladder/mirrors. They are structural and findable, not dramatic.

Rescues (these are the visible change):
- R1 ACES-on-ACES + `*trailFade`: HEAD static-source stdL 0.010 (flat grey, meanL 0.67); with a moving source HEAD was saturated magenta/white blobs. After: a raw convex trail, ghosted video over psychedelic hue field (static stdL 0.054, moving 0.057). Decay slider still drives echo weights, ladder, wall gain and accMix.
- R2 bass envelope: now in A.a (each pixel replays the recurrence from its own C.a). HEAD effectively used 0.8*raw bass.
- R3 treble "sparkle" was `hash*treble*1.5` on every pixel = a white veil (meanL 0.49 silent -> 0.86 loud). Now `smoothstep(0.93,1,hash)*treble*3` sparse points (loud: 0.55-0.65).
Check for coordinator: look at a loud-audio frame on real hardware — sparkle amplitude was chosen by eye on SwiftShader.

## gen-psychedelic-layered-time-stamps (2nd pass; no `params` in JSON, none added)

Kept verbatim: zoom_params wiring (x layers, y delay, z distortion, w chroma), layer loop, layer_weight, lagged echo taps, postmark ring (dash, age envelope, warp), delay-clock wavefront in A.a, feedback mix, applyGenerativePrimaryControls, A packing.
A packing: unchanged (raw pre-ACES feedback RGB, wrapping delay clock in A.a).

Ideas (earlier pass owned 1-3):
4. Per-channel time lag (chroma delay line, §12.2B) — `wob_r/wob`/`wob_b` at t_i ± tau_i, `tau_i = 0.04*lag_dt*i`; layer 0 identical to HEAD, fringe grows with layer age. `echo_tap` now takes three wobbles.
5. Double-circle datestamp with ink dropout — inner ring at 0.84 r, value-noise dropout (`ink_noise`, freq 60 in aspect-corrected space) on both rings.
Formula names: chroma delay line (§12.2B) only.

Rescues:
- R1 OkLab was broken (forward M2 used as inverse, XYZ M1 on linear sRGB): every ink was green. HEAD static render: flat green (meanL 0.575, stdL 0.014). Standard linear-sRGB OkLab pair; ink chroma 0.10 -> 0.17 and ink hue spread 360° -> 180° across layers (eight inks 45° apart averaged to beige; `color_shift` still drives ring age/radius untouched).
- R2 edge-clamp smear at default amp 0.5 -> ping-pong fold (`mirror01`); warp field and amplitude unchanged.
- R3 Fresnel rim normal z 0.02 -> 1.0: rim was ~1 everywhere (constant beige veil with dark dots at the sine zero crossings). After: textured, hue-varied field (meanL 0.42, stdL 0.059); low-distortion (z=0.12) shows rings and layers clearly.
- x-meta.upgrade.params names aligned to the real roles (Layer Count / Delay Spread / Distortion / Chromatic Shift); x-meta is stripped from shipped lists, defaults/min/max untouched.
Check for coordinator: the default distortion (0.5 -> +-0.5 uv) is still extreme by design — the picture is a mirrored smear, not a recognisable video. Not changed (param theft). Static test source is low-contrast; judge on real footage.

---

## Batch de-duplication (fork A)
§12.2 rows: chroma delay line + soft inverse-square (tunnel), chroma delay line (psychedelic), none (echo). Chroma delay line is on exactly 2 files; no Cauchy in fork A. Neither of my files shares a spring/ripple/IQ overlay.
