# NOTES fork B — conv-fractal-kernel, data-moshing (second pass)

Cards + mechanism interrogation: `BRIEFS-forkB.md` (written before any WGSL edit). VM = SwiftShader only; no real-GPU look was done.

## conv-fractal-kernel
SHADER: conv-fractal-kernel
IDENTITY: 15×15-tap blur weighted by Mandelbrot-set membership (boundary > interior, DE glint), mouse-warped centre, ripple Julia offset, alpha = fractal depth
KEEP VERBATIM: 4 params + roles; 7-step tap grid; `pow(v,2)*0.45 + boundary*0.7 + 0.05`; glint; ripple Julia; palette tint; ACES; audio reads; depth passthrough; A = display RGBA; the escaped-point smooth-iteration formula; escape-time loop body (kept as the second half of a split loop)
ADD:
  1. circle orbit trap (§12.2E "Orbit trap") — nearest approach of the first 4 orbit points to `|z|² = 0.1225` (uses the `x2+y2` the escape test already computes); per-tap weight × `0.55 + 0.9·exp(−14·trap)`; energy-conserving (lands in `accumWeight`). Only 4 orbit points are trapped: over the full orbit the rings are denser than the 15×15 lattice (aliased hatching, seen and rejected). Loop is split so the long tail is HEAD's loop unchanged.
  2. defocus-scaled aperture (tactic 4, second-order of `kernel_radius`) — tap pixel footprint × `1 + 0.75·smoothstep(0.05, 0.6, |depth − depth@pointer|)` (≤1.75×; 2× showed a lattice on 3 px highlights). The fractal window is NOT scaled, so the aperture keeps its shape. Flat/absent depth ⇒ ×1 (HEAD).
FORBID (held): springs/extraBuffer, new params, palette swap, feedback layer, per-sample accumulators.
A PACKING: ACES display RGBA; alpha = mean membership 0..1 (documented on the header's `A packing:` line).
RESCUES (HEAD defects, not credited as ideas):
  - R1 interior smooth-iteration NaN. HEAD evaluates `log2(log2(dot(z,z)))` for non-escaped orbits where `dot(z,z) < 1` ⇒ `log2` of a negative. CPU replica: at defaults and in most of the slider space **all 225 taps are interior** and all NaN on IEEE hardware. SwiftShader's `log2` returns `log2|x|` (probe: 23.17, finite) so HEAD only "worked" on this VM; on a real GPU interior weight/colour were an undefined `clamp(NaN)`. Fix: smooth value only when escaped; interior = 1.0 exactly.
  - R2 alpha out of range. `fractalDepth = Σv / Σw` ⇒ measured 1.48 (theoretical max 2.0) at defaults. Now `Σv / 225` ∈ [0,1]; measured 1.0 at defaults, 0.96 in a boundary-rich window (HEAD 1.466). The palette tint reads the same value: tint factor 0.4 vs 0.59 (HEAD on SwiftShader); the tint *hue* depends on `fractalDepth + time·0.05` with period 1, so the snapshot hue differs (teal→red at t≈0.5) but it cycles every 20 s either way.
  - Also (design observation, not changed): HEAD's weight window lives in the main cardioid for nearly all slider values ⇒ the kernel was a flat box; Idea 1 is what gives the interior structure.
Diff vs HEAD @192 (SRC=img, defaults, bass/mids/treb 0.3): 97 % px >12/255 — dominated by the rescue-driven tint hue/strength change (point-source kernel test below shows the actual kernel change). Kernel check (single-pixel point source on black, max radius): HEAD = flat 15×15 box; new = curved ridge/band structure inside the box; at defocus the lattice at 1.75 px spacing shows as expected for a 1 px source.
Timing (SwiftShader, load avg 20–27, 128², min-of-drained-frames over 60 frames, interleaved HEAD/new, 6 rounds): ratios 0.94 / 1.67 / 1.17 / 1.05 / 0.97 / 1.09 → **median 1.07×**. (An earlier 10-frame run read 1.27–1.31× purely from noise; the loop split keeps the long iteration tail HEAD-identical.)
Gates: wgsl_precommit_gate 1/1; verify-naga-wasm --files 1/1 valid; audit_dead_sliders 0 new; audit_extrabuffer pass. JSON: description appended; `"depth-aware"` added to features (now true: depth drives the aperture); `params` byte-exact.

## data-moshing
SHADER: data-moshing
IDENTITY: per-pixel motion-vector field (raw A: offset.xy, confidence, age) smeared along flow, axis-collapsed per macroblock, corrupted by bass/clicks, displaced render + block-edge ring + R/B split + quantize + residual spark
KEEP VERBATIM: 4 params + roles; flow smear; pointer scrub incl. the spring block (unchanged); click fronts; `corruptionEvent`; `macroblockMV` (0.72); `residualSpark`; depth-modulated decay; ±0.4 clamp; edge ring; R/B ±blockSize/2 split; global floor quantize; treble band noise; ACES; semantic alpha; **A = raw `(offset.xy, confidence, age)`**
ADD:
  1. 4:2:0 chroma block bleed (§12.2B "Chroma delay line (4:2:0)") — luma stays the displaced pixel's; chroma (rgb−Y) pulled toward one tap at the macroblock centre of the displaced uv, weight `smoothstep(0.2,0.8,confidence)·corruption`. One extra `textureSampleLevel`; luma-neutral by construction. Visible as block-coloured fringes under crisp luma near the pointer / on bass hits.
  2. intra-refresh sweep (codec GOP artifact, tactic 5) — 2-macroblock-wide band, left→right, 9 s period (`REFRESH_PERIOD`), wipes `offset/confidence/age` before the A write; block-quantized so it follows Block Size; the vector jump lights the existing residual spark. `age` (written but never read at HEAD) now resets to 0 = "frames since last intra".
FORBID (held): IQ palette, shockwaves beyond HEAD's, scanlines, second tear system, new params/packing, new spring state.
A PACKING: raw sim `(offset.xy, confidence, age)` — unchanged.
RESCUES: none made. **Flagged, not fixed:** the spring (`extraBuffer[133..138]`) never persists — `writeExtraBuffer` re-uploads all 256 floats every frame (`src/renderer/webgpu/audioDepth.ts:49`, `frame.ts:281`) — so `initialized` is false each frame, `springVel` is 0 and `offset += springVel*scrubMask` is dead at HEAD (the pointer still raises `confidence` and, via Idea 1, now drives visible chroma bleed). A real fix needs a place to keep pointer velocity (no new packing allowed in an in-place upgrade). Same pattern likely exists in other pointer-led shaders that copied this spring block.
Identity checks: `smear=0, corruption=0` with loud audio → max |diff| vs HEAD = 0 (Idea 1 is gated by `corruption`, Idea 2 wipes zero state). Calm defaults (audio 0.2): 0.4 % px >12/255 (edge fringes only). Loud + held pointer + corruption 1: 42 % px >12/255 (chroma bleed + refresh column visible in the diff).
Timing (SwiftShader, load ≈ 25, 512², 30 frames/round, interleaved): 6 rounds = 1.11 / 0.57 / 0.90 / 0.97 / 0.92 / 1.07 → **median 0.95× (≈1.0×, within noise)**. A 128² run was jitter-dominated (4–6 ms frames; median 1.35, range 0.88–1.62) and is not a usable reading. The only added cost is one `textureSampleLevel` + a few ALU ops per pixel.
Gates: wgsl_precommit_gate 1/1; verify-naga-wasm --files 1/1 valid; audit_dead_sliders 0 new; audit_extrabuffer pass. JSON: description appended only; `features`/`params` untouched.

## Dedupe / coordinator
- Formula rows used by fork B: §12.2E Orbit trap (conv-fractal-kernel), §12.2B Chroma delay line 4:2:0 (data-moshing). If fork C also takes the 4:2:0 chroma row, that is the allowed 2-files-per-batch maximum.
- Not done here (coordinator): `upgrades:record`, `generate_shader_lists`, `verify:shaders:fix`, real-GPU look, commit.
- Scratch tooling (private copies, not committed): `agents/mr_dots.mjs` (SRC=img + `DOTS=1`/`DOTR` point-source mode), scratchpad `forkB/perf.sh`, `fk_cpu.py`, `trap_view.py`, `kern_view.py`.
