SHADER: gen-polar-rainbow-explosion
IDENTITY: Mouse-directed polar explosion of 36 neon rainbow rays, particle bursts, 3 spiral arms, center glow, bass-driven radial shock front (Mach split ahead/behind), treble ripple, heavy temporal trail.
KEEP VERBATIM: neonSpectrum, fbm/vnoise, ray loop (wavelength-scaled RGB ray widths, Mach ahead/behind split), particle bursts, spiral arms, center glow, shock glow ring, mouse-held burst, vignette, C feedback mix, CA offset, radius depth.
ADD (2 native ideas):
  1. Cauchy-dispersed click shock rings — each click (u.ripples, loop to min(config.y,50)) launches a polar front with per-channel radius age*v/n(lambda), n = 1 + 0.04/lambda^2, so red leads and violet trails; speed slider sets v, bass boosts.
  2. Descartes rainbow bows around the explosion origin — primary bow (red 42.3deg outside -> violet 40.6deg inside) and fainter reversed secondary (50.4 -> 53.4deg) mapped r = 0.5*tan(theta), Alexander's dark band darkening between them, faint inner-sky brightening; gain driven by mids and Intensity.
FLOOR FIXES: plasmaBuffer[0].xyz clamped 0..1; mids now used; A previously held pre-ACES HDR (different from writeTexture) -> same ACES display RGBA now written to writeTexture and dataTextureA; click ripples added (none before); legacy "Wolfram" header merged into contract header; Uniforms comment lists slider names. Already OK: 13 bindings, exact textureLoad C, no extraBuffer, no dataTextureB write, no fake audio, sliders x/y/z/w all live, JSON params/features already correct (unchanged).
FORBID: generic bloom/IQ palette overlays, renaming params ids (color_shift kept), writing dataTextureB, extraBuffer use, plasmaBuffer beyond [0].
COORDINATOR FIX: trail feedback decodes the stored ACES display via acesInverse(prev)/1.1 before the HDR mix, so the 75% persistence trail matches the pre-upgrade HDR trail.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (0 violations) / sliders x,y,z,w live
