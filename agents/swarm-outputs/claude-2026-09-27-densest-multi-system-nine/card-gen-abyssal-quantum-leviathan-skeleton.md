```
SHADER: gen-abyssal-quantum-leviathan-skeleton
IDENTITY: a cyan-rimmed skeleton (one traveling-wave spine + repeated torus ribs) whipping along infinite z,
  darting forward on ballistic lunges through fast anisotropic streak currents.
KEEP VERBATIM: traveling-wave spine (tail-growing whip amp + incommensurate 2nd harmonic), ballistic lunge envelope,
  torus ribs + smin fuse, 80-step march, 24-step streak-current volume (stretch/flowSpeed/freq), horizontal
  camera-velocity trail feedback (decay 0.85, HDR clamp 6), mouse gravity well, 4 slider roles
  (Bone Density / Marrow Glow / Current Turbulence / Audio Reactivity), HDR-history A packing, rim + diffuse bone.
ADD (native ideas — each fuses two subsystems already in the file):
  1. Marrow canal — map() now returns the spine-local (displaced) frame in .yzw (was a constant material id);
     marrow glow (HEAD used world length(p.xy), a fixed cylinder the swaying spine leaves) is measured from the
     displaced spine core, so the violet canal rides the whip and pinches where the smin rib joints bulge out.
     Fuses: spine kinematics x marrow shading.
  2. Bending-strain bioluminescence — analytic 2nd z-derivative of the traveling wave (X'', Y'') gives the bend;
     bending strain = -dot(local offset, r'') lights the convex (tension) flank of ribs/spine in emerald and the
     compression flank stays dark, so the light runs down the body with the wave. Audio-independent.
     Fuses: spine kinematics x rib shading.
  3. Bow-wave current parting — the current volume samples map() per step; within ~2 units of the bone the noise
     sample is pushed outward along the spine-local radial, so streaks part around the silhouette, and the flank
     leading the lateral sway (analytic d/dt of the wave) is compressed/brightened (bow), the trailing flank thinned.
     No wake vortices. Fuses: spine kinematics x streak-current volume.
FIX (silent bugs): noise corner (1,0,1) hashed i+(1,0,0) -> z-cell seams in the currents; rib flare used world z
  while pulse lighting used body z (p.z+lungeOffset) -> flare now body z so the bulge and the light coincide;
  miss depth 0.05 -> 0.0 (far = 0 convention).
NOTE (left as HEAD, per contract): kick state in extraBuffer[133..135] is zeroed every frame (so kick ~ bass*2.5
  on thread 0's frame, 0 elsewhere) and other threads race thread (0,0)'s write. Not built on.
FORBID: vertebral phase-lag undulation, vortex wake (chronos leviathan), peristaltic segments (moth), springs, ripples,
  Beer-Lambert transmittance (dyson owns it), new creature/new system.
A PACKING: HDR history RGB (clamped <= 6) + semantic alpha (unchanged); C read back as the same HDR history, ACES on
  writeTexture only — no double tone-map.
```

STATUS: final
