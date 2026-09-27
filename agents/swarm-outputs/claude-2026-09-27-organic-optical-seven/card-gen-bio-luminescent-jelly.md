SHADER: gen-bio-luminescent-jelly

IDENTITY (one sentence): one drifting 2D SDF jellyfish, a domed pulsing bell over 8 chained-segment tentacles, with treble sparkles, mouse attraction and a held-click shockwave.

KEEP VERBATIM:
- Bell SDF (circle scaled 1.3 in y, flat cut at `bellP.y > 0`), `bellRadius = 0.18 + pulsePhase*0.04*(1+bassSmooth)`.
- 8 tentacles x 5 segments loop, `sdSegment` + `smin_j` union, `tentacleGlow`, the sway sines and `waveAmp`.
- Params (zoom_params.x pulse speed, .y tentacle length, .z glow intensity, .w drift speed), drift + mouse attraction, held-pointer shockwave, treble sparkles, glow hue, gamma + ACES tail, alpha model.
- `pulsePhase` read from `dataTextureC.r` and written to `dataTextureA.r` (identical for every pixel).
- Pre-existing quirks left alone so the default look holds: `env_j(0.5, bass, ...)` uses a constant prev (so bassSmooth is about 0.47 at silence); tentacles run toward -y from the ring (same side as the dome, given the y-down `flatten bottom` comment). Not touched.

ADD (3 native ideas):
1. IDEA 1 Jet propulsion: an analytic contraction wave (`thr[s] = max(0, -cos(pulseSpeed*(time - 0.09*s)))`, delayed per segment so it travels down the tentacle) straightens the sway and stretches each segment while the bell squeezes; the tentacles also lag and stream opposite the analytic drift velocity (`d(drift)/dt` in closed form, x0.85 for the attraction blend). Belongs here: this is how a medusa actually swims, and it uses the pulse the shader already runs. Stateless (no history), visible at audio = 0.
2. IDEA 2 Anatomy: 4 radial canals with a travelling glow from centre to margin, a ring canal that follows the (scalloped) bell margin via the SDF depth, a horseshoe gonad (open toward the margin), and 8 rounded lappets with V-notches on the flat margin. The generic `innerGlow` shell stays but at 0.55 weight as diffuse mesoglea; the organs read on top. Belongs here: adds a real body plan to the same bell SDF, not a new creature.
3. IDEA 3 Lit marine snow: two stateless parallax cell layers of sinking specks (hashed jitter, gentle sway); each speck is lit by inverse-square distance to the jelly, pulses with the bell, and gets a halo that grows near the jelly. Belongs here: the jelly's own glow becomes the light source that reveals the water column.

FORBID on this file: springs / `extraBuffer[133..138]` (zeroed every frame), ripple shockwaves (the held shockwave already exists), IQ palette overlay, another creature, worm plumes / vent mats / click chain-reaction (sibling gen-bioluminescent-abyss).

A PACKING: raw sim state, unchanged: `A.r` = pulsePhase (raw, un-tone-mapped, the same value at every pixel, read back per pixel from `C.r`); `A.g` = `A.b` = 0; `A.a` = semantic alpha. `writeTexture` carries ACES display RGB + semantic alpha. No B writes.

SILENT-BUG AUDIT: no zero-C early return (pulsePhase just ramps from 0); no ripple.w, pow(negative), or dead-mask patterns; `dataTextureC` is read with exact `textureLoad`. Nothing found to fix. All four sliders were already live and stay so.

DEFAULT-LOOK NOTE: at slider defaults the bell, tentacle chain, glow colours, drift and mouse attraction are unchanged. Visible differences are the additions: tentacle streaming/stretch, canals/gonad/lappets, and faint lit specks. Not visually verified (no GPU).
