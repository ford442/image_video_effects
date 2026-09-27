# Idea Card — gen-resonant-quantum-obsidian-scarab-engine

```
SHADER: gen-resonant-quantum-obsidian-scarab-engine
IDENTITY (one sentence): a breathing cyan plasma torus core wrapped in a
  mirror-folded (KIFS) exoskeleton of black obsidian beads with hard white
  specular, violet quantum dust, and a faint feedback trail.
KEEP VERBATIM: map() (mouse-shifted sdTorus core, 4-fold KIFS with its
  in-place x/y "rotation" shear, smin 0.5, material ids 1/2); 100-step primary
  march; Lambert core + pow32 obsidian spec; held-mouse dust; 5% C feedback;
  fake-CA channel offset; ACES*1.2; lum alpha; depth = t/20; slider roles
  x=exoskeleton complexity (fold offset), y=plasma intensity,
  z=obsidian reflectivity, w=core pulse rate.
ADD (3 native ideas — each couples two subsystems already in the file):
  1. Elytra plate seams with a core-breath pulse — the KIFS shell is split into
     interlocking octant plates (great-circle seams in the final folded frame,
     per-plate obsidian tint); the seams are the "quantum circuitry" from the
     JSON description and light up with a wave that leaves the core at the same
     sin(time*rate) that breathes the torus, travelling outward through the
     plates. Fuses KIFS geometry + core pulse. (Plasma Intensity = brightness,
     Core Pulse Rate = wave speed.)
  2. Plasma mirror in the obsidian — reflect(rd,n) on exoskeleton hits is
     marched a short way against the core torus only; the cyan core appears as
     a Fresnel-weighted reflection in the black glass. Fuses core + obsidian;
     scaled by Obsidian Reflectivity x Plasma Intensity.
  3. Core corona leaking between plates — primary march integrates
     exp(-coreDist) * stepLength, so plasma light bleeds through the gaps of the
     exoskeleton and rims the torus silhouette on misses. Fuses the march +
     core field.
FORBID: spring cursor, click ripples (HEAD never used ripples), IQ palette,
  conchoidal fracture shells (gen-obsidian-echo-chamber), trailing membrane /
  buckle fractures (gen-resonant-quantum-obsidian-astro-manta), dragon iris or
  bismuth hopper ideas (batch siblings), a new creature or new fractal.
A PACKING: ACES display RGBA (HEAD, unchanged). C is read as colour history.
```

Audio: rides along only (bass already in pulse rate; mids in plasma).
All three ideas are visible with audio = 0.

Notes on HEAD bugs:
- KIFS "rotation" writes p.x then reads the new p.x for p.y (a shear, not a
  rotation). Kept verbatim: it IS the exoskeleton shape; fixing it would
  change the identity. The seam trap replicates it exactly so seams sit on
  the real surface.
- C feedback mixes ACES display back into HDR before ACES (5% weight). Stable
  (contracts), kept as HEAD's look; noted, not changed.
- No pow-negative-base, ripple.w, zero-C, or dead-mask issues found. New pow
  calls clamp bases with max(.,0).
- Dust is zero unless the mouse is held (zoom_config.w * 0.1) — HEAD behaviour,
  preserved.
