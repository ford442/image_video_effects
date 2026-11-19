# NOTES — fork B

Scratch: /tmp/claude-0/-root-image-video-effects/1fa06ff7-ab76-48ee-a212-b70ea888abd0/scratchpad/forkB/ (renders, run1.txt, diff.py, perf.sh with absolute paths).
Note: running `audit:dead-sliders` / `audit:extrabuffer` / precommit gate rewrote `reports/*.json|md` — coordinator should restore/regenerate those, not take them from forks.

## gen-grok41-plasma (`gen_grok41_plasma.wgsl`)
- KEEP VERBATIM: yes (zonal jets, storm eye, polar hood, belt edges untouched except Rescue 4 inside storm-eye math). A packing unchanged (pattern, stormMask, limbT, validity).
- Rescues (all confirmed at HEAD):
  - R1 L157: camera orbit applied to `ro` only → globe off-centre at t=1.5 and **absent** at T0=10/25 (render). Now rd orbits too; planet centred and present at T0=10/25/45.
  - R2 L136: `plasmaBuffer[1..8]` per-bin reads (out of range) → bass/mids/treble.
  - R3 L185: click lightning × `ripple.w` (always 0) → dead; now unit strength (no ripple injection in harness — structural only).
  - R4 L266: `pow(theta-1.15,2)` / `pow(sin,2)` negative bases → x*x.
- Idea 5 moon-transit shadow (native) L284-295: umbra+penumbra disc in orbit-view space, 40 s transit, starts on-disc. Visibility: 1.91 % frame @192, 1.90 % @576 (≈5.5 % of the globe disc; local feature). Enlarged once from 1.03 %.
- Idea 6 Kelvin–Helmholtz belt billows (native) L277-281: longitude wave × l2 shear curls the belt-edge phase. 8.87 % @192, 8.85 % @576.
- Default look: HEAD idle 0.475/0.168 (globe off-centre) → new 0.453/0.179; held 0.481→0.457; audio 0.474→0.460. nan 0 everywhere, 60 f A16 run ok.
- frameMs (interleaved min, 192, very noisy box): ratios 0.67, 0.905, 1.863, 1.869 (median ≈1.38×, bimodal = load noise; added cost is ~30 ALU ops on a 1-sphere shader) — coordinator must re-time alone.
- Gates: precommit pass, naga-wasm pass, dead-sliders 0, extrabuffer 0 new.
- JSON: description +~45 chars; no tag changes.
- Open: KH billows read as a fairly regular zigzag at 192 — real-GPU look; uv y is screen-down (HEAD), left alone.

## gen-chromodynamic-plasma-collider
- KEEP VERBATIM: yes (5 earlier ideas). A packing unchanged (HDR pre-ACES + alpha).
- Rescue 1 L156: extraBuffer[133..138] mouse spring is re-uploaded zero every frame → it reset to rawMouse each frame (no-op) and raced a write from thread 0. Replaced with `mouse = rawMouse` (same picture, removes extraBuffer write).
- Idea 6 Airy-disc aperture diffraction (§12.2 Airy disc) L85-95 + L281-285: (2J1(x)/x)² sidelobes on the beam spot at each ring plane, per dispersed channel. 42.1 % @192, 42.0 % @576, mean|Δ| 0.026 (soft violet halo around the beam core + faint rings).
- Idea 7 synchrotron radiation fan (native) L199-212: warm stripe on the sleeve wall on the outer side of the local bend (tunnelSlope), ∝ curvature. 3.76 % @192, 3.79 % @576; Tunnel Warp=0 removes it (no bend) — consistent with slider role.
- Default look: idle meanL 0.261→0.286, stdL 0.055→0.082; held 0.260→0.286; audio 0.327→0.348; 60 f A16 0.460→0.476. nan 0.
- frameMs ratios (noisy): 0.89, 1.008, 1.814, 0.585 → median ≈0.95×. Coordinator should re-time alone.
- Gates: precommit pass, naga-wasm pass, dead-sliders 0, extrabuffer 0 new (one fewer write site).
- JSON: description +~45 chars ("synchrotron light fans onto the outer wall"); feature `sprung-magnetic-anomaly` is now false-ish (spring was always dead at HEAD too) — left as is, coordinator call.
