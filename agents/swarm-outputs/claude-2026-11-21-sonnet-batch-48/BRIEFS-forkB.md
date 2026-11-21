# BRIEFS — fork B (cyber-focus, pixel-focus) — written BEFORE any WGSL edit

HEAD = worktree file at fork start (post-prelude-migration, pixel-identical to origin/main 2e876e2e). Both files are **display pass-through filters**: inside the focus pool the output is the source pixel. Therefore **no ACES** (same call `pp-sharpen` made in its 2026-11-09 rescue: an ACES fit over an SDR photo repaints the in-focus region). A packing stays HEAD's: display RGBA (A = finalColor), C never read.

HEAD runs (SwiftShader, SRC=tex / SRC=img, 384², 6 frames): both compile, NaN 0, not blank. HEAD defects found (rescues):
- **R1 (both)** `uv = gid.xy / res` (no +0.5): every `textureSampleLevel(readTexture, linear, uv)` lands on a texel *corner*, so the "crisp" pool is a half-pixel bilinear blur and the pixel-focus mosaic samples cell corners. Fix: texel-centre uv `(gid + 0.5) / res`; mosaic samples cell centres.
- No dead sliders (all four read in both). Audio reads are `plasmaBuffer[0].xyz` (+ `[1..4].x` bins in pixel-focus, valid since VJ-Studio all-slot audio). No ACES-on-negative, no illegal stores.

---

## cyber-focus

```
SHADER: cyber-focus
IDENTITY (one sentence): a mouse-tracked focus aperture that keeps the picture crisp inside and turns everything outside into a blocky-glitched, chromatically fringed, box-blurred "corrupt feed", with scan packets and click rings of clarity.
KEEP VERBATIM: 4 params + roles (radius → aperture, blur → 3×3 lattice spacing, glitch → block-offset gate, aberration → R/B horizontal split); bass→radius, mids→glitch/aberration, treble→packet glow/offset; aspect-correct circular aperture, heldFocus ×1.35; clickClarity rings; scanPacket (sin(uv.y·75 − t·15)^14); 20×20 hash-gated block offsets (same magnitude formula); 3×3 box lattice with per-tap R/B split; defocus alpha falloff; cyan packet tint; depth pass-through; A = finalColor.
ADD (2):
  1. Block-DCT quantization (§12.2B) — the "blocky glitch" is a corrupt block stream; a real one also shows codec banding *inside* the blocks. Per 8-px (scaled ×floor(resY/540)) macroblock: 4 quadrant taps → DC + H + V + diag cosine coefficients of luma, `q = round(x/Q)·Q` with Q growing with frequency (DC 1×, AC 3×, diag 5×, JPEG-style) and chroma kept DC-only (4:2:0-style block colour). Q = f(glitch · focusMask) → bitrate starves with distance from the aperture; per-block hash varies Q (some blocks starve harder); a scan packet drops Q (keyframe refresh band). The macroblock's glitch offset is taken at the block centre with the *same* offset function as the existing 20×20 gate.
  2. Luma-weighted defocus (bokeh pooling; tactic 2 + 8) — the existing 3×3 box is a uniform average, but real defocus is radiance-weighted: highlights dominate their neighbourhood. Per-tap weight `1 + 3·smoothstep(.55,1,luma)·focusMask`, weights normalised (energy conserved, nothing added) → specular highlights pool into soft cyber-bokeh outside the lens instead of being averaged away.
FORBID on this file: new spring/ripple/IQ palette, hologram scan, neon edge pop, any new param, replacing the box lattice, Cauchy/Brown–Conrady/CFA (pixel-focus owns them).
A PACKING: display RGBA pass-through (HEAD's; no ACES — see header note).
```

**§12.1 interrogation.**
- T1 deepen kernel: the 3×3 box is a uniform operator; next-better approximation of defocus = radiance-weighted taps (Idea 2). The block offset gate is a block-domain operator; the next-better block operator is quantizing the block's own coefficients (Idea 1).
- T2 physics one step further: block-corrupt streams show DCT quantization banding and 4:2:0 chroma blocking inside blocks, not just displaced blocks (Idea 1); defocus pools highlights (Idea 2).
- T3 promote an intermediate: `blockSeed` (hash per cell) only gates the offset → also seeds per-block Q; `focusMask` (distance) → bitrate; `scanPacket` → keyframe refresh (lower Q).
- T6 history: the file writes A = finalColor but never reads C. Adding a C read would change what A means to the next frame; no history idea is added (stated, not hidden).

**§12.4 admission.** Idea 1 = §12.2B "Block DCT quantization": family = distortion/glitch (block-domain interference) ✓; consumes `focusMask`, `glitchIntensity`, `scanPacket`, the offset function and readTexture taps the file already has ✓; deletion test: remove it → exactly the HEAD effect; remove the aperture/blur/aberration and keep only the codec → no longer a focus aperture (identity lives in the mask) ✓. Idea 2: not a table row — tactic output (physics + energy accounting), consumes the 9 tap triples the loop already fetches (zero extra loads) ✓. Same row on only this file ✓ (claims: Block-DCT → cyber-focus only).

---

## pixel-focus

```
SHADER: pixel-focus
IDENTITY (one sentence): a mosaic over the whole frame with a clear focus pool around the pointer (depth-tuned radius, click rings of clarity, spectral density shimmer, lens rim, optional R/B aberration on the mosaic).
KEEP VERBATIM: 4 params + roles (Block Size → 50..500 cells, Focus Radius, Edge Hardness, Aberration with its 0.05 gate and treble·0.1 term); depth-at-mouse radius ×(0.7..1.3), held +15%; focus smoothstep; click rings (same radius/width/decay); bass/mids/bin1–4 density shimmer + far-depth coarsening; lens rim; alpha = baseColor.a·(focus·0.6 + luma·0.3 + 0.1); depth pass-through; A = finalColor.
ADD (2):
  1. Cauchy dispersion about the lens axis (§12.2F) — the Aberration slider today is a constant ±0.01 uv horizontal R/B shift (axial, symmetric, same at the pool edge and the screen corner). A real lens' lateral CA is *radial* from the optical axis (= the pointer, the centre of the focus pool), zero on-axis, growing with field radius, and its spacing follows n(λ) = 1 + B/λ² so blue bends more than red (asymmetric, non-linear). R/G/B are sampled at `axis + (cell − axis)·s_c` with s from Cauchy(650/550/450 nm), B = chromatic·0.0127 (≈ HEAD's ±0.01 at r≈0.5). Slider role, 0.05 gate and treble term kept.
  2. CFA zipper (§12.2A) — pixelation is a sensor. Each mosaic cell keeps its own *luma*, but chroma is demosaic-shared across the 2×2 cell group (`floor(uv·density/2)·2`): out = Y(cell) + [chroma(group) − Y(group)]. Cell-scale colour fringes/aliasing on fine edges, Bayer-style, visible at the default (independent of the Aberration slider). Constant strength 0.7 (the rest stays plain cell colour).
FORBID on this file: new spring/ripple/IQ palette, scanlines, changing the saved param meanings, a second depth system (it already has one), foveated cell-size rings (considered: reads as a second reimagining of the mosaic grid → rejected), Block-DCT (cyber-focus owns it).
A PACKING: display RGBA pass-through (HEAD's; no ACES).
```

**§12.1 interrogation.**
- T1 deepen kernel: mosaic = nearest-cell fetch; next-better approximation of "a camera's coarse pixel" = a cell that has its own luma but shares chroma with its Bayer quad (Idea 2).
- T2 physics one step further: the file already models a lens (focus pool, rim, aberration). First-order side effect of a real lens' CA: radial, wavelength-ordered, zero on-axis (Idea 1).
- T3 promote an intermediate: `mouse`/`dist`/`aspect` (already computed) give the optical axis & field radius for free; `density` gives the 2×2 group size; `colClear`/`baseColor` untouched.
- T6 history: A = finalColor, C unread → none added (stated).

**§12.4 admission.** Idea 1 = §12.2F Cauchy dispersion: family = lighting/optical; this shader already *is* a lens with an aberration slider (one-sentence justification) ✓; consumes `mouse`, `chromatic`, `pixelUV` ✓; deletion test ✓ (remove → HEAD's symmetric shift; keep only dispersion without mosaic/pool → not this effect). Idea 2 = §12.2A CFA zipper: pixelation is the effect, cell/group quantisation already computed from `density` ✓; consumes the same 3 fetches (+1) ✓; deletion test ✓. Claims: Cauchy / CFA zipper → pixel-focus only; Brown–Conrady not used.

Cost expectation: cyber-focus +4 loads and a few ALU only on defocused pixels when glitch>0 (HEAD 27 loads there); pixel-focus 4 → 5 loads. Cap ≤ ~1.3×.
