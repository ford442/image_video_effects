# Shader Upgrade Briefs — neon/neuro ten (2026-10-10)

## SHADER: `gen-neon-plasma-biomechanical-hive`
IDENTITY: A fast flythrough of a biomechanical hive with neon veins, brood cells, and plasma spores.
KEEP VERBATIM: raymarched hive geometry, brood-cell motif, peristaltic bolus tubes, spore swarm, slider roles.
ADD:
1. Chitin valve irises — capped brood cells get annular shutters that rotate/open with pressure.
2. Trophallactic plasma bridges — neighboring open cells exchange pulsing neon hemolymph.
FORBID: replacing the hive with unrelated geometric motifs.
A PACKING: ACES display RGBA in A; feedback lifted with `acesInverse`.

## SHADER: `gen-neon-plasma-chrono-bloom`
IDENTITY: A volumetric neon plasma bloom with radial time lag and filament intersections.
KEEP VERBATIM: raymarch structure, radial lag behavior, dual-sheet filament ignition, slider semantics.
ADD:
1. Phase-slip caustic petals — delayed shell fronts fold into hot caustic seams.
2. Rotating sepal ribs — azimuthal rib bands ride shell fronts and brighten with heat.
FORBID: replacing the bloom with non-plasma scene geometry.
A PACKING: ACES display RGBA in A.

## SHADER: `gen-neural-bioluminescence-matrix`
IDENTITY: A glowing neural matrix with saltatory spikes and bioluminescent energy transfer.
KEEP VERBATIM: Ranvier hopping, aequorin->GFP transfer, click calcium waves, temporal feedback.
ADD:
1. Astrocytic calcium tide — slower turquoise glial support glow around active tracts.
2. Vesicle bouton scintillation — amber synaptic puncta around active spikes.
FORBID: changing it into a generic volumetric cloud.
A PACKING: ACES display RGBA in A.

## SHADER: `gen-neural-fractal`
IDENTITY: Neural-activation fractal orbit rendering with dendritic growth and firing glow.
KEEP VERBATIM: neural activation iterations, dendritic growth cone logic, firing-rate color pulses.
ADD:
1. Inhibitory surround ring — over-fired loci suppress nearby branch brightness.
2. Hebbian feedback memory — active corridors persist through exact C feedback.
FORBID: replacing with unrelated fractal families.
A PACKING: ACES display RGBA in A.

## SHADER: `gen-neural-network-glow-synaptic-pulse`
IDENTITY: Synaptic pulse mesh with quantal release clouds, refractory spikes, and trails.
KEEP VERBATIM: quantal transmitter diffusion, action-potential waveform, click evoked rings, temporal potentiation.
ADD:
1. Conduction-delay ladders — per-cell latency offsets in pulse phase.
2. Astrocytic uptake halo — cyan uptake sheaths around transmitter-rich nodes.
FORBID: changing to non-neural glitch overlays.
A PACKING: ACES display RGBA in A.

## SHADER: `gen-neuro-cosmos`
IDENTITY: Cosmic-neural Voronoi web with saltatory strands and integrate-and-fire soma.
KEEP VERBATIM: voronoi web/cell blend, IAF soma logic, evoked depolarization fronts.
ADD:
1. Activity pruning shadows — weak web strands dim/fragment.
2. Hebbian reinforcement — recurrent activity re-brightens paths via feedback.
FORBID: replacing the network with a different spatial metaphor.
A PACKING: ACES display RGBA in A.

## SHADER: `gen-neuro-fluid-plasma-lotus`
IDENTITY: Raymarched lotus with liquid-neon petals, phyllotaxis core, and flux-rope field glow.
KEEP VERBATIM: lotus/body SDF blend, phyllotaxis florets, flux-rope emission, volumetric plasma.
ADD:
1. Capillary petal venation — branching luminous sap channels on petals.
2. Reconnection plumes — click-shock-driven magnetic plume bursts.
FORBID: replacing lotus structure with unrelated particles.
A PACKING: ACES display RGBA in A.

## SHADER: `gen-neuro-kinetic-bloom`
IDENTITY: Branching biomechanical flora with vein glow and saltatory spikes.
KEEP VERBATIM: trunk + side branches + spine forks, saltatory pulse front, mouse repulsion framing.
ADD:
1. Myelin pearling instability — beaded swelling/relaxation along trunk radius.
2. Synaptic bouton crowns — bulbous terminal boutons at branch tips.
FORBID: turning it into a smooth unbranched tunnel.
A PACKING: ACES display RGBA in A.

## SHADER: `gen-neuro-kinetic-liquid-gold-lotus`
IDENTITY: Liquid-gold lotus with conductive Fresnel response and plasma runners.
KEEP VERBATIM: conductor Fresnel core, phyllotaxis anther firing, torque-advected feedback.
ADD:
1. Capillary rivulets — bright gold channels running down petals.
2. Kelvin-Helmholtz shear rolls — torque-driven shear packets in plasma runners.
FORBID: replacing with matte diffuse floral shading.
A PACKING: ACES display RGBA in A.

## SHADER: `gen-neutron-star-magnetic-spindle`
IDENTITY: Neutron-star spindle with dipole magnetosphere, beams, disk, jets, and lensing.
KEEP VERBATIM: dipole-line emission, lighthouse beams, accretion/jet volume march, click starquake ring.
ADD:
1. Polar-cap spark carousel — drifting subpulse knots near magnetic poles.
2. Striped current sheet — equatorial striped wind beyond light cylinder.
FORBID: replacing with non-astrophysical abstract geometry.
A PACKING: ACES display RGBA in A.
