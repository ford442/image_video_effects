SHADER: gen-prismatic-crystal-growth
IDENTITY: Raymarched SDF lattice of octahedral/dodecahedral glass crystals that grow over time; Fresnel translucency, thickness-alpha, caustics, mouse-steered light, click seeds.
KEEP VERBATIM: crystalLattice/map/calcNormal (spacing now a parameter), fresnelSchlick, crystalCaustics, bass_env, hueToRGB, raymarch step-LOD, ripple seed loop, thickness alpha.
ADD (2 native ideas):
  1. Cauchy-dispersion facet fire: per-channel refraction with n(lambda)=1.5+B/lambda^2 (lambda 0.65/0.55/0.45 um), in+out facet refraction, sharp light lobe per channel -> spectral fire on facet edges; B scales with Prism Intensity, treble sparkle, held boost.
  2. Oscillatory growth-zone banding: look 0.12 into the facet along the refracted ray, recover crystal local frame, draw octahedral growth shells (2 + growth*8 zones) with alternating impurity tints; mids gain.
FLOOR FIXES: removed plasmaBuffer[0].w (rms) read, audio clamped 0..1; extraBuffer[2] smoothed-bass removed and growth made stateless (coordinator: agent first moved bass envelope + growth to extraBuffer[133/134], but writeExtraBuffer uploads all 256 floats per frame so 133..138 never persist; growth is monotonic in time anyway; per-pixel A.g growth state dropped); A now holds the same ACES display RGBA as writeTexture (was thickness/growth/0/alpha, which C then misread as colour); temporal blend moved to display space after ACES; C load coords clamped; Crystal Density (zoom_params.y) was DEAD -> now lattice spacing 2.5*1.25^(1-2y) (default 0.5 == old 2.5); mouse-held added (supersaturation: growth jumps ahead while held, fire brightens); ripples kept; header replaced; JSON features + params array added.
FORBID: dataTextureB writes, extraBuffer outside 133..138, plasmaBuffer beyond [0].xyz, changing updatedParams.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live
