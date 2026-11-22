# NOTES — fork B (optical-flow-tracer, temporal-feedback-zoom-tracer)

Files touched: `public/shaders/optical-flow-tracer.wgsl`, `public/shaders/temporal-feedback-zoom-tracer.wgsl`, `shader_definitions/post-processing/optical-flow-tracer.json`, `shader_definitions/post-processing/temporal-feedback-zoom-tracer.json`. Nothing committed. Scratch: `/tmp/claude-0/-root-image-video-effects/547473e0-56ec-49ad-94b1-b40db5a7c127/scratchpad/b/` (HEAD copies, ablation variants, `optical-flow-tracer_3ideas.wgsl` = the dropped 3-idea draft, `mr_hist_orbit.mjs` = orbiting-disc / flat-background copy of the harness, `flow_metrics.mjs` = batch-46 flow-accuracy copy).

Both files: `Upgraded:` bumped (+2026-11-22) because each gained an idea; `upgraded-rgba` tag dropped from header `Features:` and JSON `features` (P-ACES (c): no ACES, passthrough photo composite, LDR emissions; `upgrade-worker.mjs` itself requires `/aces/i` for that tag). JSON `params` untouched; no new params; no `extraBuffer` writes; no C feedback added.

---

## temporal-feedback-zoom-tracer

**Idea Card (as built)**
- KEEP VERBATIM: 4 params + roles; focus = mix(0.5, mouse, 0.7); fbm jitter; chromatic history; Ideas 1-4 (nested monitor bezels, recursion hue drift, field lag, feedback-camera falloff); clock-ring + click overlay (left in place, see open calls); A = display RGBA (unchanged).
- ADD 5 **Keystone camera tilt** (§12.1 tactic 1; no §12.2 row): the warp divides by `1 + dot(rotated, tilt)`, `tilt` = hand-held sway (two incommensurate sines, amplitude `0.012 + 0.03*zoom`) + `(mouse - 0.5) * 0.03`. Finding: `// ── Idea 5` in the warp block.
- ADD 6 **Auto-exposure loop gain** (§12.1 tactic 2; no row): spot-meters the age-1 ring frame and the live frame at two points straddling the focus, `gain = clamp(sqrt((Lsrc+.04)/(Lhist+.04)), 0.9, cap)`, `cap = clamp(0.93/(persistence*(1-blend)), 1, 1.4)` so the loop gain at the focus stays under 0.93 (at high persistence the gain can only hold or dim). Finding: `// ── Idea 6` after the falloff.
- RESCUE R1 **audio phase scramble**: `sin(r*95 - time*(5+treble*7))` and `cos(.. + time*(0.8+mids))` multiplied absolute time by an audio value. Measured (one frame, treble .10 vs .12): mean|dpixel| HEAD 0.0023 @ t=0.5 s, **0.0257 @ t=60 s (11x)**; NEW 0.00265 at both. Audio is now a bounded phase offset (`- treble*4`, `+ mids*2`), still reactive.
- A PACKING: display RGBA (unchanged).

**What I could and could not show**
- Diff vs HEAD (128 px, 180 frames, t=3..6 s): silent 97.9% of pixels >2/255 (mean 0.037); with audio .3/.2/.1 99.6% (mean 0.095, mostly the clock-ring phase change from R1).
- Tilt alone (silent ablation): 71% of pixels, mean 0.015; a x8 difference map shows opposing-quadrant ring-phase shifts = a real lean. **Subtle at default**: the always-on clock-ring overlay re-accumulates every frame and masks it; stronger with pointer offset or Zoom up.
- AGC alone (silent ablation): 95% of pixels, mean 0.030. Measured brightness (256 px / 128 px, 240-300 frames): default meanL 0.200 -> 0.220 (+10%), focus region 0.49 -> ~0.69; p99 0.47 -> 0.58; max 0.77 -> 0.82. **My design estimate (settle at ~0.70x source) was wrong: the real lift is ~10% because the meter is centre-weighted.** Extreme params (zoom 0, persistence 1, blend 0): NEW == HEAD (mean .166, max .908, maxch 1.388 both) by the cap. Pointer at (0.9, 0.1): mean .194 vs HEAD .19, no hot spot.
- First draft metered a 3x3 grid and blew the focus out toward white with the pointer off-centre (fixed grid missed the focus); fixed by metering around the focus + the cap. A `var<workgroup>` once-per-workgroup meter was bit-identical but SLOWER on SwiftShader (barrier = coroutine yield), so it was dropped for a per-pixel 2-point meter.
- Edge cases run: 1-layer ring (D=1) finite, gain 1; silence finite; STATIC; extreme params; NaN = 0 everywhere.

**Timing** (mr_ab_hist, 192 px, 40 cycles, load 5): paired-median 1.08-1.19x, p25 1.16-1.20x, one min-ratio 1.40. The tilt is free (no-AGC copy ~1.0); the 4 extra taps are the cost. Under the 1.3x cap on medians but borderline; coordinator re-time on a quiet box.

**Gates**: precommit 1/1, naga-wasm 1/1, dead-sliders PASS (all four zoom_params read once), extrabuffer PASS.

---

## optical-flow-tracer

**Idea Card (as built)**
- KEEP VERBATIM: 4 params + roles; pyramidal LK (coarse 3x3 stride 4, fine 5x5), Gaussian window, Shi-Tomasi gate, KLT carry through C with hysteresis, 35% inertia; Ideas 1-4; **A = raw flow field (A.xy = flow*flowScale, A.z = |flow|*flowScale*20, A.w = 1), exact `textureLoad(dataTextureC)` read-back, not ACES'd — unchanged**; alpha formula; depth passthrough.
- ADD 5 **Comet taper + continuous Trail Age** (§12.1 tactic 4): `maxAge = 1 + u32(z*4)` made Trail Age a 5-step stair (HEAD: z=0.50 and z=0.62 render identically, mean|d| = 0.0; NEW 0.006). Now `ageF = 1 + 4z` (same ages at the default z=0.5), the last age enters with fractional weight and every age is tapered `(1 - 0.6*t)` — the dead `let t = age/(maxAge+1)` in HEAD was clearly meant to taper. Finding: `// ── Idea 5` in the trail loop.
- DROPPED (implemented, measured, removed): **shutter integration along the path** (1-4 adaptive sub-taps per age) and **constant-turn-rate trail** (rotate the per-age step by the angle between `prevFlow` and `flow`). Both act only on pixels with non-zero flow (the mover's body): wake pixels have ~0 flow and read the ring unwarped, so the visible onion-ring wake comes from plain echo of earlier outputs, which neither touches. Ablations on an orbiting disc: default sliders each <2% of pixels (mean 0.0006); max sliders 4.5-5.3% (mean 0.002); a 4-up crop of HEAD / NEW / no-turn / no-subtap was indistinguishable by eye. Not claimed. The 3-idea draft is in scratch if the coordinator wants it.
- A PACKING: raw flow (documented, unchanged).

**Measured**
- Diff vs HEAD, orbit scene (128 px, 40 frames): default sliders 12.8% of pixels >2/255 (mean 0.0035, 2.3% >8/255); max sliders (flow 1, age 1, blend .15) 49% (mean 0.011).
- Solver / A unchanged by construction; the batch-46 flow metric moves slightly only because LK compares against the ring (earlier outputs, which now carry the taper): rmsErrInside 2.11 -> 2.22 px, haloMean .27 -> .26, farMean .068 -> .057 at 3.4 px/frame.
- 1-layer ring finite (alpha .5 as HEAD), silence finite, NaN = 0.
- Timing (128 px, 24 cycles, load 5): paired-median 0.98-0.99x.
- Gates: precommit 1/1, naga-wasm 1/1, dead-sliders PASS, extrabuffer PASS (all four zoom_params read once).

---

## Open calls / things I did NOT do (for the coordinator and the user)

1. **zoom-tracer clock-ring overlay dominates the default picture** (additive rainbow rings at 95 rad/uv, always on, written into the ring so it compounds) and hides the tunnel structure, including the shipped bezels (at 0.6%/frame zoom the "nested" bezels stack into one thick halo). It predates this pass and is not on the `Ideas:` line, so I left it; removing or gating it would be the single biggest improvement to the file. User's call.
2. **optical-flow-tracer flow accuracy degrades fast with speed** (batch-46 metric, rms px inside the disc: 0.73 @ 1.1 px/frame, 2.1 @ 3.4, 8.7 @ 6.7; flow collapses to ~0 at high speed, the coarse level reaches ~+-4 px). Batch-46's solver; not touched (no cost headroom). Wake pixels also carry only the decaying 35% inertia flow.
3. The ring holds each frame's own OUTPUT (engine `blitReadTex` -> ring), so LK compares live source against previous trails, not previous source: a possible accuracy limit shared by every ring-fed flow shader.
4. The pasted note's "writes extraBuffer[4]" and "no exact dataTextureC load" do not apply to these two (both only READ `extraBuffer[4]` as historyHead; the flow tracer already uses exact `textureLoad(C)`; the zoom tracer has no C).
5. Tag removal (`upgraded-rgba`) is a P-ACES policy call; reversible by adding the tone-map to the emitted terms if the user prefers the tag.
