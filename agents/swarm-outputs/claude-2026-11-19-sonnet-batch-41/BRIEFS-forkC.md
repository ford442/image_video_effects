# BRIEFS — fork C (sonnet/batch-41)

## gen-showcase-nebula-core (2nd pass; existing Ideas: chaos filaments, warp lens, photoevaporation pillars — KEEP VERBATIM)
HEAD render @0.5×4 (192): idle meanL 0.286 stdL 0.213; held 0.308/0.220; audio 0.8,0.5,0.9 0.706/0.222. Picture fine (Balmer disc, 4 pillars). No rescue. Read-only defects noted: CA is a constant +r/−b offset (not spatial); `col` can be negative before ACES (bass rings `sin` × cyan, `b − caStr`) → clamp ≥0 before acesToneMap (rule 9 fix, not an idea).
§12.1: (1) what moves? gas via domain warp, history via C convex mix — but history is read at the SAME pixel, so trails never travel. (2) what's missing physically? the ionisation front is a soft colour gradient, no shell. (3) audio: bass drives ionization only through colour radii. (6) idle look = static disc.
- **Idea 4: stellar-wind streaming (§12.2 curl-noise advection)** — C history read at `coords − curl(ψ)·k` where ψ = the f3 cloud field's noise; trails stream along divergence-free gas lanes, outward with a radial wind term.
- **Idea 5: Strömgren shell (native)** — thin bright [O III]-teal ionisation front at radius R = 0.55 + 0.3·ionization, crumpled by nebula density; where it cuts a pillar it's hidden (dust).

## gen-quantum-fluorescent-nebula-anemone (2nd pass; existing: nematocyst beads, Stokes afterglow, crenulated oral disc — KEEP VERBATIM)
HEAD render @0.5×4 (192): idle meanL 0.886 stdL 0.088 — **washed-out near-white disc**; held 0.887/0.087; audio 0.907/0.066. Look: no tentacles at all.
- **Rescue 1: tentacles were 22 coincident circles.** `dist = length(rot(angle)*p + (sway,0)) − 1.6` — rotating p about the origin leaves `length` unchanged, so every "tentacle" is the same r≈1.6 ring (± sway), summed 22× → white. Fix: each tentacle is a tapered radial arm in its rotated frame (along = q.x, lateral = q.y + bending sway), r 0.55→2.7. Beads re-parameterised along the arm (still crawling outwards). Overall exposure re-balanced so default meanL lands in a readable range.
- **Idea 4: acrorhagi tip bulbs with Schlick cuticle (§12.2 Fresnel–Schlick)** — a glowing bulb at each arm tip; cosθ from the bulb's radial profile, F = F0 + (1−F0)(1−cosθ)^5 gives an iridescent rim.
- **Idea 5: touch retraction (native)** — clicks (ripples, age window) make arms within reach of the click contract (shorter, thicker) then re-extend over ~2.5 s.
