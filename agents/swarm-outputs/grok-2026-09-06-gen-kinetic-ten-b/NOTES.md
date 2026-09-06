# Notes — Grok simpler generative / kinetic ten B (2026-09-06)

Cards: `BRIEFS.md`. Underscore-backed files kept (`gen_cyclic_automaton.wgsl`, `gen_fluffy_raincloud.wgsl`). Saved `params` not rewritten (JSON diffs are `features` tags only).

| ID | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| gen-barnsley-fern | scale/CA/brightness/feedback; pickIFS; barnsleyInv | ACES display RGBA | last-affine tint (`lastIdx`); stem rib from idx 0 |
| gen-apollonian-gasket | recursion/inversion/size/rainbow; five seeds; circle_inv | linear RGB then ACES display | packing rims on seeds; curvature tint from last k |
| gen-conway-game-of-life | seed/morph/grid/decay; B3/S23 family | raw alive, generation, activity, alpha (ACES display only) | neighbor-count heat; still-life amber |
| gen-cyclic-automaton | States/Spontaneity/Bloom/Cooldown; GH rest/fire/refract | raw state, fire, refract, bloom | cardinal chirality; just-fired halo (`nextState==2`) |
| gen-chaos-game-ifs | iterations/glow/rings/sat; existing SDF sculpture | ACES display RGBA | `ifsPoint` lastPick occupancy; Sierpinski hole |
| gen-bifurcation-diagram | r window/zoom/iterations/scheme; logistic + lyap | HDR density in A | continuous scheme mix; lyap≈0 period ridge |
| gen-acid-lissajous | speed/complexity/glow/feedback; STRANDS×SAMPLES | ACES display RGBA | origin-crossing beads; freqX≈freqY waist |
| gen-audio-spirograph | freq/audio/trail/thickness; epi+hypo | history RGB + coverage | additive gear glow; rolling-center hubs |
| gen-cycloid-bloom | spin/petals/glow/persistence; coarse+refine | ACES display RGBA | `bestT` vein; origin stamen. No extraBuffer spring |
| gen-fluffy-raincloud | coverage/turbulence/rain/wind; curl solver | raw density, vx, vy, moisture | anvil deck; virga (display uses `virga`) |

No new extraBuffer owners. Springs only where HEAD already had them. Cyclic and raincloud keep existing `[133..138]` springs. Cycloid still does not write extraBuffer.
