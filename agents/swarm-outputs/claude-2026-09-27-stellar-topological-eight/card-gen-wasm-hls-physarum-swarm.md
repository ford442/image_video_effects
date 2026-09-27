# Idea Card: gen-wasm-hls-physarum-swarm (RESCUE, then 2 ideas)

```
SHADER: gen-wasm-hls-physarum-swarm
IDENTITY: slime-mould vein network that eats the video (luma = food), mouse attracts, audio steers.
WHY IT IS DEAD (HEAD): agent (x,y,angle,alive) lives in extraBuffer[agentIdx*4..]. The runtime re-uploads all 256 floats
  every frame (0-2 audio, 4 historyHead, 5..132 FFT, rest zero) => every agent reads alive==0 and re-seeds to the same
  hash position each frame (static noise), and the shader clobbers the audio/FFT slots (race).
KEEP VERBATIM: 3-sensor F/L/R steering with weight (trail + food*2.5); sensorAngle / sensorDist / decayRate / depositAmount
  roles and mix() ranges (0.3..1.2, 5..25, 0.85..0.995, 0.3..2.0); turnSpeed = 0.5 + bass*3 + mid*1.5 (times sensorAngle),
  moveSpeed = 1.5 + treble; deposit *(1+bass*2); random tie-break when F is the minimum; mouse pull radius 150 px, blend*0.3;
  3x3-blurred, decayed trail; video-as-food; chromatic palette (paletteChromatic); depth pass-through.
RESCUE (state rule changes): Eulerian agents, no extraBuffer at all (not even 133..138).
  A = (trail, mx, my, hue): m = mass density * heading (|m| = mass, m/|m| = heading).
  Per pixel, exact textureLoad on C only:
   1. u = speed * m/max(|m|,0.05); source s = p - u.
   2. gather at s from the 4 bilinear corners: mass = bilinear(|m|); heading = corner with largest weight*|m|
      (winner-take-all).  Plain vector bilerp of m was tried FIRST and failed the gate (opposing streams cancel -> isolated
      hubs, giant component 0.17); this is the "do not annihilate" mechanism.
   3. Jacobian J = det(I - grad u) from central differences of u (4 more loads): converging flow piles mass up
      (this is what concentrates agents onto veins, as in real physarum); mass = clamp(max(mass,0.07)*(1+0.6(J-1)), 0.07, 0.6).
   4. steer (F/L/R sense on trail C + food*2.5), +-0.075 rad wander, mouse pull; then trail = blur3x3(C.r)*decay
      + 0.05*dep*mass*(1-trail)*(1-decay)/0.04125  (deposit normalised so Trail Decay changes persistence, not brightness).
  Seed path: C texel all-zero (first frame / resize) -> mass 0.075..0.225, heading from hash.
  Mass floor 0.07 = re-inflation; cap 0.6.
NUMPY GATE (physarum_sim.py, N=128, 1500 steps): see report; all 9 slider cases pass (vein mesh, giant comp >= 0.66, mass
  >100% of initial, no saturation, state moving).
ADD (after the sim lives):
  1. Peristaltic cytoplasm streaming: brightness pulses that run along the veins in the local heading direction:
     phase = dot(pos, heading)*k - time*w, modulating trail brightness (gated by heading coherence so it only shows on real veins).
     Native: an actual vein carries cytoplasm along its axis, and heading is a field the rescue now owns.
  2. Tube shading of veins: normal from the trail gradient (C central differences), diffuse + specular, so veins read as
     cylinders; plus a distinct foraging-front colour where mass is high but trail is young
     (youth = (1.21*dep*mass - trail)/(0.3*1.21*dep*mass+0.02), the equilibrium trail for that mass; 7-17% coverage in numpy).
FORBID: boids / reaction-diffusion reimagining, springs, ripples, extraBuffer state, ripple-style overlays, IQ palette stamp.
A PACKING: raw sim state (trail, mx, my, hue). ACES only on writeTexture. No ACES on stored fields.
SLIDERS: names/defaults/min/max/step byte-exact. Roles kept. LOOK AT SAVED VALUES DIFFERS: HEAD was static per-frame noise
  (dead); saved values now give a slowly migrating vein mesh.
SILENT BUGS FIXED: extraBuffer clobber of audio/FFT slots + always-reseeding agents; alpha hardcoded 1.0 and A alpha 1.0
  (now vein coverage); mouse pull blended raw angles across the +-pi seam (now shortest arc) and normalize(0) at the cursor
  pixel (guarded); prior "temporal persistence" mix with C.rgb (no longer feeds anything back through display).
```
