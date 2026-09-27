SHADER: gen-stellar-web-loom
IDENTITY: warp-flight raymarch through a lattice of glowing node spheres joined by three axis families of fbm-warped threads, with HDR light trails and radial streaks.
KEEP VERBATIM: 80-step march (d*0.6), lattice cell/domain spacing, fbm warp (3 fbm calls, no more), mouse singularity + click deepen, starfield, radial warp streaks, HDR trail feedback (C read via exact textureLoad, .rgb only; decay rides Weave Speed), ACES, semantic alpha, 4 params (Thread Density / Weave Speed / Plasma Glow / Thread Opacity Exponent) with `updatedParams` byte-exact.
ADD:
  1. Plucked-string standing waves — each thread segment between two lattice nodes rings as a string pinned at both nodes: mode 1 sin(pi*|s|/spacing) plus a decaying mode 2 sin(2*pi*s/spacing), circularly polarised transverse displacement of warped_q, per-segment hashed pluck phase re-plucked every ~3 s (exp decay). Visible at audio = 0; bass only adds amplitude. Continuous across cell faces. (Ideas 1 = the loom is a stringed instrument, not a static net.)
  2. Warp/weft identity + real over/under — the three axis families get distinct hues (z violet kept, x amber, y teal) instead of one violet mat_id; thread radius swells/thins by cos(2*pi*s/spacing) times lattice-cell parity so each thread alternately passes over/under its crossing neighbours (continuous across cell faces, unlike a per-cell radius step). Under-passing segments are dimmed.
  3. Gyro ring per node — small tilted torus precessing around each node (per-cell hash tilt + spin); cheap (1 hash, 2 rotations, 1 torus SDF).
FORBID: beads / packets running along threads, springs, ripples, extraBuffer state.
A PACKING: existing documented packing kept: A.rgb = HDR (clamped to 6.0) trail colour, A.a = normalized march depth.

Silent bug fixed: audio burst envelope lived in extraBuffer[133]/[134], written by thread (0,0) and read by every thread. Slots 133..255 are zeroed on every upload (audioDepth.ts), so it never persisted and was a data race. Replaced with a stateless per-pixel burst = clamp((bass - 0.3) * 5, 0, 2) (same 0..2 range; fires on loud kicks rather than on rising edge); all extraBuffer writes and reads removed.
Tint note: thread colour now blends tempTint at 50% (mix(1, tempTint, 0.5)) so the three hues stay distinct; nodes keep the full tempTint.
