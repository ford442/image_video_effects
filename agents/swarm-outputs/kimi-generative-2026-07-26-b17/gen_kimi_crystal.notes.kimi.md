# gen_kimi_crystal — Batch 17 Upgrade Notes (Kimi, Optimizer role)

## Line delta
- Before: **211** lines
- After: **286** lines (**+75**, within brief target 261–301)

## Changes per technique

### 1. OOB bounds guard (priority 1)
- Added the standard sibling guard at top of `main`:
  `if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }`
- Shader no longer relies on WebGPU OOB-store discard for edge invocations.

### 2. HDR safety: hue-preserving clamp + ACES
- New `hueLimit(c, maxVal)` helper: uniform scale-down when peak channel > 1.2 (hue preserved).
- New `acesToneMap` (Narkowicz fit), applied after `hueLimit(color, 1.2)` and before blending/store.
- Protects against edgeGlow + sparkle + mouseGlow pushing HDR > 1.

### 3. Spectral dispersion on Fresnel edge glow
- Added dispersion IOR constants `IOR_ICE_R/G/B = 1.31/1.32/1.33`.
- Edge glow split into 3 spectral Fresnel-Schlick samples (per-channel F0) with slightly
  offset edge distances (`abs(d ∓ 0.008)`) for cheap chromatic fringing on crystal edges.
- The scalar `fresnel` used by the transmission block is untouched (IOR_ICE = 1.31, verbatim).

### 4. Audio growth
- `bass = plasmaBuffer[0].x` → `bassGrowth = 1 + bass*0.6` pulses the growth cycle rate,
  plus a `sizePulse` term (`1 + bass*0.15*sin(...)`) on crystal size.
- Per-bin FFT shimmer: each hex row maps to engine bins 1..8 via
  `rowBin = 1 + ((rowIndex % 8) + 8) % 8` (negative-safe modulo); `rowFFT` drives a
  `rowShimmer` that brightens `interiorPattern` facets and adds a crystal-body glow term.

## Slider wiring (saved-preset contract preserved)
All 4 existing params wired via `u.zoom_params`, ids/defaults/min/max/step unchanged,
`updatedParams` index 0–3 written verbatim from brief:
- index 0 / `.x` — Grid Density → `gridDensity = mix(2,5,x)` (hex grid scale)
- index 1 / `.y` — Crystal Purity → `crystalPurity = mix(0.3,1,y)` (absorption + transmission)
- index 2 / `.z` — Growth Speed → `growthSpeed = mix(0.05,0.3,z)` (animation rate)
- index 3 / `.w` — Crystal Thickness → `crystalThickness = mix(0.1,1,w)` (Beer path length)
Mapping was already shader-specific (not generic boilerplate), so semantics kept; each
slider drives a real constant of the crystal algorithm.

## Binding compliance
- Canonical 13-binding layout preserved, no renumbering, no binding 13 added.
- `@workgroup_size(16, 16, 1)` kept.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- `textureSampleLevel(..., 0.0)` for sampler reads; no storage-texture sample misuse.
- `extraBuffer` declared but never written (no [0..132] violations).
- `plasmaBuffer` read-only: `[0].x` bass + `[1..8].x` FFT bins (read allowed per contract).
- No WGSL reserved keywords used as identifiers.

## Preserved verbatim (per CAUTION)
- Physical transmission block: `crystalMask`, Fresnel-Schlick with F0 from `IOR_ICE=1.31`,
  Beer absorption `exp(-k*path*mask)`, transmission product — unchanged.
- Odd-row hex offset logic (`i32(hexId.y) % 2 == 1` branches) — unchanged.
- Core hex grid, growth hash cycle, mouse glow, sparkle, palette, blend/depth logic — unchanged.

## QA flags
- `wgsl_precommit_gate.py`: PASS — 1 file, 0 failed, 0 warnings (naga binary unavailable
  in this VM → naga step skipped by the gate itself; bindgroup + workgroup checks ran).
- `audit_extrabuffer.py`: AUDIT PASS — 0 violations.
- `audit_dead_sliders.py`: AUDIT PASS — 0 dead sliders, 0 def errors.
- JSON definition written verbatim from the brief's fenced block; validated as parseable JSON.
- Not visually verifiable in this VM (no GPU adapter) — validated via gates only.
