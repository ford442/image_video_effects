# Fireworks leftover atmospheric six — Idea Cards (written before WGSL)

Family: the six atmospheric / conductor / spread fireworks skipped by yesterday’s named-shell taxonomy ten. August already did bindings/ACES/exact-C/four named params — that is the floor, not this upgrade. Two native pyrotechnic ideas each. Identities kept. Existing pointer command shells kept; wind-ripple click-ripple barrages kept; audio-symphony extraBuffer[133] bass envelope kept. No new extraBuffer springs.

Claimed IDs: `gen-fireworks-fan-shell`, `gen-fireworks-comet-trail`, `gen-fireworks-smoke-bloom`, `gen-fireworks-wind-ripple`, `gen-fireworks-nocturne`, `gen-fireworks-audio-symphony`.

Skipped: named shells already shipped 2026-09-10; lighting catalog that already has named optical ideas; `matrix_digital_rain` (wrong kernel); `neon-pulse-edge` / `sim-volumetric-fake-em` (next lighting leftover); kaleido / hybrid / Batch 56–62 spring+ripple stamps.

---

SHADER: gen-fireworks-fan-shell
IDENTITY: wide hemisphere fan burst — peacock-tail sparks with strong horizontal bias after a rocket ascent
KEEP VERBATIM: fan-angle / shell-power / spark-density / hue-cycle; rocket then fan; mouse fan; Batch 37 drag / shellWind / flutter / starfield (already in the file — not this upgrade)
ADD (2 native ideas):
  1. Peacock eye spots — even fanT rays get a larger cooler node at mid-age (ocellus, not another core flash)
  2. Two-row palmette — even j is an outer long ray; odd j is an inner shorter ray (0.55 speed)
FORBID on this file: restating drag/wind/flutter as the upgrade; turning it into a spherical peony; springs
A PACKING: ACES display RGBA (HEAD stores color history in A; C is previous display)

---

SHADER: gen-fireworks-comet-trail
IDENTITY: blazing comet head with a long luminous tail, peel sparks, and a late burst
KEEP VERBATIM: comet-speed / trail-length / head-brightness / color-shift; 7 comets; peel loop; late radial burst; mouse comet
ADD (2 native ideas):
  1. Ion vs dust tail — ion is a straight anti-velocity streak; dust is the existing gravity-sag trail (two tails, not a longer hex chain)
  2. Coma halo — a wide dim sphere around the head, separate from the hex bokeh core
FORBID on this file: peony rewrite; springs; cloning fan palmette
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-smoke-bloom
IDENTITY: FBM smoke puffs around bursts plus neighbor-feedback bloom on the bright cores
KEEP VERBATIM: smokeDensity / bloomStrength / burstEnergy / trailDecay; smokePuff; mouse smoky peony
ADD (2 native ideas):
  1. Buoyancy — smoke center rises as sparks fall (puff y += burstAge * 0.12)
  2. Burst-lit smoke — puff brightness scaled by the local flash exp(-burstAge * 8)
FORBID on this file: Gray-Scott; cloning sim-smoke-trails vorticity; springs
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-wind-ripple
IDENTITY: wind-integrated sparks with UI ripple shock-front barrages
KEEP VERBATIM: windEnergy / rippleSensitivity / trailLength / colorDrift; sparkPosWind; existing click-ripple fronts; mouse shell. zoom_params.x drives both energy and wind amount (one slider — keep)
ADD (2 native ideas):
  1. Altitude shear — wind gain * (0.55 + 0.45 * saturate((uv.y + 0.8) * 0.7)) so higher sparks drift more
  2. Leeward streak — extra glow only on the downwind side of each spark (dot(uv-sp, windDir) > 0), not yesterday’s willow curtain lean
FORBID on this file: new springs; cloning willow leeward wholesale
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-nocturne
IDENTITY: mixed mortar field — staggered launches, bursts, crackle, lingering embers over a night sky
KEEP VERBATIM: energy / tempo / density / color-drift; 9 staggered mortars; mouse command shell
ADD (2 native ideas):
  1. Muzzle flash at launchPos during the first ~0.12s of ascent
  2. Two habits in the mix — even shells keep a round burst; odd shells droop (vy *= 0.55, extra gravity) without copying named-taxonomy files
FORBID on this file: springs; cloning chrysanthemum/willow wholesale; using config.y as dt
FLOOR (not an idea): u.config.y is rippleCount — stop using it as a timestep
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-audio-symphony
IDENTITY: fireworks conducted by the music — smoothed bass envelope triggers launches, mids layer, treble crackles
KEEP VERBATIM: launch-density / bass-drive / mids-layering / treble-sparkle; extraBuffer[133] smoothed bass (single-writer at (0,0)); mouse command
ADD (2 native ideas):
  1. Onset-only primary — bassPulse gates the big shell intensity, idle floor stays the small mortar
  2. Band-tinted stars — bass gold / mids rose / treble white on the starfield (not the shells)
FORBID on this file: writes to extraBuffer[0..132]; moving the envelope off [133]; springs
A PACKING: ACES display RGBA; extraBuffer[133] stays envelope
