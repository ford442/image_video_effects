SHADER: gen-ghost-flame
IDENTITY: advected temperature/fuel flame sim rendered through a ghost blue-cyan blackbody palette with a wick column, chemiluminescent ignition band, smoke fringe, cyan age trails and temperature-driven translucency.
KEEP VERBATIM: hash/snoise3/fbm3 kernel; velocityField; advection + Laplacian diffusion + approx vorticity; combustion (ignition 0.15, burnRate from Flame Height); height cooling; base fuel feed; mouse heat + ripple bursts; blackbody/ghostFlameColor palette; smoke/glow/age tint; soft tone map + CA + ACES; alpha curve; slider roles (Flame Height, Turbulence, Cooling Rate, Diffusion); saved params; extraBuffer[133..134] bass/RMS envelopes.
EXISTING IDEAS (2026-09-06):
  1. base wick column (thin Gaussian fuel stem)
  2. ignition chemiluminescence (blue band at ignition temperature)
ADD:
  3. Buoyant puffing pinch-off — a travelling cooling wave along the flame axis (frequency nudged by mids, depth by Flame Height) periodically necks the column so flame packets detach and drift off; native because real buoyant diffusion flames flicker by exactly this ~10 Hz pinch-off, and it acts on the sim's existing cooling term.
  4. Schlieren heat haze — the temperature gradient from the already-loaded 4-neighbour C taps draws faint pale refraction fringes in the cool air around/above the flame (scaled by Diffusion), and depth becomes a truthful thermal relief; native because hot-gas density gradients are what a ghostly flame visibly bends.
FORBID: spring cursor, click shockwave rings, IQ cosine palette, conveyors, new particle system, replacing the palette or sim, dataTextureB use.
A PACKING: raw sim state (unchanged): A = (temperature, fuel, velocityX, age); C read via exact textureLoad as fields. ACES only on writeTexture.

## Notes
- Kept verbatim: noise/fbm kernel, velocityField, advection/diffusion/vorticity, combustion, height cooling, base fuel feed, Ideas 1-2 (wick, chemiluminescence), mouse heat + ripple bursts, palette/glow/smoke/age tint, soft tone map + CA + ACES, alpha curve, slider roles, saved params (JSON params byte-exact), extraBuffer[133..134] envelopes.
- A packing: unchanged raw sim state (temperature, fuel, velocityX, age); C read only via exact textureLoad; ACES only on writeTexture; no textureStore(dataTextureC).
- Idea 3 (buoyant puffing pinch-off): public/shaders/gen-ghost-flame.wgsl L256-263, right after height cooling. Travelling sin^6 cooling wave along +y (advection direction), snoise3 phase wobble, mids speed it up, Flame Height scales neck depth, RMS deepens it.
- Idea 4 (schlieren heat haze): L307-313 (gradient from existing left/right/up/down C taps, resolution-normalized, fringes in cool air, Diffusion scales strength, treble brightens), alpha gains haze*0.12 (L~334), depth thermal relief L357-359.
- Floor fixes: depth was a pass-through of input depth; now a truthful thermal relief. JSON features gained "audio-reactive" (plasmaBuffer[0] drives height/turbulence/puffs/haze) and "mouse-driven" (pointer heat source). Audio source, semantic alpha, ACES, 13 bindings, 16x16 already correct; all 4 sliders live; resolution division guarded with max(res.y,1).
- Gates: naga "Validation successful"; wgsl_precommit_gate --files 1/1 passed, 0 extraBuffer violations. No GPU visual QA.
- Pre-existing quirk left alone: base fuel feed uses uv.y<0.15 while first-frame seed sits at uv.y=0.92 (identity-preserving; not changed).
