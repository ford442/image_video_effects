# Upgrade Notes — Grok (`cursor/reveal-twelve`, 2026-10-27)

Twelve pointer-led reveal shaders. Idea cards are in `BRIEFS.md` (written first). Each file keeps its previous mechanism and gains two ideas. Saved `params` are byte-exact.

Ten pasted headers were migrated with `migrate_to_prelude.py` (`sonar-reveal`, `codebreaker-reveal`, `sonar-pulse`, `blueprint-reveal`, `sketch-reveal`, `night-vision-scope`, `motion-revealer`, `thermal-touch`, `digital-reveal`, `neon-flashlight`). `pixel-reveal` and `x-ray-reveal` already included the prelude. That swap is not the upgrade.

Dead `extraBuffer[133..138]` springs were removed from `codebreaker-reveal`, `sonar-pulse`, `night-vision-scope`, and `digital-reveal`. The CPU re-uploads that range as zeros every frame, so the spring was either a no-op or one Euler step off the origin. The pointer is the raw cursor. That is a fix, not an idea.

`codebreaker-reveal`, `sonar-pulse`, `night-vision-scope`, and `digital-reveal` no longer read `plasmaBuffer[1..]`. Those bins are never uploaded. The shimmer is a phase of `plasmaBuffer[0]`. Dead-bin fix, not an idea.

`codebreaker-reveal` display is now ACES. It was already tagged `upgraded-rgba`. `sonar-pulse` display is now ACES. `thermal-touch` stores raw heat in A.r and tone-maps only the display write. The old write was tone-mapped colour read back as heat.

Real-GPU visual QA was not run. This VM has no hardware GPU.

Gates: Naga 12/12, extraBuffer clean, dead sliders clean (12 files, 0 new), `generate_shader_lists.js`. Vitest 169 files, 1435 passed, 1 skipped. `SKIP_WASM_BUILD=1 npm run build` succeeded.

## Per shader

### sonar-reveal
- Kept: three detuned rings, click shocks, PPI arm and afterglow, contact blips, outward echo. A stays ACES display RGBA.
- Added: fixed range rings at 1/3 and 2/3 of Reveal Size; traveling rings widen with distance. Edge Softness is still the near width.
- Formula: none.

### codebreaker-reveal
- Kept: disc, click bursts, column rain, cell glyphs, blink. Bass still widens the disc.
- Added: white head and exponential tail on each falling cell; the decrypt hole is stored in A.a and closes with Rain Speed.
- Formula: none.

### sonar-pulse
- Kept: sine pulse, secondary beat, chromatic echo, click pings, depth attenuation.
- Added: phase speed `sqrt(tanh(k)/k)` so low Frequency runs ahead; amplitude `1/sqrt(1+d²)`.
- Formula: deep-water dispersion (§12.2D).

### blueprint-reveal
- Kept: Sobel, bold and thin pens, dashed hidden lines, ink mask in C.r, cyanotype, depth hatch.
- Added: every fifth grid line is heavier; a small circle and cross at the pointer, on the sheet only.
- Formula: none.

### pixel-reveal
- Kept: block memory (`10 + level`), decode ladder, Bayer colour ladder, held invert, scanlines, luma threshold.
- Added: hidden pixels above the threshold take the brighter tap one block to the right; a dark seam on the coarse cell edge.
- Formula: none.

### sketch-reveal
- Kept: gradient hatch, three tonal layers, paper tooth, wash in C.g, dried rim, smudge.
- Added: a dark contour on the existing edge; mid-wetness is speckled by the existing tooth.
- Formula: paper granulation (§12.2C).

### night-vision-scope
- Kept: scope disc, barrel pinch, green luma, MCP sparks, bloom, click ring, vignette.
- Added: green holds last frame's green, stronger with Brightness; stable vertical streaks under the temporal grain. Noise Grain scales both.
- Formula: none.

### motion-revealer
- Kept: Sobel tensor, frame difference, six-tap streaks, click fronts, cosine glow.
- Added: streaks follow the tensor only where coherence is high; C.a low-passes motion so the reveal holds after the motion stops.
- Formula: structure-tensor coherence (§12.2A).

### thermal-touch
- Kept: blackbody ramp, local glow, luma floor, held radius, bass on intensity, mids on shimmer, ambient mix, cooling.
- Added: 9-point laplacian on exact C.r; inverse-square pointer and click heat; isotherms on the plate. A.r is raw heat.
- Formula: isotropic 9-point Laplacian (§12.2D); soft inverse-square (§12.2F).

### digital-reveal
- Kept: glyph bars and dots, column speeds, mask decay in C.r, click blobs, held brush, depth weight.
- Added: hash-length drops with gaps; the reveal wipes each glyph from the top of its cell.
- Formula: none.

### x-ray-reveal
- Kept: Beer-Lambert plate and bone window, Sobel, collimator and crosshair, dose mottle, click field.
- Added: transmission falls along +x inside the lens; faint vertical grid lines masked to the field.
- Formula: none.

### neon-flashlight
- Kept: umbra and penumbra, edge light, specular catch, cone ribs, sweep, held squeeze, click fronts, depth-edge alpha.
- Added: core brightness is `I/(d²+r0²)` with r0 from Beam Radius; the umbra desaturates toward white and the penumbra keeps the neon hue.
- Formula: soft inverse-square (§12.2F). Shared only with thermal-touch.
