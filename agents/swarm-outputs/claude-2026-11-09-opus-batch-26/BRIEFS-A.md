# BRIEFS — fork A (written before WGSL edits)

SHADER: byte-mosh (live 2-pass graph: byte-mosh-mangle → byte-mosh-render; byte-mosh.wgsl is the orphaned single-pass file, not loaded by the definition/registry, left untouched)
IDENTITY: block-hashed bitwise corruption — xor with a position pattern, bit rotation (Bit Shift), byte mask (Operation Mix) — composited over the source in a render pass.
KEEP VERBATIM: block grid from Block Size, hash-vs-Error-Rate block selection, xor/rotate/mask op chain, 4 param roles, graph shape (mangle writes A, render reads C).
RESCUE: mangle xor'ed the IEEE-754 bit patterns of r^g^b for EVERY pixel and bitcast back → whole frame collapsed to a hue-less purple/black field (source image unreadable even in clean blocks). Operate on an 8-bit RGB byte word instead; clean blocks pass through.
ADD:
  1. Motion-vector block copy — corrupted blocks fetch their pixels from a hashed, block-quantised displaced block (P-frame reuse), so the mosh carries picture content instead of pure noise.
  2. Bit-plane severity — each corrupted block mangles only its lowest N bits per byte (N 1..8 from a second hash + Error Rate); mild blocks keep the image with crunchy low bits, severe ones scramble fully.
  3. Macroblock seam ringing — render pass reads the mangle's corruption flag (C.a) of 4 neighbours; at clean/corrupt borders a decaying ±luma ring (DCT-style overshoot) plus treble-driven chroma slip.
FORBID: springs, ripples, palettes.
A PACKING: mangle → (moshed RGB 0..1, corruption flag); render → display RGBA (overwritten by mangle next frame).

SHADER: digital-decay-rgba
IDENTITY: block displacement corruption + chroma split over the image, with a 4-species reaction-diffusion bloom seeded by corrupted blocks.
KEEP VERBATIM: block hash/displacement, pixel jitter, aberration, scan/noise, 4-species RD + spectral tint, 4 param roles.
RESCUE: extraBuffer[133..138] spring is zeroed every frame → smoothMouse ≡ (0,0) → held burst / pointer RD injection only ever fired at the top-left corner. Use raw pointer.
ADD:
  1. Seam-born rot — RD species B/D are injected along the edges of corrupted blocks (block-boundary distance), so decay grows out of the macroblock seams.
  2. Bit-depth erosion — where RD B+D concentration is high the picture is quantised to fewer levels (8 → 2 bits), the organism literally eating colour precision.
  3. Macroblock chroma bleed — in corrupted blocks chroma is sampled at the block centre (4:2:0-style), luma stays per-pixel.
FORBID: new springs, palettes.
A PACKING: raw RD state (A,B,C,D) — unchanged.

SHADER: magnetic-luma-sort
IDENTITY: luma-gated pixels drift toward/away from the pointer magnet via exact-load trail advection.
KEEP VERBATIM: luma threshold gate, domain gate, dipole tangent, click vortices, decay mix, 4 param roles.
RESCUE: (a) A stored ACES display and C fed it back into mix → re-graded every frame (trails compress/dim). Store pre-grade colour in A; ACES only on writeTexture. (b) extraBuffer spring never persisted (zeroed each frame) — it was a no-op equal to raw mouse; removed the fake state.
ADD:
  1. Comparator sort taps — the upstream history read takes the brightest of 3 taps along the pull direction (a compare-swap step), so bright runs win and streaks look sorted, not blurred.
  2. Magnetic hysteresis — A.a stores trail energy; pixels that were already moving keep moving at a lowered luma threshold (remanence), so streaks persist past the gate.
FORBID: palettes, ripples beyond HEAD's.
A PACKING: pre-grade trail RGB (linear) + trail energy (hysteresis).
