SHADER: gen-luminous-cauldron
IDENTITY: Radiant alchemical cauldron: violet/amber convection swirl in a round pot, heat-shimmered caustics, rising SDF bubble froth, treble spark glitter.
KEEP VERBATIM: sat, hash21/hash22, noise, fbm, bass_env, acesToneMap, sdSphere, causticPattern, heatShimmer; bowl/swirl/convectionWaves, 3-layer bubble grid, sparks, base color stack, C feedback mix; slider mappings (Boil Rate, Convection, Foam, Radiance).
ADD (2 native ideas):
  1. Minnaert bubble-collapse capillary rings: per-surface-cell bubbles burst on staggered phases and radiate decaying rings with fine capillary ripple (collapseRing); bass lowers the burst threshold, Foam scales strength. Click ripples drop a large collapsing bubble ring at the click.
  2. Meniscus rim caustic at the pot lip: bright double band just inside the bowl edge (meniscus climb + focused caustic line), wobbling with convection, flickering via causticPattern, lifted by Radiance and treble.
FLOOR FIXES: extraBuffer[0] (out of range) bass envelope relocated to guarded extraBuffer[133]; textureSampleLevel(dataTextureC) -> clamped textureLoad; dataTextureA was storing data channels (waves/bubbles/sparks/caustics) -> now final display RGBA identical to writeTexture; alpha was 1.0 -> bowl coverage + froth + collapse + rim + glow; depth was 0 -> surface height; audio clamped 0..1 with controlled gains; added click ripples (min(config.y,50)); mouse-held (zoom_config.w) stirs extra swirl and boils faster; config.z/w only used for dims/aspect (no fake audio); no dataTextureB writes; JSON params array + features added.
FORBID: writing dataTextureB, extraBuffer outside 133..138, replacing the pot/bubble motif, generic bloom/palette overlays.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x,y,z,w live
