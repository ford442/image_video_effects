# Fast-motion + psychedelic ten — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `mouse-kaleidoscope-tunnel` | speed / mirrors / twist / depth; `kaleidoscope()` fold; click bursts; 3-layer parallax | `-log(r)` `depthLayer`; R/B `polar.y` split via `tunnelSample` | ACES display RGBA (HEAD never wrote A) |
| `mouse-wormhole-lens` | radius / spiral / hue / lens; invert; oval stretch; click baby portals | `1/r²` lensOffset; `textureLoad` C mix inside portal | ACES display RGBA. Mouse stash extraBuffer[133..134] (1-frame, not a spring) |
| `kaleido-scope` | `poincareMap`; morph 4–7/6–11; ringOffset; Brown lens; CA | `fract(hypR*3.5)` crease; `oppAngle` opposite wedge mix | ACES display RGBA (HEAD unused telemetry) |
| `breathing-kaleidoscope` | cycle / segments / rotation / maxRotation; FBM warp; jewel; grain | `inhale` sign on `sin(phase)`; `mouseDown` holds `liveTime` | ACES display RGBA (HEAD unused telemetry) |
| `hypnotic-spiral` | arms / rot / hue / warp; counter-spiral; click reverse | `mix(rLin, rLog)`; tangent `ride` sample | ACES display RGBA |
| `concentric-spin` | density / speed / smoothW / gapFade; rose/epi morph; lag center | `textureLoad` C lag; `convShift` along ring tangent | lag.xy telemetry (C read as lag) |
| `quantum-tunnel-interactive` | strength / aberration / pulse / twist; [133..138] spring; click mouths; sector FFT | `-log(dist)` pulse into zoom/twist; R/B `twistR`/`twistB` | ACES display RGBA. Existing spring kept |
| `gen-hypnotic-vortex-tunnel` | nRings / rot / zoom / distort; ring×spoke; iris | `fract(z)` seam; `spinDir` even/odd | ACES display RGBA (single ACES) |
| `gen-psychedelic-time-warp-kaleidoscope` | fold / wobble / curl; `applyGenerativePrimaryControls` roles | `textureLoad` smear along fold; bass=mirrors, mids=wobble, treble=curl | ACES display RGBA (HEAD wrote noise to A, filtered C as color) |
| `gen-psychedelic-moire-flower` | 5-lobe `moireFlower`; interference; `neonColor`; CA | petal 8/13; p2 `* 1.068` detune | ACES display RGBA. Speed wired into `t`. Mouse UV not pixels |

Skipped Batch 54–60 overlay kaleidoscopes and Fast-Motion Ten. Quantum tunnel’s spring is HEAD’s, not this upgrade.

Gates: Naga 10/10, precommit 10/10 extraBuffer 0, dead sliders 0 (7 defs with `params[]`; three generative files are `updatedParams`-only and all four `zoom_params` are live), catalog 1,362, SKIP_WASM_BUILD=1 build green. Jest 652 pass / 6 fail = pre-existing WASM `bridge/api.js`. Real-GPU QA external.
