# Notes: Densest Medusa→Citadel Seven

Bug patterns found at HEAD that are new to this batch. Grep the catalog for them.
- **Upside-down generative scenes.** `uv = (fragCoord*2 - dims)/dims.y` with no y flip maps the screen top to -y, so the
  owl, seahorse and citadel rendered upside down. All three were flipped. The medusa has an explicit "inverted"
  comment and was left as is; flagged for GPU QA.
- **A rounded-cube repeat grid fills all of space.** `sdBox(p - cellCentre, 0.45s) - 0.05` is below 0 at every cell
  corner when s < 0.577, so the march stops at t=0 and normalize(0) gives NaN. The citadel was blank at every slider
  value.
- **A `.xzy` swizzle on the camera orbit.** It jumps the camera overhead, and at one mouse position ro.xz is 0, so
  cross(fwd, up) is 0 and the frame goes NaN (medusa).
- **dataTextureC.r read as "audio"** (medusa). This joins the "own C history used as audio" family.
- **Mouse divided by resolution.** zoom_config.yz is already 0..1, so the mouse is dead or pinned
  (arachnid, citadel).
- **time × (audio-scaled speed).** The phase jumps hundreds of radians with the music at large t (neural lattice,
  citadel).
- **Step exhaustion shaded as a hit** (owl, medusa).
- **The camera starts inside a moving membrane in about 22% of frames**, so t goes negative and surfaces behind the
  camera get drawn (neural lattice).
- **A glow coefficient that goes negative in the slider's upper range** leads to an e^40 whiteout (arachnid z > 2.33).

Idea swaps agents made (all justified in their cards):
- seahorse: fold-plane threads were replaced by a fold-tree chromatophore cascade, because the tail is disjoint beads
  and orbit-trap filament glow is already saturated.
- orrery: eclipsing moons were refused (about 2 px wide, and they would double the body loop).
- neural: cage lanterns are lit from behind the hit rather than accumulated in the march, because the median hit is
  about 0.2 from the camera.
- arachnid: raising feedback persistence was refused (silk afterglow via C is saturated).

JSON oddity left in place: arachnid's z default 0.5 is below its min of 1.0. Params must stay byte-exact.
Neural lattice's stale `controls` array was also left alone.
