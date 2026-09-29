# Broadcast-Signal Twelve — batch contract (2026-09-28)

Live law: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §3, §4, §8, §9). Bindings: `agents/WGSL_BUILTINS_GENERATIVE.md`, `docs/BINDING_CONTRACT.md`.

## Claimed IDs (one agent each — never touch another agent's file)
vhs-chroma-bleed, vhs-jog, vhs-tracking-mouse, signal-tuner, crt-scanline-damage, scan-distort, waveform-glitch, holographic-projection-failure, holographic-glitch, phosphor-decay, cyber-terminal-ascii, strip-scan-glitch

Selection: theme = broadcast / tape / tube signal degradation. 535 unclaimed candidates (no `^//  Ideas:` line, not in any
2026-09-2x batch folder, single-pass JSON url); 18 read in full; rejections in NOTES.md. Not touched: the concurrent
uncommitted `claude-2026-09-28-split-gen-twelve` files.

## Per-file floor (hygiene, not the upgrade)
Canonical 13 bindings, @workgroup_size(16,16,1), bounds guard; ACES on display RGB only; semantic alpha; dataTextureA is the
only feedback write (packing per card); exact `textureLoad(dataTextureC, coord, 0)`; audio only from `plasmaBuffer[0].xyz`
(or read-only FFT bins `extraBuffer[5..132]` guarded by `arrayLength`); saved `params` byte-exact; naga-clean;
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl` passes.

## Verified runtime facts that shape every card
- `extraBuffer[133..255]` is re-zeroed every frame (`audioDepth.ts:43-56`, `frame.cpp:84-97`): every "spring cursor" in these files is a no-op that reads state 0. **Floor:** replace springs with direct `zoom_config.yz`, delete the `extraBuffer` writes. Never build an idea on extraBuffer state.
- `plasmaBuffer[1..]` is never written: reads like `plasmaBuffer[rowBin]` are dead. Use `plasmaBuffer[0].xyz`; real FFT bins live in `extraBuffer[5..132]` (read-only, guard with `arrayLength`).
- `u.ripples[i].w` is 0; age = `time - ripple.z`; cap loops `min(u32(u.config.y), 50u)`.
- `pow(neg, 2.0)` is NaN — rewrite as `x*x`. `sin(uv.y*res.y*PI)` at texel centres is a constant (crt-scanline-damage's scanlines are dead).
- A written post-ACES and re-tone-mapped through C compounds (drift to ~0.73). Where a file mixes C history, store **pre-ACES linear** in A and ACES only on `writeTexture` (document on the `A packing:` line).
- Cloud VM has no GPU: structural gates only; visual QA is external.


## WGSL header (copy format from public/shaders/crt-tv.wgsl)
```
// ═══════════════════════════════════════════════════════════════════
//  <Name>
//  Category: <category>
//  Features: <truthful list incl. audio-reactive / mouse-driven / click-reactive / upgraded-rgba>
//  Complexity: <Low|Medium|High>
//  Upgraded: 2026-09-28
//  Ideas: <idea 1>; <idea 2>; <idea 3>
//  A packing: <what A holds and how C is read back>
// ═══════════════════════════════════════════════════════════════════
```

## JSON
`params` byte-exact (ids, names, defaults, min/max/step, mapping). `updatedParams` aligned additively only (labels/defaults may
be corrected if HEAD is wrong — say so in NOTES). Description updated truthfully to name the ideas. `features` gets
`upgraded-rgba` only with ACES + implemented ideas; `audio-reactive` / `mouse-driven` / `click-reactive` only if true.

## Forbidden everywhere
New extraBuffer writes of any kind; generic ripple shockwaves on effects that do not own the pointer; IQ cosine palettes;
oil-slick chroma; any idea listed in the card's FORBID; editing any file other than your own .wgsl + .json.
