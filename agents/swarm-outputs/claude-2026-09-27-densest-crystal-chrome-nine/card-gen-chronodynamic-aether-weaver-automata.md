```
SHADER: gen-chronodynamic-aether-weaver-automata
IDENTITY: a 2D clockwork loom — two rotating sdGear gears (12 and 8 teeth) with metallic banding and edge glow,
  crossed by sine+noise "aether" thread splines with node glints, echo trails and a chromatic smear.
KEEP VERBATIM: sdGear (L60-65), the two gears' placement/teeth/rotation sense (L106-117), metallic banding + edge glow,
  thread spline formula family (L124-148), node glints, 4 slider roles (x thread_count, y loom_rotation_speed,
  z aether_bloom, w temporal_decay), saved params/updatedParams. applyGenerativePrimaryControls may stay but must not
  double-map a slider into something unrelated (document if kept).
FIX/WIRE (major first):
  - THREADS DEAD: i32(u.zoom_params.x) (L120) = 0 threads for every x < 1.0 (default 0.5!). Map x to a real count,
    e.g. 2 + x*10 (default -> 7), fractional last thread fading in.
  - Audio from u.config.y (L81 = rippleCount) feeding thickness/glow (L132,142,144) -> plasmaBuffer[0].xyz.
  - Thread colour reads plasmaBuffer[0..255] (L138-139) -> black/undefined. Use a real per-thread colour.
  - "Previous frame" is readTexture (L164: the input photo) and the chromatic smear samples readTexture (L178-182),
    mixing 20-35% of the user's photo into a generative shader -> use exact textureLoad(dataTextureC) for echo/smear.
    Fix the back_uv=1.0 off-edge read.
  - Mouse "click" test mouse.x>0 && mouse.y>0 (L96) is ~always true -> use zoom_config.w for held.
  - y rotation: time*speed (L106/108) phase jump when the slider moves -> accept only if documented; prefer a
    continuous base spin plus slider.
  - Reinhard + pow + gain up to 1.45 (L171) -> ACES on display. Alpha 1.0 (L189) -> semantic.
  - A packing lie: A = (thread.r, thread.g, gear.b, 1) (L191) while C is read as colour -> display-consistent HDR RGBA.
  - Depth: glow-based unclamped (L188) -> gear coverage (gears near, threads mid, void 0).
  - JSON description "" and features [] -> fill honestly (params untouched).
ADD (native ideas):
  1. Gear-tooth automaton ring — each tooth of each gear is a cell of a 1D elementary cellular automaton; the ring
     advances one generation per tooth pitch of rotation (stateless: Rule 90 from a single seed via the Lucas/bitwise
     test cell(i,g) = ((g+i)/2 & (g-i)/2)==0 with parity, or equivalent), live teeth glow/extend. The meshing contact
     tooth of gear 1 seeds gear 2's ring, so the two gears pass the pattern like a clockwork computer. This makes the
     "automata" in the name real.
  2. Capstan wrap — the threads bend along the gradient of the gear SDF and wind onto the rotating hubs (tangential
     deflection within a band around each gear, advancing with the gear angle), so thread field and gear field become
     one mechanism instead of two overlaid layers.
FORBID: heddle lanes, plasma shuttle, warp thread-memory ghosting, over-under interlacing, escapement tooth gates,
  backlash lag, Keplerian gearing, spring cursor, ripple rings, IQ palette stamp.
A PACKING: HDR display RGBA + semantic alpha; C read exactly as colour history (echo trails).
DEFAULT-LOOK SHIFT: HEAD had 0 threads at default and a 20-35% input-photo tint; now threads + automaton teeth,
  no photo bleed. Not GPU-verified.
```

STATUS: draft (coordinator) -> superseded by Final below

## Final (implementer, 2026-09-27)

AUDIT CLAIMS (vs HEAD): all verified. i32(zoom_params.x) = 0 threads below 1.0 (default 0.5 drew no threads);
audio = u.config.y (ripple count); thread colour from plasmaBuffer[idx], idx grows with time -> zero/garbage;
"previous frame" and chromatic smear both read readTexture (user photo, 20-35% bleed); filtered C sample at 3%;
held test mouse.x>0 && mouse.y>0 always true; Reinhard + applyGenerativePrimaryControls (x->intensity, y->speed
pulse, z->contrast pow, w->mouse gain: every slider double-mapped); alpha 1.0; A = (thread.r, thread.g, gear.b, 1)
while C read as colour; depth from glow. Extra finding: the HEAD planet gear is bolted to a rotating arm (orbits the
sun, never spins on its own axle), so its teeth skid over the sun. back_uv = 1.0 read texel res (off-edge).

FIX done: threads 2 + x*10 (default 7, fractional last thread fades); audio = plasmaBuffer[0].x (bass) for the HEAD
audio roles, mids/treble keep the chromatic roles; per-thread colour (aether blue -> brass by thread hash); echo +
chromatic smear are exact textureLoad(dataTextureC) with clamped coords (no photo bleed; the separate 3% C blend is
folded into the echo); held = zoom_config.w > 0.5 (pull), else HEAD bend; applyGenerativePrimaryControls removed
(double-mapping); ACES on display only (x1.2 exposure); semantic alpha = coverage*0.85 + luma; A = HDR pre-ACES RGB
+ alpha (C re-blended in the same space, no double tone-map); depth sun 0.9 / planet 0.8 / threads 0.5 / void 0.
Rotation kept as HEAD time*speed (stateless; moving the slider re-phases gears and the automaton clock; documented).

IDEAS as implemented (line numbers in the new file):
  1. Gear-tooth automaton ring — helpers L60-112 (rule90 L73, toothAutomaton L85-103: coupled Rule 90 on 12- and
     8-tooth rings, one generation per sun tooth pitch past the mesh, sun contact tooth XOR into planet contact tooth,
     planet tooth leaving the mesh XOR back into the sun, fresh single-tooth seed at the mesh every 24 generations;
     stateless, <=23 uniform bit steps x2 calls). Main L162-214: planet now rolls on the sun without slip
     (spin2 = 1.5*(a2-a1)+phi0, orbit unchanged; numpy-verified sun tooth <-> planet gap at every contact, scratch
     mesh.py), live teeth stand proud (+0.05/+0.04 at the crown), burn amber, just-born teeth flash, the handed bit
     glints at the pitch point. Numpy sim (scratch ca.py/ca2.py): the two-way coupling with the "leaving" tooth keeps
     both rings lively; the uncoupled 8-ring dies in 4 generations and the 12-ring locks to period 4.
     ~4.2 s per generation at default speed; frozen at speed 0 (the clock stops).
  2. Capstan wrap — capstanWrap L114-118; main L216-229: thread lookup q swirled about each hub by exp(-|gearSDF|/w)
     (sun clockwise, planet counter-clockwise, drag 0.9*(0.4+speed) rad), wound turns cos(ang*36 / ang*24) ride the
     rim in gear-local angle, wrapped thread brightened (capstan_gain) in the loop L238-268.
AUDIO roles (not ideas): bass -> thread sway/thickness/node glints/smear width; mids/treble -> smear offsets;
  treble -> tooth lamp gain. Everything above is visible at audio 0 (nodes have a 0.4 base).
SLIDERS: x thread count (2..12), y gear/automaton speed + capstan drag, z thread brightness + halo bloom,
  w echo decay. params/updatedParams byte-exact; JSON gained description + features [upgraded-rgba, audio-reactive,
  mouse-driven] only.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha; C read back exactly as HDR colour.
REFUSED/SKIPPED: no ripples/spring added (HEAD has none). Did not make rotation phase-continuous (needs state;
  extraBuffer[133+] is zeroed per frame).
DEFAULT-LOOK SHIFT: HEAD default had 0 threads and a 20-35% input-photo tint + Reinhard/pow grade; now 7 coloured
  threads wrapping the rims, lit automaton teeth, planet visibly rolling (~3.5x faster world spin than HEAD's arm-only
  motion), ACES. Gates: naga OK, precommit gate pass, dead-slider audit pass (1305 defs scanned). Not GPU-verified.

STATUS: final
