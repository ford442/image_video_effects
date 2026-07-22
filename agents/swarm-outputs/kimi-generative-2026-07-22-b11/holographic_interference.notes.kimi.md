# Notes: holographic_interference (Visualist upgrade, 2026-07-22, batch 11)

**Role:** Visualist
**Shader:** `public/shaders/holographic_interference.wgsl` (v2 → v2.1)
**JSON:** `shader_definitions/generative/holographic_interference.json` (added `updatedParams` + `"updated": true` only; no other fields touched)

## Key changes

- **Animated laser speckle:** new `animatedSpeckle()` — temporally jittered cell-hash grain (coarse+fine mix), jitter amplitude scaled by treble (`plasmaBuffer[0].z`). Accumulated per coherent source at different scales/time offsets, then modulates fringe intensity via a treble-gated `shimmer` term. Real holograms shimmer; flat fringes read fake.
- **IQ cosine palette thin-film tint:** new `iqPalette()` (classic a + b·cos(2π(c·t+d))) keyed on `filmThickness * 0.22 + contrast * 0.3 + time * 0.015`, blended at 0.3 mix — thin-film hues sweep holographically while the original R/G/B fringe dispersion stays dominant.
- **Mouse parallax:** mouse offset from center now tilts the reference-beam angle (`mouseTilt = (mouse - 0.5) * (0.55, 0.3) * π`), so the interference field shears with viewpoint like a real holographic plate. Mouse still also moves the virtual object.
- **Slider rewiring (saved-preset contract kept — same ids/defaults/min/max/step/mapping):**
  - `zoom_params.x` Film Thickness → object-beam path length (unchanged mapping, still physically meaningful).
  - `zoom_params.y` Wave Scale → laser wavenumber `k` (unchanged).
  - `zoom_params.z` Depth Weight → **now actually used** (was declared but dead): gates depthFactor strength and the parallax attenuation mix.
  - `zoom_params.w` Chromatic Aberration → R/B fringe dispersion split (unchanged).
- **Fine carrier fringe:** high-frequency luminance comb (`cos(contrast*48 + grain*6 + t)`) phase-dithered by the animated grain, subtle ±8% modulation.
- **Bloom widened:** mids now add sparkle to the constructive-interference HDR bloom (previously `mids` was sampled but unused).
- **Tone map dedup:** the old double ACES pass (`aces()` then `acesToneMap()`) consolidated into a single `acesToneMap(color * 1.35)`; removed the duplicate `aces()` helper.
- Core algorithm preserved: 3 coherent sources, spherical object beam vs planar reference beam phase accumulation, per-channel chromatic fringe dispersion, semantic alpha, writes to writeTexture/writeDepthTexture/dataTextureA every frame.
- Canonical 13-binding layout and `@workgroup_size(16, 16, 1)` untouched; no binding 13 (no history ring).

## Line count delta

- Before: 144 lines → After: **194 lines** (+50, bottom edge of the +50/+90 window).

## QA flags

- All constants (shimmer gain 0.35 + treble·0.45, tint mix 0.3, tint key weights, carrier ±0.08, exposure 1.35, mouse tilt 0.55/0.3·π, parallax atten gate 0.85+0.15) are **eyeballed, not visually verified** — this VM has no GPU adapter, so visual QA is deferred to a GPU-capable environment.
- Gate: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/holographic_interference.wgsl` → **PASS** (exit 0, naga OK, bindgroup compatible, 0 warnings).
- JSON validated with `json.load` (parses; keys as expected).
- Caveat: at `depthWeight = 0` depth modulation is fully bypassed (depthFactor = 1) — intentional, slider now means "how much depth matters".
