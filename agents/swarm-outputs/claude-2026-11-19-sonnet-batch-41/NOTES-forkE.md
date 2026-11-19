# NOTES — fork E (sonnet/batch-41)

Harness: SwiftShader, box load 30–55 (other forks running) → timings noisy. Scratch: scratchpad/forkE/.

## gen-polar-rainbow-explosion
- KEEP VERBATIM held (Cauchy click shocks, Descartes bows/Alexander, supernumerary fringes, ray-bow knots untouched). A packing unchanged (ACES display RGBA in A, acesInverse feedback).
- **Rescue 1 (confirmed):** HEAD added the two shock-front terms once per ray with no ray mask (36× an unmasked ring) → idle frame white most of the 4 s shock cycle: meanL 0.871 / 0.939 / 0.859 at t=0.8/1.5/2.0 (stdL 0.036 at 1.5), held 0.988. Gated by an angular lobe 3× ray width. Rescue-only perf 0.93–1.09× HEAD.
- **Idea 5: burst comet tails** (native) — one tail per burst along its ray, length ∝ burstSpeed·(0.3+speed), reddening behind the head. Visibility 2.37 % px >0.02 at 192 (local streaks; first per-particle version was 4.0 % at 192 and 576 but cost ~1.5×, so moved to one tail per burst and widened).
- **Idea 6: shock-front ray refraction** (native) — rays kink by the signed gaussian derivative of the front (∝ 0.6+bass). Visibility 49.3 % (192) / 49.5 % (576), mean|Δ| 0.053.
- Default look idle t=1.5: meanL/stdL 0.939/0.036 → 0.587/0.148; held 0.988/0.016 → 0.686/0.192; audio 0.706/0.072 → 0.589/0.163; 60 f t=4 0.581/0.188 → 0.521/0.144. nan 0.
- frameMs per-round ratios after trim: 0.95, 1.51, 0.91, 1.17 (median ≈ 1.06×; one load outlier). Coordinator should re-time alone.
- Sliders: all four change the picture (intensity 0 → meanA 0.2; others shift stdL/meanA). JSON unchanged (tags already true).
- Gates: precommit pass, naga-wasm pass, dead-sliders AUDIT PASS, extrabuffer no findings.
- Open: still a broad pink centre-glow wash (centerGlow at colorShift 0 is pink) — identity, left alone. mouse burst sits at cursor while origin is mouseNorm*0.5 (HEAD, left).

## gen-chronodynamic-aether-weaver-automata
- HEAD fine (idle 0.207/0.163, held 0.208/0.161, audio 0.291/0.201; gear + live-tooth spikes + threads). No rescue. Header `Ideas:` listed only ideas 3–4 though the code carries ideas 1–4 → prepended ideas 1 and 2 names (truthful header fix). KEEP VERBATIM held. A packing unchanged (HDR pre-ACES in A, exact C reads).
- **Idea 5: shuttle flight laying a weft pick** (native) — per tooth pitch (generation) a shuttle crosses the loom, direction by gen parity, lane by gen hash, brass weft behind it, persisted by the existing C echo; mids brighten. Visibility 2.9 / 2.8 % (t=2, 192/576), 2.6 / 2.8 % (t=6). Shuttle stops when Loom Rotation Speed = 0 (gen frozen) — consistent with the loom.
- **Idea 6: heat-blued temper colours** (native) — straw→bronze→purple→blue by depth into the gear face, warmed toward straw near the mesh pitch point. Visibility 56.4 / 57.0 % (t=2), 54.5 / 55.3 % (t=6).
- Default look: idle 0.207/0.163 → 0.253/0.189 (30 f t=3); held → 0.267/0.192; audio → 0.341/0.221; 60 f t=8 0.249/0.189. nan 0.
- frameMs (single renders, loaded box): HEAD ≈ 270–283, new ≈ 190–306; interleaved perf log was lost — coordinator should re-time. Added work is O(1) per pixel (no loops), so expect ≈1.0–1.05×.
- Sliders: all four sweep min→max change stdL/meanA. JSON unchanged.
- Gates: precommit pass, naga-wasm pass, dead-sliders AUDIT PASS, extrabuffer no findings.
