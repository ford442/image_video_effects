# Ethereal generative ten — Idea Cards (written before WGSL)

Family: USER.md cohort from Cyber Chrono Nebula Phoenix through Feedback Echo Chamber. Two native ideas each (nautilus gets floor + ideas). Identities kept. Existing springs/ripples kept where HEAD already owns them; no new springs.

Claimed IDs: `gen-ethereal-cyber-chrono-nebula-phoenix`, `gen-ethereal-cyber-chrono-void-whale`, `gen-ethereal-cyber-plasma-void-dragon`, `gen-ethereal-glass-flora-terrarium`, `gen-ethereal-quantum-glass-nautilus`, `gen-ethereal-quantum-hologram-bonsai`, `gen-ethereal-quantum-holographic-fractal-coral`, `gen-ethereal-quantum-medusa`, `gen-ethereal-silk-veil`, `gen-feedback-echo-chamber`.

---

SHADER: gen-ethereal-cyber-chrono-nebula-phoenix
IDENTITY: Cybernetic phoenix SDF rising from domain-warped nebula with chrono attractor trap
KEEP VERBATIM: wingspan/plasma/chronoMix/spinRate; sdPhoenix; attractorTrap; spring halo [133..137]; ripple flares
ADD (2 native ideas):
  1. Wing feather filaments along SDF edge — phoenix plumage, not generic noise
  2. Tail ember convection streaks along tail SDF axis
FORBID: replacing phoenix with a different creature, IQ palette takeover
A PACKING: raw telemetry in A (trap, d, nebula, alpha) — C reads fields

---

SHADER: gen-ethereal-cyber-chrono-void-whale
IDENTITY: Raymarched skeletal whale in volumetric plasma ocean with temporal glitch streams
KEEP VERBATIM: plasmaDensity/temporalGlitch/refractionIndex/coreBloom; rib torus cage; core bloom; click fronts
ADD (2 native ideas):
  1. Baleen comb striations across open rib torus openings
  2. Bass sonar ping rings from core (automatic, distinct from click ripples)
FORBID: replacing whale with fish/kraken, spring overlay
A PACKING: ACES display RGBA in A

---

SHADER: gen-ethereal-cyber-plasma-void-dragon
IDENTITY: Segmented plasma dragon with crystalline ribs, halo crown, and nebula veins
KEEP VERBATIM: plasma/undulation/density/nebula params; capsule segments; octahedral shards; halo sigils
ADD (2 native ideas):
  1. Breath plasma jet cone along head-to-tail spine tangent
  2. Per-segment scale overlap parallax on body armor
FORBID: Gray-Scott, spring cursor, replacing dragon motif
A PACKING: ACES display RGBA in A

---

SHADER: gen-ethereal-glass-flora-terrarium
IDENTITY: Chromatic glass flora and pollen inside a terrarium raymarch
KEEP VERBATIM: floraDensity/nectarGlow/refractionIdx/timeWarp; chromatic raymarch; pollen mat
ADD (2 native ideas):
  1. Condensation droplet beads on terrarium glass shell
  2. Dew meniscus highlights on leaf-tip normals
FORBID: replacing flora with crystals-only scene, springs
A PACKING: ACES display RGBA in A

---

SHADER: gen-ethereal-quantum-glass-nautilus
IDENTITY: Log-spiral nautilus chambers raymarched with iridescent glass shell
KEEP VERBATIM: refractionIndex/spiralTightness/iridescenceShift/audioReactivity; log spiral map; voronoi micro-fractures
ADD (2 native ideas):
  1. Chamber septa walls between adjacent spiral chambers
  2. Pearl nacre luster on inner chamber ridges
FORBID: replacing nautilus with generic sphere, springs
A PACKING: ACES display RGBA in A (floor: dataA, depth, plasmaBuffer, exact C)

---

SHADER: gen-ethereal-quantum-hologram-bonsai
IDENTITY: Holographic jade bonsai with mouse lensing and bass-smoothed shimmer
KEEP VERBATIM: complexity/instability/glow/audioReact; branch SDF; bass_env [133]; mouse gravity lens
ADD (2 native ideas):
  1. Prune-cut seal rings at terminal branch tips
  2. North-facing moss lichen from bark normal vs up-light
FORBID: replacing tree with fractal cloud, new springs
A PACKING: ACES display RGBA in A

---

SHADER: gen-ethereal-quantum-holographic-fractal-coral
IDENTITY: Fractal coral branches with holographic palette and volumetric bioluminescence
KEEP VERBATIM: fractalDensity/holographicFreq/bioLum/audioPulse; recursive branch map; palette interference
ADD (2 native ideas):
  1. Polyp mouth pits along branch axis (tube SDF minus)
  2. Zooxanthellae symbiont pulse in branch interior from exact C
FORBID: replacing coral with generic crystals, springs
A PACKING: ACES display RGBA in A

---

SHADER: gen-ethereal-quantum-medusa
IDENTITY: Raymarched jellyfish bell and tentacles with chromatic separation and C glow memory
KEEP VERBATIM: swimmingSpeed/tentacleCurl/quantumGlow/repulsionStrength; tentacle field; pulse memory in C.a
ADD (2 native ideas):
  1. Nematocyst stinger dots along tentacle rim from edge SDF
  2. Bell contraction wave from radial phase tied to bass
FORBID: replacing medusa with particle cloud, new springs
A PACKING: ACES display RGBA in A

---

SHADER: gen-ethereal-silk-veil
IDENTITY: Multi-layer gold silk ribbons with mouse gather and fold sheen
KEEP VERBATIM: flowSpeed/waveIntensity/layerDensity/sheenAmount; ribbon layers; gather; click pluck
ADD (2 native ideas):
  1. Selvage fray noise along ribbon width edges
  2. Held-crease memory blended from exact C when mouse down
FORBID: replacing fabric with liquid solver, springs
A PACKING: ACES display RGBA in A

---

SHADER: gen-feedback-echo-chamber
IDENTITY: Multi-tap feedback echo chamber with gravity-well warp and psychedelic palette
KEEP VERBATIM: echoCount/decayRate/echoSpacing/colorShift; loadHistoryExact taps; bass_env [133]
ADD (2 native ideas):
  1. Harmonic echo ladder at integer 2× spacing taps (musical delay)
  2. Standing-wave nodal interference from echo-count phase field
FORBID: replacing with slit-scan, new springs
A PACKING: ACES display RGBA in A
