# NOTES fork D — physarum-gemini, physarum-grokcf1 (first pass + rescue)

## Shared rescue (both files)
HEAD kept agents in extraBuffer (re-uploaded every frame, so the app never moved them) and stored writeTexture only at agent texels (rest of the frame undefined). Rescue = Eulerian agents in A, the pattern from gen-wasm-hls-physarum-swarm: A = (trail density, mx, my, caste), |m| = mass, m/|m| = heading, semi-Lagrangian gather + winner-take-all heading + flow-Jacobian thickening. Full-frame display with Beer–Lambert transmittance over the photo, ACES, alpha = mix(0.35,1,coverage). Corner-texel sentinel (A(0,0).r = -0.6875) reseeds when C holds another shader's frame. Mouse down spawns agents (radial outward heading).
Kept: personality colour fns, transmittance/hdrEmission, 4 slider roles (radius→mass cap, deposit, sensor dist 5–15 px, decay), nutrient-speed rule, 5% random turn, pulse.
Changed rule: HEAD steered toward LOWER density (never ran); Eulerian mass needs attraction to form veins, so sensors now steer toward trail + food.
Audio: bass → deposit / halo / rim; mids → turn rate, seams, streaming.

## physarum-gemini
IDENTITY: slime-mold network with "alpha scattering / physical light transport".
ADD: (1) forward-scatter halo — 2 taps up the light path, in-scatter × transmittance; (2) caste contact seams — 3×3 caste spread lights fused membranes; (3) caste-synchronised pulse flashes (HEAD pulse made soft and per caste).
## physarum-grokcf1
IDENTITY: same sim, cyan/green palette.
ADD: (1) contour foraging — sensors smell photo luminance edges (tubes trace outlines); (2) ectoplasm rim over dark endoplasm core (trail gradient); (3) shuttle streaming — bands along heading that reverse every ~2 s.

Timing (256², load ~12): HEAD ≈ free (dead path); gemini 109 ms, grokcf1 112 ms vs gen-wasm-hls-physarum-swarm 74 ms (~1.5×). Not trimmed: no live HEAD to compare against.
Gates: verify-naga-wasm --files 2/2 valid; SwiftShader render 256² 200 frames, no NaN, network forms. JSON features + description appended.
Not done: real-GPU look, shader lists (coordinator). Harness copy: agents/mr_forkD.mjs.
