# Split-Gen Twelve — batch contract (2026-09-28)

Live law: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §3, §4, §8, §9). Bindings: `agents/WGSL_BUILTINS_GENERATIVE.md`, `docs/BINDING_CONTRACT.md`.

## Claimed IDs (one agent each — never touch another agent's file)
Generative: kimi_flock_symphony, gen-showcase-nebula-core, gen-worley-cellular-noise, gen-sentient-holographic-neuro-lace-matrix
Non-generative: sonar-reveal, lighthouse-reveal, fabric-zipper (interactive-mouse); video-echo-chamber, mercury-temporal-mirror
(image); holographic-sticker (visual-effects); luma-glass (distortion); audio-reactive-pyramid (post-processing)

Selection: 172 unclaimed candidates (no `^//  Ideas:` line, no upgrade marker, not in any 2026-09-2x batch, single-pass
JSON url). 26 read in full; rejections in NOTES.md. Every card idea was grepped against the 670 catalog `Ideas:` lines.

## Per-file floor (hygiene, not the upgrade)
Canonical 13 bindings, @workgroup_size(16,16,1), bounds guard; ACES on display RGB; semantic alpha; dataTextureA is the
only feedback write (keep HEAD's documented packing unless the card says otherwise); exact `textureLoad(dataTextureC, coord, 0)`;
audio only from `plasmaBuffer[0].xyz` (audio-reactive-pyramid may keep its valid extraBuffer[5..132] FFT bins);
saved `params` byte-exact; naga-clean; `python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl` passes.

## Verified runtime facts (trust over older docs)
- `plasmaBuffer[0].xyz` = bass/mid/treble is uploaded. `plasmaBuffer[1..]` reads ZERO.
- extraBuffer per frame: [0..2] bass/mid/treble, [4] historyHead, [5..132] 128 FFT bins, [133..255] ZERO. Nothing written
  to extraBuffer persists — springs/dampers/click counters there are no-ops. Leave HEAD inert springs, add none, never build an idea on extraBuffer state.
- `u.ripples[i].w` is always 0. Ripple age = `time - ripple.z`. Cap loops at `min(u32(u.config.y), 50u)`.
- `zoom_config.yz` = mouse in canvas UV 0..1, y=0 TOP. `zoom_config.w` > 0.5 = held. `zoom_config.x` = time.
- Screen y=0 is the top. "Up" in a y-up scene means flipping pixel y.
- `pow(x,n)` with x<0 is NaN (use x*x). WGSL float `%` keeps sign. `fract(uv.x*res.x)` at texel centres is constant 0.5.
- Renderer copies A→C after the pass (A wins over B). A written by a feedback shader IS next frame's C.
- A feedback trail `col + prev*k` written without tone map settles at 1/(1-k)× and blows out — use a convex mix.
- Real-GPU visual QA is external; the Cloud VM has no WebGPU. Do not claim looks.

## WGSL header (copy format from public/shaders/crt-tv.wgsl)
```
// ═══════════════════════════════════════════════════════════════════
//  <Name>
//  Category: <category>
//  Features: <truthful list incl. audio-reactive / mouse-driven / upgraded-rgba>
//  Complexity: <Low|Medium|High>
//  Upgraded: 2026-09-28
//  Ideas: <idea 1>; <idea 2>; <idea 3>
//  A packing: <what A holds and how C is read back>
// ═══════════════════════════════════════════════════════════════════
```

## JSON
`params` byte-exact (ids, names, defaults, min/max/step, mapping). `updatedParams` aligned additively only (labels may be
corrected if HEAD label is wrong — say so). Description updated truthfully to name the ideas. `features` gets
`upgraded-rgba` only with ACES + implemented ideas; `audio-reactive` / `mouse-driven` only if true.

## Forbidden everywhere
New extraBuffer springs; generic ripple shockwaves on effects that do not own the pointer; IQ cosine palettes; oil-slick
chroma; any idea listed in the card's FORBID; editing any file other than your own .wgsl + .json.
