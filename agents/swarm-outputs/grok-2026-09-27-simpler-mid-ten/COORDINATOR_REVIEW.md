# Coordinator review — simpler / mid generative ten

Reviewed against `BRIEFS.md`.

| Shader | Card before diff | Ideas pointable | Keep holds | Overlay shared | Packing | Params | Springs | Naga |
|---|---|---|---|---|---|---|---|---|
| gen-acid-lissajous | yes | cusp dwell; 2:1 lobes | beads, waist, strands | no | ACES display | exact | existing only | pass |
| gen-audio-spirograph | yes | stator; cusp flash | gears, hubs | no | history + coverage | exact | existing only | pass |
| gen-barnsley-fern | yes | pinna rachis; crozier | probabilities, stem rib | no | ACES display | exact | existing only | pass |
| gen-apollonian-gasket | yes | stipple; kisses | rims, k tint | no | linear A, ACES display | exact | existing only | pass |
| gen-aperiodic-monotile | yes | kite notch; metatile | reflection, brim | no | ACES display | exact | none added | pass |
| gen-bifurcation-diagram | yes | transient; cobweb | mix, lyap ridge | no | HDR density | exact | existing only | pass |
| gen-chaos-game-ifs | yes | settle age; scaffold | hole, vertex tint, one SDF | no | ACES display | exact | existing only | pass |
| gen-conway-game-of-life | yes | split deaths; lean | rules, heat, amber | no | raw CA | exact | existing only | pass |
| gen-art-deco-sky | yes | setbacks; mullions | searchlight, halos, fluting | no | pre-ACES history | exact | none added | pass |
| gen-alien-flora | yes | gills; spores | stem+cap, SSS | no | linear history + alpha | exact | none added | pass |

Pass 10/10.

Gates: Naga 10/10, extraBuffer 0 new, dead sliders 0 new on these ids, catalog 1,373, Jest 741 pass / 6 fail / 1 skip (pre-existing WASM `bridge/api.js`), `SKIP_WASM_BUILD=1` build compiled.

Real-GPU visual QA: external. Do not claim the pictures look right from this VM.
