# Quantum / Psychedelic Seven — NOTES (2026-09-27)

Requested ten; seven upgraded. `gen-protocell-division` (09-21), `gen-psychedelic-moire-flower` and
`gen-psychedelic-time-warp-kaleidoscope` (09-09) already carry `Ideas:` lines and were left alone.
"gen-psychedelic-spiral" is `gen_psychedelic_spiral` in the catalog.

| Shader | Ideas in the diff | Kept verbatim | A packing |
|---|---|---|---|
| gen-psychedelic-layered-time-stamps | lagged echo taps; postmark rings; delay wavefront | zoom_params roles, distortion + chroma split, OkLab/blackbody mix, Fresnel rim, alpha, depth | raw pre-ACES RGB + delay clock in A.a |
| gen_psychedelic_spiral | petal-tip pearls; pen-trace rosette; nested outline ladder | spiroCenter, superformula, ghost ring, core/band/spokes, palette, feedback UV chain, mouse offset | raw hue-clamped colour history + presence alpha |
| gen-quantum-acoustic-bioluminescent-void-urchin | spine firing waves; C afterglow; cage void-reflection | map() SDFs, matIDs, glow accumulation, mouse orbit/bend, membrane shimmer | ACES display RGBA |
| gen-quantum-entangled-ferrofluid-engine | Rosensweig spike lattice; entangled-pair filaments; psi^2 nodal contours | sphere + satellites, fbm spikes, PBR, centre glow, vignette, chroma shift | ACES display RGBA |
| gen-quantum-fluorescent-aether-moth-swarm | wingbeat flutter; flight-aligned smear; lantern orbit; idle roost mandala | curl2 flow, spawn blobs, trail advect/decay, mouse gravity+scatter, audio mandala | raw HDR RGB + semantic alpha |
| gen-quantum-fluorescent-nebula-anemone | nematocyst beads; Stokes-shift afterglow; breathing oral disc | 22-tentacle loop, fBm nebula, god rays, hue clamp, ACES, dither | raw field state |
| gen-quantum-foam-alpha | virtual pair flashes; Born-rule hits; foam membranes | pair loop, vacuumField feedback, collapse glow, uncertainty alpha | raw sim state, unchanged |

## Silent bugs fixed on the read path (all noted in cards)
- ferrofluid: filtered sampler on rgba32float history -> exact textureLoad; post-ACES history fed into pre-ACES mix
  (now acesInverse); ripple strength used `ripple.z` (start time); audio faked from ripple positions -> plasmaBuffer;
  glow snapshotted at end of march.
- spiral: click ring scaled by `ripple.w` (always 0) -> dead clicks; ripple age used x5 time vs raw stamp.
- anemone: audio read `config.y` (click count) -> plasmaBuffer; ripple strength used `r.z`.
- foam-alpha: Cloud Density and Collapse Strength were dead sliders (now wired; default reproduces old collapse);
  `localSigma` crossed zero while held -> NaN alpha, now floored.
- layered-time-stamps: `plasmaBuffer[1..255]` per-layer colour was black; pow negative base clamped; feedback read
  was a filtered read of a delay-counter texture.

## Judgement calls the user should look at
1. **anemone slider roles changed.** HEAD's WGSL read x/y/z/w as Reach/Fluorescence/NebulaDensity/QuantumFreq while the
   JSON labels them Fluorescence/Tentacle Density/Audio Reactivity/Nebula Density. The WGSL now honours the labels.
   Mapped values equal HEAD's at the 0.5 defaults; a saved preset at other values will look different.
2. **layered-time-stamps default look is not numerically identical to HEAD** (per-layer tint is now hue-varied
   instead of black-plasma monochrome; feedback is a real read).
3. **ferrofluid trail look changes slightly** (acesInverse decode of history).

## extraBuffer
The request asked for bounded extraBuffer[133..138]. `writeExtraBuffer` uploads the whole 256-float scratch every
frame, so [133..255] is zeroed each frame and can never hold state. No shader here stores state there. Ideas that
needed memory used A/C texture history instead.

## Gates
naga 7/7, wgsl_precommit_gate 7/7, extraBuffer audit PASS, dead-slider audit (scanned 1291; for the 5 JSONs with
only `updatedParams` all four zoom_params.xyzw grepped by hand), generate_shader_lists + check_duplicates clean
(1386 unique IDs), Jest 6 failing suites = identical set on clean main (WASM bridge imports; not regressions),
`SKIP_WASM_BUILD=1 npm run build` OK. Real-GPU visual QA: external, not done.
