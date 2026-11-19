# BRIEFS — fork E (sonnet/batch-41)

## gen-polar-rainbow-explosion (3rd pass; existing ideas KEEP VERBATIM: Cauchy click shocks; Descartes bows + Alexander band; supernumerary fringes; ray-bow knots)
HEAD renders (192, saved defaults 0.75,0.35,0.5,0, 20 f):
| case | t | meanL | stdL |
|---|---|---|---|
| idle | 1.5 | 0.939 | 0.036 |
| held 0.4,0.6 | 1.5 | 0.988 | 0.016 |
| audio .8/.5/.9 | 1.5 | 0.706 | 0.072 |
| idle | 0.8 / 2.0 / 2.8 | 0.871 / 0.859 / 0.522 | |
**Rescue 1 (white wash):** inside the 36-ray loop the two shock-front terms (`rayColor * shockIntensity …`, `ahead` blue) are added once per ray with NO ray mask → 36× an unmasked broad ring (exp(-|r-shockR|*10)) → frame saturates white for most of the 4 s shock cycle. Fix: gate both by an angular lobe 3× the ray width (shock lights the rays it crosses). Not an idea.
§12.1: (1) what is the noun? rays from a polar burst + particles + optical bows. (2) what moves? particles outward along rays; shock front radially. (3) what's missing physically? particles are round dots with no motion read; rays pass straight through the shock front although it is a density jump. (6) deletion test: each below removes a named, visible thing.
- **Idea 5: burst comet tails** (native) — each of the 72 burst particles drags a hue-split streak back toward the origin along its own ray (length ∝ burstSpeed·speed); same-noun: the bursts already ride rays outward.
- **Idea 6: shock-front ray refraction** (native) — rays kink angularly where they cross the shock front (angular offset ∝ signed gaussian derivative of the front), so the front reads as a lens crossing the ray fan.

## gen-chronodynamic-aether-weaver-automata (3rd pass; KEEP VERBATIM: tooth automaton (Idea 1), capstan wrap (2), cage precession (3), bobbin knots (4))
Header `Ideas:` lists only 3 and 4 — append 1 and 2 truthfully.
HEAD (192, 0.5×4, 30 f, A16): idle 0.207/0.163, held 0.208/0.161, audio 0.291/0.201. Renders fine (sun gear + live-tooth spikes + threads). No rescue.
- **Idea 5: shuttle flight laying weft** (native loom noun) — each tooth pitch a glowing shuttle is thrown across the loom (direction alternates with generation parity, lane per generation hash), pulling a brass weft line behind it; the C echo keeps the laid weft.
- **Idea 6: heat-blued temper colours on the gear faces** (native clockwork) — gear interior gets straw→bronze→purple→blue temper bands by depth from the rim, warmed toward straw near the mesh pitch point (friction heat).
