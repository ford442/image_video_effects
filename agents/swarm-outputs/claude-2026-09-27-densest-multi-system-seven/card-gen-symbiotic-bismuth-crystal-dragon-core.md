# Idea Card — gen-symbiotic-bismuth-crystal-dragon-core

```
SHADER: gen-symbiotic-bismuth-crystal-dragon-core
IDENTITY (one sentence): a raymarched, breathing KIFS bismuth labyrinth (stepped-domain box folds,
  palette iridescence) fused by smooth-union to a liquid-gold sinew artery — the "symbiotic core" —
  with a mouse gravity well that drags the labyrinth toward the pointer.
KEEP VERBATIM: map() crystal branch (period-4 repetition, abs-fold + two time rotations per iteration,
  floor(bp*5)/5 stepped modulation, x1.5 scale, box SDF), sinew rotation r3 + sin^3 noise + radius 0.3,
  smin(k = 0.2*zoom) union and the crystal-0.1 material rule, sin(t*speed)*0.1+1 breathe, the mouse
  gravity well (mouse_pos, 2.0 radius, 0.5 pull), camera ro/rd, 100-step march + step AO + d^2 fog,
  palette(), crystal/gold shading formulas. Param roles: x Zoom, y Complexity (fold count),
  z Breathing Speed, w Iridescence Shift — all four saved `parameters` byte-exact.
ADD (3 native ideas):
  1. Ichor seep along the symbiotic seam — the smin blend weight h (where crystal and sinew
     distances meet) becomes a capillary stain: molten-gold ichor wicks outward from the seam into
     the bismuth with fingering, plus an emissive capillary line on the seam itself. The file's
     whole premise is the crystal/sinew symbiosis; this makes the union visible instead of a blend.
  2. Peristaltic heart-bolus — lub-dub double pulses travel down the sinew artery toward the viewer,
     bulging its radius and heating its emission; the artery mouth flares when a bolus arrives.
     Paced by Breathing Speed (heart rate). The description promises a core that "pulses like a
     heart"; HEAD only had a uniform global scale sine.
  3. Furnace underlight through the labyrinth — the artery is a heat source: crystal facets whose
     normals face the artery axis pick up warm core light that swells with each bolus, and the march
     accumulates a thin volumetric heat haze from sinew proximity so the core glows through gaps.
FORBID on this file: hopper terraces, oxide thin-film, twin-boundary seams, terrace-lip glints,
  flux lines (shipped bismuth siblings); iris/pupil/cornea (plasma-dragon-eye owns those);
  springs, click ripples, IQ-palette stamps, extraBuffer state.
A PACKING: ACES display RGBA (alpha = surface coverage x fog transmission + core haze). No C read —
  stateless; A mirrors the display frame for downstream history consumers.
```

## Silent bugs fixed (read path)
- **Camera inside the sinew (whole frame was a flat gold wash).** The sinew was an infinite z-cylinder
  of radius 0.3 around the view axis; the camera at (0,0,-4) sits inside it, so map(ro) < 0 and every
  ray "hit" at step 0 (numpy port: 100% of pixels hit at i=0, 100% sinew). The labyrinth was never
  visible. Fix: the artery is capped in world space at z = -2.5 (mouth in front of the camera, zoom-
  independent) and bores a lumen (radius 0.6 in folded space) through the crystal so it is seen
  running down a crystal-walled channel. Port after fix: ~1–11% sinew core at centre, labyrinth
  walls elsewhere, hits at median 1.5–1.7 units.
- **Audio read from `extraBuffer[0]`** (not audio). Now `plasmaBuffer[0].x` bass (breathe phase,
  bolus amplitude, flash).
- Floor: header, ACES, semantic alpha, depth write, A write were missing.
