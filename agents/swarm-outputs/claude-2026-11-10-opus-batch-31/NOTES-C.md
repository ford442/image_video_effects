# opus/batch-31 — fork C notes

Measured on SwiftShader, 192², defaults, idle pointer (0.5,0.5), 8–12 frames. Δ = % of pixels with |Δ| > 0.02 on writeTexture RGB, idea on vs idea removed.
Timing: 512², 30 frames, two runs each (SwiftShader, noisy).

## gen-erosion-strata
- Kept verbatim: fbm/voronoi kernels, lh/li/lf layer stack, era palette (moved into `bandColor()`, identical values/order), all 4 param roles, existing ideas (contacts, cross-beds, ripple marks, concretions), fossils, veins, quake ripples, held-pointer glow.
- A packing: ACES display RGBA (unchanged).
- Ideas (new):
  5. Creeping normal faults + gouge — Δ 65.3 %.
  6. Desert-varnish drips from the exposed bed face — Δ 11.4 % (first try hung from lf=0 where alpha≈0: 0.2 %, moved to the exposed face).
  7. Pool reflection of band colours below the water line, ripple wobble; alpha ≥ 0.55 in the pool — Δ 26.0 %.
- Rescue: water line was upside down (y-up maths on a y=0-top screen: the "wet" band sat at the top of the frame and the pointer moved it inversely). Now `yUp = 1 - uv.y`, pointer `1 - zoom_config.z`.
- Timing: HEAD 92/112 ms vs new 110/86 ms → ~1.0–1.2×.
- JSON unchanged (features already truthful).

## gen-cosmic-velvet-hypnosis
- Kept verbatim: spiralPhase / velvet / rings / runner / counterSpiral / velvetWeave formulas, existing 4 ideas, click halos, drag swirl, history smear, param roles.
- A packing: ACES display RGBA (read back as colour history) — unchanged.
- Ideas (new):
  5. Tufted buttons at arm × octave-seam crossings (dimple, 4 pleats, button highlight) — Δ 16.1 %.
  6. Breathing trance zoom (log-radius inhale/exhale, bass deepens) — Δ 99.8 % (global motion).
  7. Negative afterimage of C history in the troughs — Δ 68.8 % (gain trimmed 1.4→1.0).
- Rescues: (a) atan2 branch-cut seam on the −x axis (visible horizontal cut at HEAD): hue now `abs(angle)/PI` (same 0..1 range, mirrored), moire angular frequency rounded to an integer; (b) `max(hdr, 0)` before ACES — palette G dips to −0.05 and ACES mapped negatives to a ~0.2 glow. Hue mirroring shifts the palette layout vs HEAD (expected).
- Timing: HEAD 51/41 ms vs new 43/43 ms → ~1.0×.
- JSON unchanged.

## Gates (both files)
wgsl_precommit_gate OK, verify-naga-wasm --files OK, audit:dead-sliders PASS (2 defs scanned), audit:extrabuffer PASS, no NaN at default or with audio (1,1,1) + held pointer. Real-GPU visual QA: external.
