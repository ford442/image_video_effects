# Liquid and vortex batch idea cards

These cards were written before editing the batch WGSL.

## gen-chromatic-acid-drip
IDENTITY: pH-colored metaballs and chromatically lagged falling acid.
KEEP VERBATIM: metaball and drip fields, pH colors, slider roles, HDR color feedback.
ADD:
1. Gravity-fed rivulets extending below the existing drip menisci, to connect the blobs to the falling liquid.
2. Effervescence inside the metaballs, small rising bubbles caused by the acid reaction.
FORBID: unrelated cursor shockwaves or a replacement palette.
A PACKING: HDR display RGB and semantic alpha.

## gen-liquid-metal-cymatic-resonator
IDENTITY: a reflective, resonating liquid-metal heightfield.
KEEP VERBATIM: Fourier standing waves, raymarch, viscosity history and four slider roles.
ADD:
1. A weak counter-propagating radial mode beating against the existing radial waves.
2. Crest-aligned specular ridges that emphasize the resonator's wave peaks.
FORBID: a new scene or generic chromatic overlay.
A PACKING: ACES display RGBA.

## vortex-warp
IDENTITY: source imagery rotated by a Rankine vortex around the pointer.
KEEP VERBATIM: Rankine profile, FFT turbulence, angular dispersion, spring eye and slider roles.
ADD:
1. A weak radial inflow in the sheared outer vortex that draws source imagery toward the eye.
2. Depth-sensitive history retention that prevents temporal smearing equally across depth boundaries.
FORBID: replacing the warp with a generative vortex.
A PACKING: ACES display RGBA.

## gen-von-karman-vortex
IDENTITY: alternating point-vortex rows visualized as streamlines behind an obstacle.
KEEP VERBATIM: analytic velocity and streamfunction, obstacle, slider roles and color history.
ADD:
1. Traveling dye packets following existing streamline contours through the wake.
2. Twin shear-layer ribbons issuing from the obstacle into the alternating street.
FORBID: generic spiral or changes to vortex shedding.
A PACKING: display RGBA.

## gen-quantum-liquid-metal-chronosphere
IDENTITY: raymarched, capillary liquid-metal sphere with differential time bands.
KEEP VERBATIM: sphere SDF, modes, gravity-well interaction, echo history and slider roles.
ADD:
1. Cross-mode capillary interference on the existing metallic shell.
2. A grazing-angle liquid rim that outlines the sphere's moving silhouette.
FORBID: replacement geometry or new palette.
A PACKING: ACES display RGBA.

## interactive-magnetic-ripple
IDENTITY: pointer-centered magnetic ripples, Worley field lines and spring envelopes deforming the source.
KEEP VERBATIM: Worley/curl fields, ripple solver, saved slider roles, raw A state.
ADD:
1. Field-line convergence streaks, strengthened where the magnetic pull aligns with the field.
2. Wave-crest compression, increasing refraction on the existing ripple crests.
FORBID: treating state channels as previous-frame RGB or adding generic trails.
A PACKING: raw [bass envelope, mouse x, mouse y, ripple intensity].

## gen-quantum-liquid-gold-cymatic-vortex
IDENTITY: raymarched liquid-gold plane, cymatic vortex and central singularity.
KEEP VERBATIM: plane/sphere SDF, vortex, cymatic waves, gold material and slider roles.
ADD:
1. Secondary concentric mode interference in the existing cymatic displacement.
2. Flow-aligned glints on the gold crests, tied to the twisted vortex angle.
FORBID: replacing gold with an unrelated thin-film palette.
A PACKING: HDR linear RGB and alpha.

## liquid_magnetic_ferro
IDENTITY: dipole-driven ferrofluid spikes with a viscosity-smoothed magnetic field.
KEEP VERBATIM: dipole field, spike function, viscosity feedback, slider roles and raw A field.
ADD:
1. Spike-base meniscus rings to give the existing raised peaks a liquid boundary.
2. Directional magnetic striations following the smoothed field.
FORBID: display-color history in the simulation slot.
A PACKING: raw [field x, field y, field magnitude, 1].

## liquid-time-warp
IDENTITY: source video accumulated in curl-advected, interactive liquid time trails.
KEEP VERBATIM: midpoint curl advection, bounded anti-diffusion, wipe fronts, slider roles and B output.
ADD:
1. Flow-aligned two-tap history stretching for directionally smeared time layers.
2. Depth-sensitive history retention to separate near and distant temporal layers.
FORBID: replacing the feedback solver or adding an unrelated palette.
A PACKING: ACES display RGBA; B retains flow diagnostics.

## gen-volcanic-ink
IDENTITY: dark ink basin with hot fissures, molten folds, soot and embers.
KEEP VERBATIM: fBM fissures and lava, ink feedback, slider roles and B diagnostic channels.
ADD:
1. Ash settling on the existing cooling rind, carried by the soot field.
2. Hot fissure cores with cooler ink-lined shoulders, using the existing crack field.
FORBID: replacing the volcanic palette or using generic ripples.
A PACKING: HDR linear ink trail and semantic alpha; B retains lava/cracks/ember/smoke.
