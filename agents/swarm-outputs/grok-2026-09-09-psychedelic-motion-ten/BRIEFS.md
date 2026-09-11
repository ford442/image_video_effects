# Fast-motion + psychedelic ten — Idea Cards (written before WGSL)

Family: leftover kaleidoscope / tunnel / spin / wormhole IDs that still lack Idea Cards. Native motion/fold/portal ideas only. No spring+ripple+IQ stamp. No clone of Poincaré crease onto the breath kaleido, or log-z onto the wormhole.

Skipped as already overlay-rich: `kaleidoscope` (Batch 60), `kaleido-scope-grokcf1` (Batch 55), `fractal-kaleidoscope` (56/57), `kaleido-portal-interactive` (17), `polar-warp-interactive` (54), `infinite-spiral-zoom` (30), `warp_drive` (56), `vortex-warp` (60 Rankine), `liquid-zoom` (58B), Fast-Motion Ten IDs.

---

SHADER: mouse-kaleidoscope-tunnel
IDENTITY: mouse-centered kaleidoscope tunnel; polar depth layers; click bursts
KEEP VERBATIM: tunnelSpeed / segmentBase / spiralTwist / zoomDepth; `kaleidoscope()` fold; click ripple bursts; 3-layer parallax
ADD:
  1. Log-z rings — recede with `-log(r)` so depth is a tunnel, not a linear `fract`
  2. Wavelength split along the existing spiral (R/B sample the same polar path)
FORBID: extraBuffer springs, IQ palettes, cloning Poincaré kaleido-scope
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: mouse-wormhole-lens
IDENTITY: mouse portal that inverts, spirals, and hue-shifts inside; drag stretches oval
KEEP VERBATIM: portalRadius / spiral / hue / lens; invert; event-horizon glow; click baby portals
ADD:
  1. Inverse-square lensing on the existing edge offset (gravity on this portal)
  2. Exact-C throat ghost (echo through the hole, not a new sim)
FORBID: springs stamp; kaleidoscope fold
A PACKING: ACES display RGBA. Mouse stash moves to extraBuffer[133..134] so A is not a one-pixel telemetry lie.

---

SHADER: kaleido-scope
IDENTITY: Poincaré-disk hyperbolic tessellation of the photo
KEEP VERBATIM: `poincareMap`; morph 4–7 / 6–11; ringOffset; Brown `lensDistort`; existing CA
ADD:
  1. Geodesic crease along Poincaré `hypR` iso-lines
  2. Opposite-wedge sample (true dihedral pair, not extra CA)
FORBID: cloning kaleidoscope.wgsl rose FBM; cloning grokcf1 Batch 55; new springs
A PACKING: ACES display RGBA (HEAD packed unused telemetry)

---

SHADER: breathing-kaleidoscope
IDENTITY: kaleido whose segment count breathes via FBM warp
KEEP VERBATIM: cycleSpeed / segments / rotation / maxRotation; FBM warp; jewel mix; film grain
ADD:
  1. Inhale vs exhale — petal scale expands on `sin>0`, contracts on `sin<0`
  2. Held-breath freeze — `mouseDown` holds breath at rest (pointer already exists; not a spring)
FORBID: extraBuffer spring; cloning Poincaré
A PACKING: ACES display RGBA (HEAD packed unused telemetry)

---

SHADER: hypnotic-spiral
IDENTITY: Archimedean SDF spiral arms mixed over the photo
KEEP VERBATIM: arms / rotSpeed / colorCycle / warp; counter-rotating second spiral; click reverse
ADD:
  1. Log vs Archimedean mix (`r` vs `log(r)`) so the coil can tighten
  2. Sample the photo along the spiral tangent (the photo rides the arm; kill the UV blob)
FORBID: kaleidoscope fold; new springs
A PACKING: ACES display RGBA

---

SHADER: concentric-spin
IDENTITY: concentric rings rotating in alternating directions; mouse is the center
KEEP VERBATIM: density / speed / smoothW / gapFade; rose/epi morph via mids; lag center
ADD:
  1. Exact-C lag — `textureLoad` of C (HEAD used a filtering sample)
  2. Gap conveyor — in the ring gap, slide the photo along the ring tangent
FORBID: kaleidoscope; new springs
A PACKING: lag.xy telemetry (C is read as lag)

---

SHADER: quantum-tunnel-interactive
IDENTITY: mouse-centered photo tunnel with chromatic scale split and pulse rings
KEEP VERBATIM: tunnel / aberration / pulse / twist; existing [133..138] spring; click mouths; sector FFT voices
ADD:
  1. Log-z pulse so the existing `sin(dist*20)` rings recede
  2. Wavelength-scaled twist (R/B extra angle on the same `twistAngle`)
FORBID: new springs; kaleidoscope stamp
A PACKING: ACES display RGBA

---

SHADER: gen-hypnotic-vortex-tunnel
IDENTITY: generative nested vortex rings; mouse is the vanishing point
KEEP VERBATIM: nRings / rotSpeed / zoom / distort; `tunnelLayer` ring×spoke; iris
ADD:
  1. Log-depth seam walls (`fract(z)`)
  2. Even/odd layers contra-rotate
FORBID: springs; photo-kaleido clone
A PACKING: ACES display RGBA (single ACES; HEAD double-mapped)

---

SHADER: gen-psychedelic-time-warp-kaleidoscope
IDENTITY: kaleido fold + curl-noise wobble + temporal C mix
KEEP VERBATIM: fold / wobble / curl; `applyGenerativePrimaryControls` param roles (intensity / speed / scale / mouse)
ADD:
  1. Exact-C smear along the fold (HEAD filtered C as color while writing noise to A)
  2. Honest three-band: bass=mirror count, mids=wobble, treble=curl. Kill `plasmaBuffer[index]` as audio
FORBID: new springs; treating applyGenerativePrimaryControls as the upgrade
A PACKING: ACES display RGBA

---

SHADER: gen-psychedelic-moire-flower
IDENTITY: multi-frequency polar moiré flower
KEEP VERBATIM: 5-lobe `moireFlower`; interference; `neonColor`; CA taps
ADD:
  1. 8/13 phyllotaxis on the existing petal sines
  2. Density detune between p1 and p2 (beat, not a new flower)
FORBID: cloning islamic tiling; springs
A PACKING: ACES display RGBA (already). Floor: wire unused Speed into `t`; treat `zoom_config.yz` as UV.
