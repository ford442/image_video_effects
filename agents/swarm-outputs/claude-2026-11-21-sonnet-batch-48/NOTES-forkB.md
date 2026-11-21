# NOTES — fork B (cyber-focus, pixel-focus)

Cards, interrogation and admission: `BRIEFS-forkB.md` (written before the WGSL). Baseline = worktree file at fork start (prelude-migrated, pixel-identical to origin/main 2e876e2e), snapshotted to the scratchpad `b/` dir. VM = SwiftShader: **structural + render checks only, no visual-QA claim.**

Both files are display pass-through filters (the in-focus pool must return the source pixel), so **no ACES** was added — the same call `pp-sharpen` made in its 2026-11-09 rescue. A packing is HEAD's: display RGBA (A = finalColor), C never read, depth passed through.

---

## cyber-focus  (first pass; header gains `Upgraded: 2026-11-21`, `Ideas:`, `A packing:`, `Rescues:`)

**KEPT VERBATIM:** 4 params/roles (radius, blur, glitch, aberration); bass→radius, mids→glitch/aberration, treble→packet glow/offset; aspect-correct aperture + held ×1.35; click clarity rings; `scanPacket` formula; 20×20 hash-gated block offsets (same magnitude formula — lifted into `glitchOffset()` unchanged); 3×3 box lattice with R/B split; defocus alpha falloff; cyan packet tint; depth pass-through.

**ADD (where to point in the diff):**
1. `// ── Idea 1: block-DCT quantization (§12.2B)` — per 8-px macroblock (×floor(resY/540), so 16 px at 1080p): 4 quadrant taps at the block-centre glitch offset → luma DC/H/V/diag, `q = round(x/Q)·Q` with Q×1/3/5 by frequency, chroma DC-only (`qC = 1.5Q`). Q = (0.015 + 0.12·glitch·blockMask)·per-block hash(0.5..2.5)·(1 − 0.85·keyframe-packet). Applied as luma 0.6 / chroma 0.3 blend onto the blurred pixel (first try replaced the whole pixel and erased part of the R/B fringe; a pure quantization-error variant read as confetti noise — both rejected). Gated by `smoothstep(0,0.3,glitch)`, so glitch = 0 is HEAD's look.
2. `// ── Idea 2: luma-weighted defocus (bokeh pooling)` — per-tap weight `1 + 3·smoothstep(.55,1,luma)·focusMask`, normalised by Σw. Zero extra loads.

**Rescues:** R1 texel-centre uv (HEAD `gid/res` sampled texel corners → the "crisp" pool was a half-pixel bilinear blur, depth read on a boundary). Visible default look change: crisp pool is now exact-source; far field gains block banding.
**Not touched:** JSON `features` still carries HEAD's `fast-motion` tag (not opted into a brief — left, flagged for the coordinator); `params` and `x-meta.upgrade.params` untouched; `description` extended (visible behaviour changed).

**Diff vs HEAD (SRC=tex, 384², 6 fr):** defaults — 94% of pixels move >0.01 (62.6% >0.05; the synthetic source has per-pixel noise so the half-texel rescue alone moves 84% >0.01 even with blur/glitch/aberration = 0 — that number is the rescue, not the ideas). glitch = 0 — 82.8% >0.01 / 11.8% >0.05 (Idea 2 + rescue).
**Timing (interleaved HEAD/new, min-of-drained-frames, median of per-round ratios; box is shared with other forks so single rounds swing 0.4×–2.3×):** worst case (glitch 1, blur .8, tiny aperture → almost the whole frame defocused) median **1.11×** (9 rounds), defaults **1.20×** (9 rounds) — both ≤ 1.3 cap. **Trimmed once:** the first cut measured 1.52× in the worst case because every pixel re-evaluated a second `glitchOffset` (3 sin), a block-level scan packet (sin + `pow`) and two `cos`; the macroblock taps now reuse the pixel's own `offset`/`scanPacket`, and the cosine basis is the odd polynomial √2·sin(πt/2) (exact at the quadrant taps, ≤ 0.0064 at the block edge). Look re-checked after the trim (unchanged).
**Loads:** HEAD 27 loads per defocused pixel; new +4 (macroblock taps) only when glitch > 0 → ≤ +15% loads in the defocused region; Idea 2 adds ALU only.
**Gates:** precommit 1/1, naga-wasm 1/1 (0 known/0 new), dead sliders 0 (all four read), extraBuffer audit pass (0 violations). Renders: NaN 0 at defaults, all-zero params, all-max params + audio 1,1,1 + held pointer at the frame corner + two ripples, and 1088² (block 16).
**Not verified:** real-GPU look and timing; behaviour on real HDR/video; whether 8 px macroblocks read well at 4K (scales to 32 px by the floor rule).

---

## pixel-focus  (creative first pass; `Upgraded: 2026-06-28, 2026-11-21`, `Ideas:`, `A packing:`, `Rescues:` added)

**KEPT VERBATIM:** 4 params/roles incl. Aberration's 0.05 gate and `+treble·0.1`; density 50..500 with bass/mids/bin1–4 shimmer and far-depth coarsening; depth-at-mouse radius ×0.7..1.3, held +15%; focus smoothstep + click rings (radius/width/decay unchanged); lens rim; alpha = `baseColor.a·(focus·0.6 + luma·0.3 + 0.1)`; depth pass-through; A = finalColor.

**ADD:**
1. `// ── Idea 1: Cauchy dispersion about the lens axis (§12.2F)` — `cauchyScale(B)` n(λ)=1+B/λ² at 650/550/450 nm relative to green (R<1, G=1, B>1); R and B are fetched at `axis + (quad − axis)·s_c`, axis = pointer. B = chromatic·0.0127 (≈ HEAD's ±0.01 uv at field radius ≈ 0.5). Radial, zero on-axis, asymmetric — HEAD was a constant symmetric horizontal ±0.01 shift. Gated exactly as HEAD (`step(0.05, chromatic)`), now by a uniform `if` so the two extra loads vanish at the default (Aberration default is 0).
2. `// ── Idea 2: CFA zipper (§12.2A)` — luma from the mosaic cell, chroma from the 2×2 quad (`floor(uv·density/2)·2 + 1`): `colPixel = quad + (Y(cell) − Y(quad))`, clamped ≥ 0. Visible at the default, independent of the Aberration slider.

**Rescues:** R1 texel-centre uv; mosaic now samples the cell **centre** (`(floor(uv·density)+0.5)/density`) — HEAD sampled the cell corner (bilinear mix of 4 texels, whole mosaic offset by half a cell relative to the source, visible as a jump at the focus seam at low density). Default look changes slightly (mosaic is source-aligned).
**Considered, rejected:** foveated cell-size rings (reads as reimagining the mosaic grid); Brown–Conrady (a second lens row on a 2-idea card).
**Not touched:** `params`, `x-meta.upgrade.params`, `features` (HEAD's `upgraded-rgba` tag is HEAD's); `description` extended.

**Diff vs HEAD (SRC=img, 384², 6 fr):** defaults 36.7% of pixels >0.01 but only 0.9% >0.05 (mean |d| 0.011 — the rescue's half-cell shift plus quad chroma; deliberately subtle at the default density); coarse mosaic (Block Size .97, radius .15) + Aberration 1: 81.9% >0.01, 39.5% >0.05. cyber-focus on the same source (defaults): 68.7% >0.01, 15.1% >0.05.
**Timing:** defaults median **1.03×**, Aberration = 1 median **1.16×** (9 rounds each, interleaved; box shared with other forks, single rounds swing 0.4×–1.9×) — within the 1.3 cap, no trim needed.
**Loads:** default 4 → 3 (base, cell, quad); aberration on 4 → 5.
**Gates:** precommit 1/1, naga-wasm 1/1, dead sliders 0, extraBuffer pass. Renders NaN 0 at defaults, zeros, all-max + audio + ripple + pointer at the frame edge, chromatic exactly 0.05 + treble 1.
**Not verified:** real-GPU look/timing; how the zipper reads on real photos at the default density (cells are ~1.4 px on a 384 px frame, ~4 px at 1080p — subtle by design at the default, clearly visible at Block Size ≳ 0.8).
