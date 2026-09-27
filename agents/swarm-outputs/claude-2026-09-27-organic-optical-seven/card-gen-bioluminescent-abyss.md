SHADER: gen-bioluminescent-abyss
(file: public/shaders/gen-bioluminescent-abyss.wgsl, JSON: shader_definitions/generative/bioluminescent-abyss.json, id inside is gen-bioluminescent-abyss; edited in place)

IDENTITY (one sentence): an endless raymarched deep-sea floor drifting past swaying tube worms with glowing tips and cone-shaped thermal vents, lit by a mouse-driven submarine spotlight.

KEEP VERBATIM:
- `map()` (floor fbm, worm domain repetition + sway, vent cones, mat ids 1/2/3/4), the 128-step `raymarch`, `calcNormal`, camera (orbit yaw from mouse, target drifting in +z on `u.config.x*0.1`).
- Audio seasons from `plasmaBuffer[0].xyz` (bloom/harsh/volatile) and their use on tip glow.
- The mouse spotlight on glowing tips (`mouseSpot`, `zoom_config.w` as held flag), hue-by-height tip colour, tip pulse `sin(t*2)`.
- Marine SSS + `calculateMarineAlpha` alpha model, clarity fog `exp(-t*clarity)`, premultiplied `writeTexture` (`color * a, a`), depth `t/100`.
- Four saved params byte-exact: worm_density (x, cell size), current_strength (y, sway), glow_intensity (z, tip glow), water_clarity (w, alpha fog). All four are live in HEAD and stay live and distinct.

ADD (3 native ideas):
1. Tube-worm plume crown (IDEA 1) — the glowing tip is a bare capped cylinder; real tube worms (Riftia) wear a feathery plume of radial gill lamellae. Implemented in shading only (not SDF, so the 128-step march is untouched): a `wormFrame()` helper mirrors `map()`'s cell + sway to get the swayed-axis angle, then a slowly twisting angular lamella ridge (with fine pinnule barbs along height) perturbs the normal tangentially (bump), gates the tip emission (bright gills, dark clefts) and adds a gill rim light. The crown strengthens toward the very top and reads as radial spokes on the top cap. The plume retracts (lamella depth collapses to a smooth bright bud) under the mouse spotlight, at a click bloom, and while a chain-reaction pulse passes through the worm.
2. Chemosynthetic bacterial mats (IDEA 2) — vents are the reason for the ecosystem but currently have no ecology around them. The floor (mat 1) gets a faint emissive mat whose extent falls off with distance to the NEAREST vent centre (3x3 scan of the existing 30-unit vent-cell hash, vent_h > 0.7, only evaluated for floor pixels in shading). Concentric chemical zoning: pale sulphur-white near the cone, orange mid, teal-green far, patchy via the existing `fbm`, with a slow outward breathing wave. Scales with the saved glow slider; mids (nutrient upwelling) ride along.
3. Click chain-reaction (IDEA 3) — HEAD's click is a local exponential bloom around the click point. Now each click also launches an arrival-gated relay along the worm field: a worm's tip lights after `distance(worm cell centre, click) / CHAIN_SPEED` plus a per-worm reaction jitter from the cell hash, flashes and decays, then retracts its crown. Neighbours fire in sequence, so the front visibly hops worm to worm.

FORBID on this file: marine snow (sibling gen-bio-luminescent-jelly owns it), new SDF-heavy plume geometry, jet/tentacle motion, spring/extraBuffer layers, IQ palette stamp, generic ripple rings.

A PACKING: ACES display RGBA in A (temporal trail `mix(prev*0.96, display, 0.25)` on rgb AND on alpha). HEAD packing kept (display colour history read back from C); only alpha changes from hardcoded 1.0 to the real alpha trail. Note HEAD's A history is never blended into `writeTexture`; that output model is preserved as instructed.

SILENT BUGS FIXED (disclosed):
- Click age used `time = u.config.x * 0.1` (`time - ripple.z`); ripple.z is on the `u.config.x` clock, so a click bloom only started once 0.1*clock exceeded the click time (about 9x the click time later) and then aged 10x too slowly. Now `clock - ripple.z` with `clock = u.config.x`. The camera keeps its 0.1-scaled `time`.
- Ripple xy -> world was `ripple.xy * 8` (arbitrary, not the spotlight's mapping). Now uses the spotlight's exact mapping `(x*10 - 5, y*8 - 4)`. Additionally the spotlight/click mapping is anchored to the camera's ground position (`target.z` at the relevant time = `0.5 * clock`), because the camera drifts +z at 0.5 units/s while HEAD's mapping was fixed near the origin (the spotlight and every click landed behind the camera after ~20 s). At clock = 0 it is identical to HEAD; a click is anchored to the camera position at its own `ripple.z` (stateless).
- Click bloom was added to `glowIntensity` AFTER the tip colour had been computed, so it only altered alpha (dimming) and never brightened anything. The click accumulation now runs before the colour is built.
- `dataTextureA.a` hardcoded 1.0 -> real alpha trail.
- Filtering `textureSampleLevel(dataTextureC, u_sampler, ...)` on rgba32float -> exact `textureLoad(dataTextureC, coord, 0)`.
- No ACES in HEAD: added on display RGB (exposure-scaled), so the overall tonality (bright tips compress, mid values shift) changes; this is the plumbing floor, not an idea.
Noted, not changed: HEAD's A history never reaches `writeTexture`, so the temporal trail only matters to downstream/next-frame readers of C.

Not verified visually (no GPU in this environment).

Gates: naga OK; wgsl_precommit_gate 1/1 pass; audit_dead_sliders 1305 scanned, 0 new dead (all four zoom_params x/y/z/w read by hand in WGSL). JSON: only `upgraded-rgba` added to features; params byte-exact.
