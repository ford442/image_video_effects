# sonnet/batch-22 — fork C briefs (written before any edit to the real WGSL)

Shaders: gen-celestial-glass-tornado (2nd pass), gen-vitreous-chrono-chandelier (2nd pass).
HEAD diagnostics were run on scratch copies only (`scratchpad/forkC/`), 192/288/576 px, default params (tornado 1,0.5,0.2,1; chandelier has NO
top-level `params`, so the app feeds 0.5 x4), idle cursor, audio 0.4,0.3,0.2.

Row budget used: Snell vector refraction (F) + Step-count AO (E) on the tornado; Soft inverse-square (F) on the chandelier. No Cauchy added
(the tornado already has it). Nothing else from §12.2.

---

## 1. SHADER: gen-vitreous-chrono-chandelier

IDENTITY: an endless lattice of glass chimes (rounded-box crystals on torus mounts) swinging as damped pendulums over an abyssal floor of
caustic web, shaded by three-channel refraction, bass-reactive.

KEEP VERBATIM: 4 slider roles (x Shatter Threshold, y Chime Density, z Refraction Index -> iorR/G/B offset, w Transmission -> colour gain);
`round(q/spacing)` cell lattice + `hash3` per-cell len/damping/theta0; `pendulumAngle` physics (g = 9.81, omega = sqrt(g/len)); cluster
phase-lock term; crystal rounded box + cleavage-plane cut (`max(crystal, cleavage)`); mount torus; link box; tick-mark disc; mouse repel
(only audible with bass); `refractRay` x3 + `causticPattern`; floor caustic web; temporal C mix, chromatic aberration, ACES; A = display RGBA.

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): the crystal shading is a caustic *pattern lookup* at `hitP + refracted*2`; it has no light, so the facets
  have no form (HEAD render: flat tiled brown boxes). A chandelier is a lamp seen through glass.
- Tactic 2 (physics one step further): a real chime that is struck rings and decays, and a chandelier crystal that breaks leaves a shard that
  falls along its cleavage plane. `pendulumAngle` decays `exp(-damping*t)` forever and is never re-excited.
- Tactic 3 (promote an intermediate): `swingX/swingZ/angle` per cell are computed in `sceneSDF` and thrown away — the floor caustic could use
  them; `cleavage` plane normal is already a vec3; `shatterThreshold` is read into a local and never used (dead slider).
- Tactic 6 (history): C is read as display colour history (5% mix). No extra continuity idea; packing stays.

HEAD DIAGNOSIS (measured on scratch copies)
- Upside-down: `rd = normalize(vec3(uv, 1))` with `uv.y` growing downward on screen, but the scene is y-up (chimes hang below the camera at
  y=3, floor at y=-2.6). HEAD shows the hanging forest in the TOP half, the floor lattice glued above it, and a black bottom half.
- Chime spacing: `chimeDensity = zoom_params.y` is used directly as the cell size. JSON has no `params`, so the app feeds 0.5 -> 0.5-unit cells
  holding 1-3 unit pendulums: every chime is clipped by its neighbours' cells (noise soup). x-meta documents a default of 4 (never read).
- Floor web is added for every pixel with `rd.y < -0.02`, including pixels where a crystal was hit in front of the floor (crystals carry the
  floor grid).
- The swing dies: amplitude `theta0*exp(-damping*t)` with damping 0.1-0.3 is ~0.05 of the start after t = 30 (60 s of wall time) and nothing
  re-excites it, so the chandelier freezes for the rest of the session.

RESCUES (documented as rescues, not ideas; default look changes on purpose)
- R1 upside-down camera: `rd.y = -uv.y`; camera re-framed (ro (2.0, 1.6, -6.5), 0.30 rad pitch down; three framings rendered, this one keeps mounts, crystals and floor foci in one frame) so the chimes + mounts hang in the
  upper/middle of the frame and the floor lattice sits below; mouse repel point now follows the camera frame (cursor up = up).
- R2 chime spacing: `spacing = mix(7, 1, zoom_params.y)` — slider stays live, reads as *density* (HEAD's direction made "density" grow the
  spacing), default 0.5 -> 4.0 (the x-meta intent). Saved params untouched (none exist).
- R3 floor occlusion: the floor web is only drawn where the floor is the first surface (`!hit || tf < hitT`) and fades with distance
  (`exp(-tf*0.045)`) so the far lattice does not alias.
- R4 swing never dies: each chime is re-struck every 6 half-periods exactly at its lowest point (cos = 0 -> position continuous, only the
  velocity is kicked); the HEAD damping constants and `theta0` are unchanged.

ADD (3 ideas)
1. Pendulum-projected floor foci (tactic 3; extends "floor-bound caustic web lattice") — every chime focuses a bright disc + ring on the floor
   under it, and the focus sways with that chime's own swing (same `chimeState` the SDF uses). The web lattice now has a pendulum-synchronous
   bright spot per chime instead of an independent texture. Same noun: caustic under a glass pendant. Per-channel radius (0.88/0.94/1.0) so the
   rim disperses.
2. Cleavage shards on bass (wires the dead Shatter Threshold slider; extends "crystal cleavage planes") — bass above the slider slides the
   cut-off half of each crystal out along the cleavage normal and it re-forms when bass falls. Zero at silence, so the idle look is not
   touched by this idea. Tactic 2 (physical side-effect of cleavage).
3. Hub lamp, soft inverse-square (§12.2F) — each mount holds a warm lamp (r0 = 0.8); crystals get Lambert + facet glint from `I r0^2/(d^2+r0^2)`;
   bass pulses it. Consumes `hitP`, `n`, `rd`, the cell's local coordinates. A chandelier is a lamp seen through glass; the flat cleavage faces
   now catch it.

FORMULA ADMISSION: Soft inverse-square is in the lighting/optical table and this shader is a glass lighting piece; it consumes `hitP`/`n` and
the cell centre; deleting it leaves HEAD's caustic-pattern crystals. Ideas 1/2 are not §12.2 rows (tactic 3 / tactic 2); both use quantities
the file already computed (swing, cleavage normal, shatterThreshold slider).
FORBID: new params/bindings/state, springs, ripple fronts, IQ palettes, hologram/scanline costume, anything touching the pendulum constants,
cell lattice, refractRay or the ACES/temporal chain.
A PACKING: ACES display RGBA (unchanged; C read as colour history). No state texels needed.

---

## 2. SHADER: gen-celestial-glass-tornado (2nd pass)

IDENTITY: a twisting glass funnel with KIFS crystal debris, three-tap prismatic facet shading, a starfield and blue/teal plasma overlays,
orbited by the cursor.

KEEP VERBATIM: 4 params + roles (vortex_twist -> twist per unit y; debris_density -> KIFS fold offset; chromatic_split -> channel offset;
audio_reactivity -> audio twist / glow / arc gain); tornado radius law `1 + 0.2y + 0.2 sin(4y+t)`; 4-fold KIFS debris sphere; 3-tap SDF
channel ramp; fresnel + thin-film + glint; helical arcs, meteors, confinement rings, accretion dust, click glass rings; C trail mix 0.025;
`acesToneMap(col*1.1)`; depth from the hit; A = display RGBA.

MECHANISM INTERROGATION
- Tactic 1: the tornado is `length(q.xz) - r(y)` evaluated after `q.xz = rot(y*twist + t)*q.xz` — a rotation of a round cross-section. It is
  rotation-invariant, so Vortex Twist and the animation `t` are *invisible* in the funnel itself (only the debris, which uses untwisted `p`,
  moves). The funnel never looks like it spins.
- Tactic 2: glass in front of a starfield shows the starfield bent by the wall; HEAD paints the funnel as an opaque ramp.
- Tactic 3: `q` (twisted frame), the hit surface id (funnel vs debris), `n` and `map()` itself are all computed and used only once.
- Tactic 6: C is display colour history (2.5%). The spring is the only history the file owns, and it is dead (below).

HEAD DIAGNOSIS (measured)
- Upside-down: the funnel radius grows with +y (wide top) but HEAD draws it narrow-top / wide-bottom; the "bottom" accretion disk
  (`nuv.y + 0.35`) lands in the top third. `nuv.y` grows downward while `rd.y` is world-up. (HEAD default meanL 0.198, stdL 0.257.)
- Per-channel ramp has a pole: `1/(1 + d*50)` with the blue tap at `p - n*split` (inside the glass, d ~ -0.03) is `1/(1-1.5) = -2`, so B < 0
  and the body is flat saturated yellow-green; `col = rgb * glow` with glow ~ 5 on the surface saturates the rest. The prismatic/glass look is
  invisible.
- Spring dead: state in `extraBuffer[133..138]`, which the app re-zeroes every frame; `extraBuffer[137] < 0.5` is therefore always true and
  the "spring" is the raw cursor.

RESCUES
- R1 upside-down: `nuv.y` flipped (y-up like `rd`); mouse pull target uses `(0.5 - mouse.y)` so cursor up = up. Camera sweep math kept (cursor
  up -> look up).
- R2 dead spring: moved to A texels (0,0) = pos+vel, (1,0) = (fract(time), 0, 0, 0.7371 sentinel); C reads masked on those two texels; every
  thread integrates the same dt (`clamp(fract(time - st1.x), 0.001, 0.05)`); critically damped omega 8 as HEAD. Idle cursor gives goal
  (0.5, 0.5) = zero sweep, so the idle default is unchanged by this rescue.
- R3 ramp pole + glow saturation: channel term uses `clamp(1/(1 + max(d,-0.01)*50), 0, 1)`; surface glow compressed `1 - exp(-0.25 glow)`
  (alpha rides the compressed value, so the glass is translucent instead of 1.0). Scratch render: meanL 0.198 -> ~0.17, B channel alive,
  facets / thin-film now visible.

ADD (3 ideas)
1. Helical glass flutes (tactic 3 + 7; consumes the twisted frame `q`) — `r -= 0.07 * cos(5 theta)` via Chebyshev `T5(q.x/r)` (no atan2) on the
   already-twisted coordinates: the ribs follow Vortex Twist (pitch) and `t` (rotation), so the slider and the spin finally read on the funnel;
   bass swells them 60%.
2. Refracted sky through the wall (§12.2F Snell vector refraction) — `refract(rd, n, 1/ior_c)` per channel (ior offsets ride the existing
   Chromatic Split slider) looks the starfield up *through* the glass; stars inside the funnel bend with the wall. The background stars move to
   the same direction-cell function so the inside and outside sky match.
3. Step-count AO (§12.2E) on the hit — 5 `map()` taps along `n` darken crevices where KIFS debris crowds the wall; post-hit only.

FORMULA ADMISSION: Snell is a lighting/optical row and a glass tornado is glass; consumes `n`, `rd`, the three channel offsets already
computed; deletion leaves the opaque ramp. Step-count AO consumes `map()` and `n` (generative/SDF row). Flutes are tactic-derived (no row).
FORBID: new springs/ripples (the existing spring is merely repaired), IQ palette stamp, replacing the funnel with another creature, new
params, touching the Cauchy 3-tap ramp, arcs/meteors/rings/dust (kept as HEAD).
A PACKING: display RGBA (RGB = ACES, A = glow opacity) as HEAD; texels (0,0) and (1,0) carry the spring state (C read masked there).
