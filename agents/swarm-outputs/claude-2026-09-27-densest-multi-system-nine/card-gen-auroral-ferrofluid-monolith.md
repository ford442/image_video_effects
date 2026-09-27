```
SHADER: gen-auroral-ferrofluid-monolith
IDENTITY: from a static camera, a twisting dark-chrome pillar with noise spikes wrapped in green/magenta fbm aurora.
KEEP VERBATIM: camera (ro z=8, focal 1.2), twisted box + mouse pole + spike map() SDF and 0.5-relaxed march, calcNormal,
  hash33/noise/fbm (uncentred gradients kept — see below), two-light + Blinn + Schlick chrome shading, aurora c1/c2
  height gradient + den>0.01 gate + den*step*2 integration, background glow, bass/treble glyph grading, 4 slider roles
  (Spike Length / Aurora Intensity / Magnetic Twist / Fluid Metallic Response), saved params byte-exact.
FIX (silent bugs, several change the default look — list them for GPU QA):
  - AURORA WAS DEAD (numpy-verified): HEAD fbm is ±0.15 (p99), so f1*f2 never exceeds ~0.03 and
    smoothstep(0.4,0.8,f1*f2) is identically 0 -> Aurora Intensity slider was dead, no aurora ever rendered.
    Fix: remap each fbm to 0.5 + 4*fbm (clamped 0..1) so the HEAD 0.4..0.8 threshold fires on ~18% of the volume.
  - Aurora march clipped wrong: started at t=0, 60 x 0.1 -> reached only t=6. Numpy: aurora bounding box (half-ext
    3.5/6.5/3.5) entry t=4.50..5.89, exit t=5.90..12.91, pillar hit t=6.12..9.05 (median 6.96). New march: 56 steps
    over [box entry, min(box exit, hit)] — covers the inner sheath and the aurora behind the pillar on miss rays.
  - L220 read audio from u.config.y (click count): clicks added purple to up-facing normals up to 50x. Removed;
    replaced by idea 3 (tip corona), audio from plasmaBuffer[0].z.
  - pow(1-abs(noise), 8.0): base clamped with max(…,0). Numpy: uncentred |noise| <= 0.43, so it never actually
    went NaN; centring the gradients (coordinator draft) would roughly double |n| and thin/shorten every spike, so
    it is REFUSED to preserve identity — clamp only.
  - zoom_config.w*8 in mouseAngle made the orbiting pole jump 8 rad on press/release -> removed (held still boosts
    poleDistort, as HEAD).
  - spikeLength could go negative under treble (spikes invert into pits) -> max(…, 0).
  - depth was constant 0 -> real hit depth (near=1, miss=0).
FLOOR: ACES replaces Reinhard (display gamma kept after it so the dark chrome is not crushed); dataTextureA = ACES
  display RGBA; semantic alpha = max(pillar coverage, aurora opacity, background glow); output no longer premultiplied.
ADD (native ideas):
  1. Aurora sheath — aurora density is boosted by proximity to the monolith SDF (map(p).x): x2 at the spike surface,
     ~x0.5 one unit out, so the curtain hugs the spikes and pillar instead of filling a box.
  2. Co-wound field aurora — mapAurora first enters the monolith's own field frame (same Magnetic Twist winding +
     0.2 rad/s spin as map()), is pinched toward the orbiting mouse pole (rotatedPole, same as the spikes see) and
     brightened there, then applies HEAD's rotation verbatim. Aurora winding now follows the Magnetic Twist slider
     and the mouse pole drags curtain and spikes together.
  3. Spike-tip corona — map() returns the spike crest factor in .y; crests (tip 0.9..0.99) emit an aurora-tinted
     corona (same c1/c2 height gradient as the volume), stronger at grazing angles, scaled by Aurora Intensity;
     treble rides along.
FORBID: Rosensweig lattice, Taylor cone pinch-off, dipole chains, chrome reflects core beam, 557.7/630 nm bands,
  curtain folds, Birkeland tubes (the draft's "field filaments" were dropped for this reason: field-aligned
  filaments ARE Birkeland tubes — idea 2 is the frame coupling + pole pinch only), springs, ripples.
A PACKING: ACES display RGBA (new; C is not read).
```

STATUS: final
