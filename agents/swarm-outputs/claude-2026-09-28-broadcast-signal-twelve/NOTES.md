# Broadcast-Signal Twelve — NOTES (2026-09-28)

Per-shader notes are in `notes-<id>.md` beside this file (kept verbatim, A packing, idea line ranges, floor fixes, JSON, gates, GPU risks).
Cloud VM has no WebGPU: every "looks" statement is inference from code. Real-GPU visual QA is external.

## Selection

Theme: broadcast / tape / tube signal degradation. 535 unclaimed single-pass candidates (no `^//  Ideas:` line, not in any
2026-09-2x batch folder). 18 read in full by three reader agents; 12 claimed (CONTRACT.md). Concurrent uncommitted
`claude-2026-09-28-split-gen-twelve` files untouched.

## Rejected after full read (rescue list, not upgrades)

- `rgb-split-glitch` — code is a YCbCr 4:2:0 codec-damage effect (delayed chroma planes, herringbone, block ringing on block *centres*); name, JSON description and three slider labels describe a different shader. Needs a rename/rewrite decision, not ideas.
- `spectral-glitch-sort` — luma-gated directional smear; no sorting anywhere. Name ≠ code. Batch 58D stamp. NaN `pow` at the click tear.
- `data-moshing` — Batch 58D raw offset-field feedback (A = offset.xy, confidence, age); "motion-compensated" is a same-frame gradient, no P-frame bleed. Real mosh = rewrite. NaN `pow` in the click ring feeds A/C.
- `pixel-rain` — matrix rain (off-theme); scrolls upward (tail above head), audio×time phase jumps, per-column fract seam.
- `interactive-glitch`, `scan-slice` — sound but off-theme; alternates. scan-slice: only audio bins 1..4 ever used, all `plasmaBuffer[bin]` reads dead.

## Traps found in this cohort (see CONTRACT.md runtime facts)

- Every "spring cursor" in the Composer-batch files (`extraBuffer[133..138]`) is a no-op: the host re-uploads a zeroed 256-float scratch each frame. Removed, direct `zoom_config.yz` used.
- `plasmaBuffer[1..8]` "per-row voice / band bars" in waveform-glitch, signal-tuner, vhs-tracking-mouse, scan-distort, phosphor-decay read zero.
- `sin(uv.y * res.y * PI)` scanlines are a constant at texel centres (crt-scanline-damage).
- Post-ACES display stored in A and re-tone-mapped through C compounds (scan-distort, holographic-*, waveform-glitch, cyber-terminal-ascii): these now store pre-ACES linear RGB in A.
- phosphor-decay was near-black at HEAD (`finalRGB * alpha`, alpha≈0 below luma 0.55) and could latch a NaN via unguarded OkLab cube roots.
