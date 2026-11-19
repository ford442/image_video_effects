# BRIEFS — fork A (sonnet/batch-41)

## gen-kinetic-neo-brutalist-megastructure (3rd pass; params [] in JSON, x-meta defaults 1,3,1,1)
HEAD render (192, defaults 1,3,1,1): t=1.5 meanL 0.625 stdL 0.001 (flat teal), t=4 0.45/0.25, t=8 0.26/0.08, t=12 0.255/0.005 (flat).
**Rescue 1 (mandatory):** camera at x=0,y=0 flying +z through a lattice repeated in x, y AND z: every cell holds a 3×2h×3 block centred at the origin, and h ≥ 2 fills the y cell, so the camera is inside a tower column for most of the sway → flat frames. Also rd.y = uv.y (screen-down = world-up), so the cap slabs/bridges hang under. Fix: one floating layer (cell.y = 0), camera overflies the street between block rows at y 5.6, pitched down 0.42, screen-up = world-up; pointer repulsion centre is re-derived from the same camera ray (depth 15) so the pointer still lands on the picture.
§12.1: tactic 1 (what does the camera see) — nothing at HEAD; tactic 2 (nouns): blocks, grind seam, server core, repulsion field; tactic 3: repulsion only *pushes* SDF, nothing shows stress; tactic 6: canyon march long & grazing → over-relaxation pays.
- Idea 5: Over-relaxed sphere tracing (§12.2 row, pre-assigned) — ω=1.6 with Keinert fallback; far blocks/bridges resolve within 100 steps.
- Idea 6: Repulsion-shell stress fractures (native) — concrete within ~1.2·R outside the pointer's repulsion sphere darkens and opens hot hairline cracks (two folded fract families keyed by cell hash), bass-lifted.

## gen-hyperdimensional-bismuth-lattice (3rd pass; defaults 0.5×4)
HEAD render: t=1.5 meanL 0.45 (close-up inside the crystal), t=4/8/20 meanL 0 stdL 0 — **black forever after ~3 s**.
**Rescue 1:** ro.z = −3 + 1.25·time flies straight through a finite fold fractal → every ray misses. Also uv.y screen-down = world-up. Fix: orbit camera (radius 5.2, Speed still drives rate via t), look-at near origin, screen-up = world-up.
Existing ideas 1–6 KEEP VERBATIM. Step-count AO: not added (file has its own AO).
- Idea 7: Recess-thickened oxide (native) — 1−ao (sheltered hopper steps) advances the thin-film palette phase one order and blends it in; exposed faces unchanged.
- Idea 8: Molten bismuth bath (native) — a liquid-metal plane at y=−2.1 under the crystal (hopper crystals are pulled from a melt): convection shimmer, Schlick-style grazing sheen, bass-lifted orange crucible glow at the foot and a foot shadow; replaces the black void below the crystal.
