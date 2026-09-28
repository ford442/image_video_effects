```
SHADER: gen-cybernetic-crystalline-neuro-lattice
IDENTITY: an infinitely repeated raymarched cell where a gyroid sheet smooth-blends with 4-fold IFS crystal boxes,
  cyan crystal "nodes" vs magenta gyroid "links", fog, mouse-held bend/shock, ripples, A/C feedback.
KEEP VERBATIM: rot3D, sdGyroid (L42-45), ifsCrystals (L48-56), map's smooth blend and material id (L84-94), node/link
  colour scheme (L172-196), fog, ACES on display, A=HDR with exact C read, ripples (HEAD, not an idea), 4 slider roles
  (x node_density = cell size, y growth_speed, z glitch_intensity, w neon_hue_shift), saved params/updatedParams.
FIX/WIRE:
  - Float % sign bug (L85): WGSL float % keeps the dividend sign -> q never centred for negative coords -> seams on the
    x=0 and y=0 planes through the screen centre. Use p - c*floor(p/c + 0.5).
  - Treble rescales the cell (L83) -> distant cells swim; audio must not change the lattice period. time = config.x +
    audio.y*0.1 (L76) audio jitter on rotation phase -> remove.
  - Camera can start inside geometry / step exhaustion shaded as hit (L154, L230) -> hit only if d < eps; if the camera
    is inside, handle (e.g. start the march past the containing surface or keep the camera in a carved channel).
  - Rodrigues hue rotation uses (1,1,1)/3 (L176) -> k=(1,1,1)/sqrt(3); apply the hue shift to links too if cheap.
  - Mouse-held shock centred on the screen, not the cursor (center L206 unused) and negative shock subtracts colour
    (L209) -> centre on the pointer, clamp >= 0. Mouse y inverted (L64 flip vs unflipped uv L128) -> flip uv, consistent.
ADD (native ideas):
  1. Nucleation front — a spherical growth front sweeps outward from the origin (period set by growth_speed, which
     keeps its rotation role too): cells behind the front have converted gyroid melt -> IFS crystal (the smooth-blend
     weight h biased toward the crystal), cells ahead are still liquid gyroid, with a bright freezing rim at the front.
     Fuses the two existing subsystems through the existing blend.
  2. Memory-crystal bit states — compute the cell index floor(p/cell + 0.5), hash it per time slice, and switch each
     cell's crystal on/off like a stored bit (off cells are gyroid-only / dim). Glitch intensity sets the bit-flip rate,
     reviving the near-dead Glitch slider (at glitch 0 no flips: all bits keep the HEAD state).
  3. (optional) Light-piped links — return d_crystal from map so the magenta gyroid links glow by proximity to lit
     crystal nodes (exp(-k*d_crystal)), i.e. nodes light the sheet.
FORBID: Bragg colour, line-defect waveguides, action-potential runners, saltatory, synapse flash, integrate-and-fire,
  refractory afterglow, dendrite web, triple-junction glow, photoelastic fringes, cage lanterns, thin-film, spring cursor.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: centre seams gone; image upright; growth front and bit states visible. Not GPU-verified.
```

STATUS: superseded by Final below

## Final (implementer, 2026-09-27)

**Audit claims vs HEAD**
- Float `%` seam (L85): VERIFIED. Negative coords landed in (-1.5c, -0.5c] -> off-centre cells and seams on the x/y/z=0 planes.
- Treble rescaling the cell (L83) and mids jitter on the rotation phase (L76): VERIFIED; both removed.
- Camera inside geometry: VERIFIED and WORSE than the card said. After the 4 IFS folds every component of `c` is in about
  [-0.09, 0.41] (numpy, 200k samples), so the 0.3 half-box was inside ~96% of space: `d_crystal == -0.05` everywhere, the
  camera started inside at 5 of 6 sampled times, every ray "hit" at t=0 (shaded 100%, t=0 100%), and `calcNormal` there is
  `normalize(0)` = NaN. **HEAD was a blank/NaN frame.** Step exhaustion itself was rare (<2%).
- Rodrigues hue (L176): VERIFIED — parallel term was k(k.v)/sqrt(3). No change at hue 0.
- Mouse shock at screen centre + negative subtraction (L206-209): VERIFIED. Mouse y inverted vs uv (L64 vs L128): VERIFIED.
  Extra finding: the mouse bend was centred on z=0, ~6 units behind every visible surface -> the held bend never showed.

**FIX done** (tagged `// FIX:`): centred repetition `p - c*floor(p/c+0.5)` (L120-129); no audio on cell size / time (L112-123);
crystal half-box 0.3 -> 0.1 (~5% fill, discrete nodes) (L178-181); 0.6 near-clip carve around the camera (L199-201);
hit = `t<30 && d<0.01` (L254-255); hueRotate with correct k(k.v), now also applied to links (L62-69, L306); image upright
uv.y (L231-232); bend centred on the cursor ray at t=3 with a safe normalize (L93-110); shock centred on cursor + clamped
>=0 (L326-333); tiny epsilon in calcNormal against zero gradients.

**Ideas as implemented**
1. Nucleation front — `nucleationFront` L133-143; SDF use L183-185 (melted crystals shrink to seed specks through the existing
   smooth blend); frost rim emission L318-320. Outgoing shells, wavelength 6, rate `0.04 + growth*0.2` (Growth keeps rotation).
2. Memory-crystal bit states — `hashCell`/`pcg` L71-82, `cellBit` L145-161; SDF contraction L187-189; dark smoky 0-bit + white
   write glint L292-294. Glitch sets write rate (0.4..3 Hz) and 0-probability (glitch*0.5); glitch 0 = all bits 1.
3. Light-piped links — `mapFull` returns d_crystal (L163-204); link glow `exp(-6*d_crystal) * frozen * bit` L310-313.

**Audio roles (not ideas):** bass -> gyroid scale + history weight; mids -> link pulse; treble -> node emission. `plasmaBuffer[0].xyz` only.

**A PACKING:** HDR linear RGB (pre-ACES) + semantic alpha, C read back exactly as HDR history (HEAD, consistent; no double tone-map).

**Refused/skipped:** nothing skipped. Kept verbatim: rot3D, sdGyroid, ifsCrystals, smooth blend + material id, node/link
colour scheme, fog, ripples, history blend, alpha, depth. JSON: params/updatedParams untouched; features += `upgraded-rgba`,
`mouse-driven` (pre-existing true tags kept).

**DEFAULT-LOOK SHIFT:** HEAD rendered nothing meaningful (NaN/flat t=0 frame). Now: a dense close-range labyrinth of magenta gyroid
sheets studded with cyan crystal nodes (numpy port: ~98-100% hit, nodes 27-69% of pixels, median hit t≈1-1.7), frost-white
front bands sweeping through, ~5-10% dark 0-bit cells at glitch 0.2, image upright. Numpy port in scratch
`gen-cybernetic-crystalline-neuro-lattice/port2.py` (hash is a stand-in, not PCG-exact). **Not GPU-verified.**

**Gates:** naga OK; wgsl_precommit_gate PASS; audit_dead_sliders PASS (1305 defs scanned, file not flagged; all 4 zoom_params read).

STATUS: final
