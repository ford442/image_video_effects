SHADER: gen-superfluid-quantum-foam
IDENTITY (one sentence): a raymarched lattice of boiling iridescent foam bubbles, warped by a flow field and a
  cursor vortex, with magenta near-miss radiation glow, cyan click-cavitation shells and a faint temporal smear.
KEEP VERBATIM: domain-repeated sphere lattice (sp = 3/env, radius (0.6+h*0.6)*env + boil, boil = hash*sin(t*3+bass*10)*P1);
  vortex pull + xz twist inside Vortex Radius (P2); glow accumulator `(0.5-d)*0.08*P3` (P3); Current Speed time scale
  (P4); per-channel ndotv chromatic iridescence; fog; click-cavitation shell loop (age = time - ripple.z, no .w);
  magenta flash; temporal mix of C; ACES; depth write; A packing. All four saved params byte-exact.
  HEAD spring in extraBuffer[133..138] is left as-is (it never persists — buffer is re-zeroed each frame — so the
  cursor is effectively the raw mouse; noted, not "fixed" into new state).
ADD (3 native ideas, each fusing subsystems already in the file):
  1. Coalescing bubble necks — each sample now evaluates the 8 nearest lattice bubbles and smooth-mins them, so when
     the existing boil (P1) / warp / bass swell pushes neighbours together they fuse through a Plateau-style neck
     instead of interpenetrating. The description promises bubbles that "merge"; HEAD only ever saw one cell.
     (lattice x boil)
  2. Film-drainage black-film pop — every bubble gets a stateless life phase (speed tied to Current Speed). Its film
     drains as it ages: the iridescence gets a thickness-driven interference-order shift (thicker at the bottom by
     gravity drainage), goes to the dark "black film" just before rupture, then the bubble pops (radius collapses)
     and throws a short warm expanding burst shell into the glow accumulator — the description's "burst ... releasing
     flashes". (boil lifecycle x iridescence x radiation glow)
  3. Kelvin-wave vortex filament — the cursor vortex becomes a superfluid quantized vortex line: a vertical hollow
     core thread through the vortex centre carrying a travelling helical Kelvin wave, rendered analytically
     (ray-line closest approach, occluded by foam hits) as a dark core with a cyan sheath, plus an irrotational 1/r
     swirl of the bubbles around that moving core. Strength/extent from Vortex Radius (P2 = 0 turns it off, like HEAD).
     (vortex x superfluid flow)
FORBID on this file: virtual pair flashes, Born-rule detection hits, Worley F2-F1 membranes (gen-quantum-foam-alpha);
  Rosensweig spikes / |psi|^2 filaments (entangled-ferrofluid); geode collapse flash / sonoluminescence strata
  (sibling in this batch); new spring cursor, new ripple overlay, IQ palette stamp, extra particle system.
A PACKING: ACES display RGBA, premultiplied (col*alpha, alpha) — unchanged from HEAD; C read back as colour history.

SILENT BUGS FIXED (read path):
  a. `curlNoise` took finite differences of a white hash (hash33), so the "current" was a discontinuous random warp of
     up to ~6 world units (numpy port: jumps of 3-6 units every ~0.5 units of space) that shattered the spheres into
     shards; its z component was also not a curl (dPsi_y/dy - dPsi_y/dx). Now: correct central-difference curl of a
     smooth two-octave trig vector potential, same call site and 0.3*env scale, displacement ~0.3-0.9 units.
  b. Cell ID used floor(pos/sp) while the repetition used round(pos/sp), so every bubble was split into 8 octants with
     different radii. Now centres and IDs both come from the same lattice index.
  c. Camera-inside-bubble: ro=(0,0,-8) sits 1 unit from lattice centre (0,0,-9); once the warp is coherent the camera
     can be inside a bubble for whole seconds, and HEAD's `d < 0.001` test "hit" at dist 0 -> blank frame. Now the
     march uses the sign of map(ro) so inside-start rays reach the inner film (normal flipped to match).
KEPT-AS-IS NOTE: HEAD spring writes extraBuffer[133..138] at (0,0); that range is re-zeroed each frame so it is inert
  (cursor == raw mouse). Left untouched per contract.
