# NOTES — pyramid family (coordinator)

- pyramid-bandprocess-pass2, pyramid-composite-pass3: not modified (clean on every gate; both read plasmaBuffer, ACES on final output, C via textureLoad).
- pyramid-downsample-pass1 (Upgraded 2026-11-22). Ideas 3+4 in WGSL (1+2 are the kept 2026-10-18 ideas):
  - Idea 3 Burt–Adelson 5-tap REDUCE kernel: halo 1→2, 20×20 tile filled by a 2-iteration stride loop, spatial weight reduceTap(dx)*reduceTap(dy) inside the existing luma range weight. B.a (range agreement) is now spatial-weighted.
  - Idea 4 beat-opened range sigma: rangeSigma *= 1 + 0.6*bass (plasmaBuffer[0].x). Measured on an edge-rich source through the full chain: bass-vs-silent mean|ΔRGB| 0.0074 (HEAD, pass 2/3 hue only) → 0.0146.
  - Hygiene: passthrough alpha = source alpha (HEAD hard-coded 1.0). JSON: added `audio-reactive` (now true).
- Kept verbatim: bilateral luma range weight, low-band settle (C), B = (blur RGB, range agreement), A unwritten, writeTexture photo passthrough, depth passthrough, all 4 params read.
- Look change at defaults: mean|ΔRGB| 0.013 on the smooth synthetic image (meanL 0.507→0.506); 0.062 on a speckle/grating source (wider kernel → more residual, expected).
- Cost: 25-tap bilateral vs 9 → timing OWED on a quiet box (readings taken under fork load were 247–955 ms for the same file and are discarded). If >1.3×, fall back to exp on the inner 3×3 only.
