SHADER: gen-prismatic-cyber-chrono-void-kitsune
IDENTITY: Nine-tailed cyber space-fox: cellular-perturbed glass body with rune lattice, nine smin'd waving tapered tails, hollow twisting rift tube with volumetric magenta density, gravity dust, fog, temporal glass smear.
KEEP VERBATIM: rot, smin, hash3, cellular, map (body/tails/rift/dust), calcNormal, marcher (0.5 step, rift density accumulation), rune pattern, tail neon shading, dust emissive, fog, 0.08*glass temporal mix.
ADD (2 native ideas):
  1. Kitsunebi fox-fire: one wisp per tail placed by inverting that tail's frame (same phase, wave and mouse bend as the SDF), so it sways with its tail; ray-point distance glow with white core + cyan-green halo, treble flicker, occluded by hit depth, flares on click shockwave.
  2. Cauchy-dispersed quantum-glass armour: n(λ)=A+B/λ² gives separate R/G/B refraction dirs around the original 0.9 eta (green = original); Glass Refraction scales B, per-channel faux background recombined.
FLOOR FIXES: fake audio u.config.y and click_shockwave=fract(u.config.y*0.1) removed -> plasmaBuffer[0].xyz clamped (bass tail/rune drive, mids tail glow/rune, treble fox-fire flicker); mouse fixed (zoom_config.yz was divided by resolution -> now uv*2-1, dead length>1.5 reset removed), held mouse bends 1.6x; real click ripples loop (shockwave rings that lash tails via tail drive); textureSampleLevel(dataTextureC) -> clamped textureLoad; Reinhard -> clamped ACES (feedback mixes in display space, matches A); alpha -> coverage (surface/rift mist/fox-fire/shock); header replaced; JSON params gained id/mapping, features added. No extraBuffer, no B write.
FORBID: replacing tails/rift/body, extraBuffer use, dataTextureB writes, scaling clicks by ripples[i].w, sampling C with filtering.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live (x tail spread+wisps, y rift density, z runes, w glass/dispersion/smear)
