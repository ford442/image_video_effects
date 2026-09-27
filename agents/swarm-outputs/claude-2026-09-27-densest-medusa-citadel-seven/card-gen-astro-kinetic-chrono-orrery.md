```
SHADER: gen-astro-kinetic-chrono-orrery
IDENTITY: a raymarched central singularity with an accretion disk and 3–10 small Kepler-orbit bodies, near-miss glow,
  stars and short trails.
KEEP VERBATIM: Kepler solver + per-pixel body cache (Batch-35 hoist), bounding-sphere cull (now radius-adaptive),
  map() SDF (disk thickness/slab/body spheres unchanged; only an argmin id is recorded), disk density, blackbodyColor(),
  glow integral, stars, fog, mouse rotation, 4 slider roles (x Complexity -> body count, y Speed, z Glow, w Audio),
  saved params, FFT bin reads, trail mix, A = pre-tone-map HDR trail, depth formula.
ADD (native ideas):
  1. Singularity-lit crescent phases + true blackbody hue — bodies get analytic sphere normals lit only by the core
     (lambert from body->core, soft terminator, metalness-driven Blinn spec, faint night-side self-glow), so each shows
     a phase that turns as it orbits; albedo is the body's blackbodyColor(temp). Replaces HEAD's false colour
     (R = temp/9000, G = metal, B = luma) for core, disk and bodies alike. WGSL L315-338.
  2. Disk-crossing flares + tidal gaps — bodies orbit in q.xy, the disk lies in q.xz, so every orbit pierces the disk.
     (a) flare = exp(-(body.y/0.16)^2) over the disk annulus, stateless from the Kepler phase (precompute L249-258):
     the body goes white-hot (L336-338) and heats a pool on the disk around its piercing point (L307-314).
     numpy: 6 bodies at default -> ~27 flare events / 120 s, a flare on ~23% of frames.
     (b) tidal gaps: each body clears a gaussian lane (depth 0.78, width 0.05+radius) at its semi-major axis
     (tidalGap L156-167, applied in disk shading L302-306) -> Cassini-like dark, lower-alpha lanes. Shading-only so
     the SDF stays Lipschitz-identical to HEAD.
  3. (refused) Eclipsing moons: bodies are r 0.04-0.07 (~4-8 px at 1080p); a split moon would be ~2 px, its shadow
     sub-pixel, and it doubles the sphere loop in the per-step map(). Not visible enough to earn the cost.
FIX/WIRE (done):
  - No ACES -> acesToneMap on writeTexture only; A/C stay pre-tone-map HDR (no double tone-map).
  - Cull sphere: claim TRUE but only for Complexity >= 6 (body 8 apoapsis reach 5.157 vs 4.4; bodies 1-7 max 4.108,
    numpy). Now boundR = max(4.4, live body reach + 0.35) per frame; default (6 bodies) stays ~4.4-4.46.
    Body 8 reach 5.157 > camera distance 5 -> added NEAR_CLIP 0.15 (> 2x max body radius) so a fly-through body
    can never swallow the frame (map(camera) < 0 case). Core 0.25 and disk <= 3.01 never reach the camera.
  - blackbodyColor pow(t-6.6, -0.133) at t = 6.6 was pow(0, neg) = inf -> base clamped to 1e-3.
  - Header: Ideas + A packing + Upgraded 2026-09-27; false "mouse-gravity" / "audio-orbit" replaced by
    mouse-orbit / audio-reactive (mouse only rotates the view — kept as is).
  - JSON features: + upgraded-rgba, + mouse-driven (mouse rotation changes the picture); audio-reactive already true.
    params byte-exact (diff is the features array only).
FORBID: Keplerian rete/astrolabe gearing, Doppler beaming crescent, photon ring, Keplerian shear streaks, dust-lane
  absorption, gravitational redshift, lensed far-side halo, brass clockwork.
A PACKING: HDR linear RGB (pre-ACES trail) + semantic alpha (disk alpha = gapped density), C = exact HDR trail.
DEFAULT-LOOK SHIFT (GPU QA): disk goes from greenish-grey false colour to orange->white blackbody with ~5 dark gap
  lanes (disk is face-on at the idle mouse 0.5/0.5); bodies go from flat discs to core-lit phases (dark transit
  silhouettes when in front of the core); periodic white-hot flares where bodies pierce the disk; ACES softens clip.
  NOT verified on GPU.
```

STATUS: final
