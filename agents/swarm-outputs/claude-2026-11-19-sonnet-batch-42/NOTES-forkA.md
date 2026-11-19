# NOTES fork A (BRIEFS-forkA.md not written separately — cards folded in here; ideas were decided after HEAD renders, before WGSL edits)

## gen-luminescent-quantum-flora-symphony (2nd pass; params: [] → defaults from x-meta 1,0.5,0.8,1.5)
- HEAD render: petal KIFS blob fills frame, core/stem hidden at default camera; not dead/white → no rescue. meanL 0.376 / stdL 0.307 idle.
- KEEP VERBATIM: ideas 1–3 untouched; Upgraded/Ideas lines appended. A packing unchanged.
- Idea 4 Fresnel–Schlick dew-wet petal cuticle (§12.2 Fresnel–Schlick; F0 0.04, reflected sky gradient + hex dew beads, treble sparkle): 55.7 % px / mean|Δ| 0.050 at 192 and 576.
- Idea 5 luminescent petal-margin aura (native; closest-approach of missing rays → petal-coloured halo, mids pulse): 31.7 % / 0.053 (192 & 576).
- First strength was too white (meanL 0.484); trimmed. New meanL idle 0.469→ after trim ~0.47 (HEAD 0.376), held 0.438 (HEAD 0.366), audio 0.500 (HEAD 0.388). Brighter default — open item for real-GPU look.
- frameMs ratio (interleaved 4 rounds, load-noisy w/ other forks): 0.90/1.01/1.37/1.63 → median ≈1.19.
- Gates: precommit ✅, naga-wasm ✅, dead-sliders PASS (blind spot: 0 defs since params: []), extrabuffer no finding. nan 0.
- Open: HEAD extraBuffer[5+(x+y)%32] "FFT" read is a per-pixel bin pick (diagonal stripes), left alone.

## gen-biomechanical-neural-mycelium (2nd pass; defaults 0.5,0.5,0.5,0)
- HEAD fine (meanL 0.122 idle). Step-count AO already present at HEAD (row budget item was redundant) → two native ideas instead.
- Idea 4 anastomosis bridges (native; pair-hashed diagonal capsules joining node c to c+(1,1,0), continuous across cells), mapScene: 14.7 % / 0.030 at 192.
- Idea 5 septal cross-walls (native; Scene.along carries nearest-strand coordinate, dark septum + bright rim lit by packets on hit shading): 10.6 % / 0.016 at 192.
- meanL idle 0.122→0.134, held 0.123→0.135, audio 0.133→0.143. nan 0.
- frameMs ratio (128px, 4 rounds): 1.37/1.13/1.13/0.99 → median ≈1.13.
- Gates: precommit ✅, naga-wasm ✅, dead-sliders PASS, extrabuffer no finding. JSON untouched.
- Not done: 576 visibility for mycelium (too slow under load), 60-frame run (no temporal state in either file).

## mycelium trim (coordinator re-time 1.32×)
- Hoist: nearest strand chosen first, `packet()` evaluated once per map() (was up to 3×). Bridge gate hashes: two hash31 → cheap sin-dot hash.
- Bug found while trimming: the camera rides the (+,+) cell-corner line, so a (1,1,0) bridge can run through the lens (a giant capsule filled a corner of the frame once the hash changed). Bridges now on the anti-diagonal (1,−1,0) → never on the camera line.
- After: Idea 4 bridges 10.8 % / 0.027, Idea 5 septa 9.9 % / 0.015 (192). meanL idle 0.133 (HEAD 0.122), t=8 0.151. nan 0.
- frameMs new/HEAD (128px, 4 rounds, noisy): 0.58/0.72/0.95/1.03 → median ≈0.84. precommit ✅ naga-wasm ✅.
