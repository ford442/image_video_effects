# Upgrade Notes: data-slicer-interactive (Algorithmist, 2026-07-21)

## Line-count delta
- Original: **189 lines** → Upgraded: **240 lines** (**+51**, within the +50…+90 window; target band 239–279 ✅)

## Changes by domain

### Slider params (zoom_params.x/y/z/w, JSON updatedParams 0–3)
- Re-scoped the 4 wired params per brief: `x` = Slice Density (unchanged semantics: slice count 4→32), `y` = Displacement (now drives slice-offset magnitude 0.05→0.35, replacing the hardcoded `0.3`), `z` = Jitter Amount (new FBM jitter, 0→0.25 amplitude), `w` = Shockwave Strength (new ring amplification, 0→2.0).
- Slice width / FBM warp / color shift demoted to fixed internal constants (0.03 / 0.03 / 0.02) since the 4 slider slots were reassigned to the brief's updatedParams.

### Audio mapping
- Bass still drives slice density (`sliceCount * (1 + bass*0.5)`) — kept.
- **Mids now drive displacement magnitude**: `dispMag = mix(0.05, 0.35, p1) * (1 + mids*0.8)` (previously mids only modulated quantization frequency).

### Branchless FBM jitter (new)
- Added canonical `domainWarp()` helper (fbmLod-based, no new bindings).
- Per-slice smooth jitter: domain-warped fBM keyed on `sliceY`, blended into displacement via `mix` with `jitterBlend = clamp(jitterParam*1.5, 0, 1)` — zero divergent branches.

### Shockwave slice bursts (u.ripples)
- Ripple loop now accumulates a second field `shock`: a sharp `smoothstep(0.04, 0, band)` envelope pinned to the expanding wavefront, weighted by per-ripple `rp.w` strength (previously ignored) and age decay.
- `shock` amplifies slice offset (`offset *= 1 + shock`), chromatic split, torn-edge glow, feedback trail mix, and adds a white flash — locally intensifying slices as the ring travels.
- Fully branchless: `f32(bool)` masks + smoothstep, no if/else in the loop.

### Glitch aesthetics
- Torn-edge glow: hot rim (`edgeT`) pinned to the FBM-warped slice boundary, tinted (r 0.9 / g 0.55 / b 1.1), boosted by treble + shock.
- Scanline shimmer: subtle `sin(uv.y * res.y * PI)` brightness weave inside active slices.
- Branchless per-slice direction flip: `select(-1, 1, fract(sliceIndex*0.5) < 0.25)` blended at 0.8 for alternating slice travel.

### Interaction
- Gravity well is now aspect-corrected (`dMouse * vec2(aspect, 1)`) and boosted ×1.5 while mouse is down.

### Preserved
- Canonical 13-binding layout (no binding 13 — not previously used), `@workgroup_size(16, 16, 1)`.
- Core algorithm: slice construction, FBM-warped edges, early-exit passthrough, bass envelope readback via `dataTextureC.a`, radial CA, temporal feedback, ACES, semantic alpha, field caches in dataTextureA/B, depth passthrough.
- All writes to `writeTexture`, `writeDepthTexture`, `dataTextureA` (and B) every frame on both paths; all sampler reads use `textureSampleLevel(..., 0.0)`; no reserved-keyword identifiers.

## QA flags
- **Eyeballed constants** (no GPU in this VM — not visually verified): slice width 0.03, fbm warp 0.03, color shift 0.02 (demoted constants), jitter amplitude 0.25, shock ring width 0.04 / speed 0.5 / lifetime 1.2s (kept from original burst code), direction-flip blend 0.8, edge-glow tint weights, scanline shimmer 0.06.
- **No-GPU caveat**: validated via naga + bindgroup checker only; runtime look (esp. shock flash intensity and jitter blend) should be eyeballed on real hardware.
- `rp.w` (ripple strength) now consumed with a floor of 0.2 — if the engine ever writes 0-strength ripples they still contribute minimally; intentional to preserve the original burst feel.
- Slider re-scope: `zoom_params.y/z/w` semantics changed from (slice_width, fbm_warp, color_shift) to (Displacement, Jitter, Shockwave) per the brief's updatedParams — legacy `params[]` entries kept in JSON for compatibility as instructed.

## Validation
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/data-slicer-interactive.wgsl` → **PASS** (naga OK, bindgroup compatible, 0 errors/warnings).
- JSON parses cleanly (`json.load` OK), exactly 4 updatedParams at index 0–3.
