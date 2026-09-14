SHADER: gen-luminous-fluid-chladni-resonator
IDENTITY: Bioluminescent liquid Chladni plate: curl-fluid warped multi-mode Chladni figures, Voronoi ridge veins, blackbody warm/cool OkLab glow on nodal lines.
KEEP VERBATIM: hash21, noise, fbm, curl2D, voronoiRidge, chladni_multi, blackbodyRGB, OkLab helpers, aces, ign, acesToneMap; n/m bass modulation, mouse damping, settle mix, warm/cool color build, alpha formula core; slider mappings (Mode N, Mode M, Fluidity, Glow Intensity).
ADD (2 native ideas):
  1. Sand accumulation on nodal lines (sandGrains): 180-cell grain lattice; grains are packed where plate displacement vanishes, sparse airborne grains flicker over antinodes (treble agitation); warm sand tint scaled by Glow.
  2. Faraday subharmonic ripples (faradayRipples): square standing-wave lattice at half the drive frequency, gated by a bass threshold (smoothstep 0.35..0.8) and confined to antinodes; feeds back into c_val and adds a cool shimmer.
FLOOR FIXES: textureSampleLevel(dataTextureC).r -> clamped textureLoad, and prior field now derived from A alpha (nodal-ness) so feedback is consistent with A holding display RGBA; audio clamped 0..1, bass intensity gain reduced 1.0 -> 0.5; added click ripples (circular flexural waves, min(config.y,50)); mouse held widens the finger damping zone; depth now plate displacement (was passthrough of input depth); pow guarded with max(0); config.z/w only resolution/aspect (no fake audio); no extraBuffer use; no dataTextureB writes; JSON params array + features added, workgroup_size aligned to WGSL 16,16,1.
FORBID: writing dataTextureB, extraBuffer use, replacing Chladni motif, generic noise overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x,y,z,w live
