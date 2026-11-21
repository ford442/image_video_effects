# BRIEFS — fork C (sonnet/batch-50): gen-symbiotic-light-networks, gen_kimi_nebula

Written BEFORE any WGSL edit. Both files are 2nd-pass; every item already on their `Ideas:` line is KEEP VERBATIM. Real saved defaults for light-networks come from `x-meta.upgrade.params` (0.5, 0.4, 0.4, 0.3 — the JSON has no `params`), nebula from `params` (0.5 ×4).

HEAD reading (renders in `.../scratchpad/c2/`): light-networks at t≤6 s is a void with one green mouse-seed blob (every node/segment is gated by `age = clamp(t*0.1 − birthTime, 0, 1)`, birthTime up to 3 → network appears over ~10–40 s; mature picture at T0=40 is a sparse hub-and-spoke web, ~1.5 s/frame @256 with 5 forks loaded). Nebula = purple/blue gas, an ionized bubble at the pointer, ~350 stars drawn as binary one-cell white squares plus a boxy pink "halo" that is the *neighbour* cell's hash (so it sits one cell to the left of a star).

---

## gen-symbiotic-light-networks

```
SHADER: gen-symbiotic-light-networks
IDENTITY (one sentence): two bioluminescent species of node-and-tube networks (cyan-green and amber-pink) whose filaments carry travelling light pulses, thicken at hubs, leak a halo, swap hue where they overlap, and leave a luciferin afterglow.
KEEP VERBATIM: 4 sliders and roles (density -> numNodes, competition -> networkCompetition/symbiosis mix, light intensity, growth); node lattices nodeSp1/nodeSp2 and the hub degree (deg1/deg2, smoothstep(1,6,deg)); networkSegment geometry (capsule distance, taper, core width, halo Gaussian hw = 3.5 w); mycorrhizal hue exchange; afterglow memory `max(seedLight, prevMem*0.95)`; mouse seeding; age/birth gating; vignette; semantic alpha; ACES only on writeTexture.
ADD (2 native ideas):
  1. Directed shuttle streaming — pulses travel from the larger hub (source) toward the smaller end (sink) instead of always A->B, and run faster on thick (hub-hub) tubes (flux ~ radius). Equal-degree tubes keep HEAD's direction/speed. Physarum tubes do shuttle cytoplasm along a pressure gradient toward demand; here the "demand" end is the leaf that lights.
  2. Leak-fed halo (energy-conserving bloom, §12.2F) — along the flow coordinate the core transmits T = exp(-mu*s) (thin tubes leak more: mu falls with hub thickness) and the fraction removed from the core reappears in the evanescent halo: core *= (1 - L), halo *= (1 + k*L), k = 1.29 from the composite weights (core 0.8 * integral(core)=w vs halo 0.10 * integral(halo)=6.2 w). Tubes visibly dim away from their hub while the skirt brightens there, instead of a uniform core + uniform skirt.
FORBID on this file: springs / extraBuffer state, click ripples, IQ palettes, new species or a Physarum agent sim, a third pulse system, any new param, any change to HEAD's lattice / hub / age constants.
A PACKING: raw afterglow memory (rgb linear pre-ACES) + display alpha in A (HEAD packing, read back as colour memory via exact C load); ACES on writeTexture only. Unchanged.
```

Mechanism interrogation (§12.1):
- Tactic 1 (deepen the kernel): the kernel is "capsule distance -> smoothstep core + Gaussian halo, modulated by one sine pulse". Next-better approximation of light in a guide: the pulse has a direction and the guide loses light along it.
- Tactic 2 (physics one step further): a light guide (optical fibre / evanescent coupling) leaks power along its length (exponential attenuation, P(z)=P0 e^-az); a Physarum tube streams toward the high-demand end and flux scales with radius. HEAD has the halo (leakage) but not that the leakage is *paid for* by the core, and its pulses ignore the network's structure.
- Tactic 3 (promote an intermediate): `hubI`/`hubJ` are already computed per tube and used only for width; `proj/len` is computed and used only for taper/pulse phase. Promote both to a source/sink ordering and an attenuation coordinate.
- Tactic 6 (use the history it owns): C is the luciferin afterglow (`max(seedLight, prev*0.95)`). Left as is: nodes' memory is unaffected; no extra continuity needed, so no change.

Formula admission (§12.4): only one §12.2 row used — **energy-conserving bloom** (§12.2F; owned by this file). Family match: the file's identity is light transport with a leakage halo (it already has one). Operates on what exists: `core`/`halo` of networkSegment, `hubI/hubJ`, `proj/len`. Deletion test: remove it -> exactly HEAD's uniform tube; keep only it -> still a network of pulsing tubes. Idea 1 is not a table row (domain-native).

Cost plan: HEAD runs `sin` + 2 smoothstep + `exp` for every tube pair (up to 2×120 per pixel) although a pixel is nearly always far from every tube. Add an early-out `dist > 3*hw` (Gaussian < 1.3e-4, core support is `width` << that) BEFORE the pulse/taper work. That pays for the new `exp` + selects and should leave the file at or below HEAD cost. Time with `mr_ab.mjs` on a mature (T0=40) state.

Open call to report (not changed): the 10–40 s empty start (age gate) means a thumbnail/first-impression at t≈0 is a lone glow; left alone because "growth" is the file's identity (slider `growthAmt` already exists for it).

---

## gen_kimi_nebula (id gen-kimi-nebula)

```
SHADER: gen-kimi-nebula (public/shaders/gen_kimi_nebula.wgsl)
IDENTITY (one sentence): a purple/blue emission-and-dust nebula with an ionizing star (Stromgren bubble) at the pointer, supernova-shell click ripples, dark dust lanes, and a field of faint twinkling stars.
KEEP VERBATIM: 4 sliders + NebulaControls constants; fbm gas + domain warp + mids/treble layers; palette; Stromgren/[OIII]/[SII]/PDR/dust-extinction/rim/EGG blocks (everything on the Ideas line); click ripple shells; wind swirl; star cell grid `hash3(floor(p*100), time*0.01)` placement and Detail cutoff; the `nebulaDensity < 0.6` "stars hide behind dense gas" rule; twinkle formula; dust reddening of stars (`* extinction`); readTexture mix, bass chromatic offset, depth, alpha terms.
ADD (2 native ideas, both on the star field the file already draws):
  1. Blackbody star colour (§12.2F Rayleigh/blackbody) — each catalog star gets a photospheric temperature from a skewed distribution (many cool red/orange K-M dwarfs, few hot blue-white B stars, initial-mass-function style) -> Planckian colour (std `blackbody`, Helland fit, copied verbatim). The existing 1/lambda dust extinction then reddens it further, so field stars behind lanes go deep orange and stars in clear gas stay blue-white (HEAD: every star is pure white).
  2. Airy PSF + diffraction spikes (§12.2F Airy disc) — the stars are one-cell binary squares; render each as a telescope image: sub-cell jittered centre, Airy core ((2 J1(x)/x)^2, first dark ring at x=3.8317), a soft glare wing, and a 4-point diffraction cross on the brightest ~20% (spider-vane spikes, thin, fading with distance). Magnitude comes from the same hash excess over the Detail cutoff, so the Detail slider still means "fewer, crisper stars". This also replaces the boxy neighbour-cell halo with a symmetric wing (a HEAD artifact, said so in NOTES).
FORBID on this file: re-adding Stromgren / dust / rims / PDR / EGG material, springs, extraBuffer, IQ palettes, lens-flare ghost chains, any new param, changing star density or the Detail semantics, Rayleigh *scattering* reflection nebulae (that would be a third idea).
A PACKING: display RGBA (ACES) in A, same RGBA as writeTexture (HEAD); nothing reads C. Unchanged.
```

Mechanism interrogation (§12.1):
- Tactic 1: stars are `select(0,1, hash>cutoff && density<0.6)` binary cells: next approximation of a point source seen through a telescope is its PSF (Airy core + diffraction pattern), and of a star's light its Planck spectrum.
- Tactic 2: first-order side effects of a real nebula photograph's stars: spectral colour spread (blue O/B stars in the HII region, red field stars behind dust) and diffraction spikes from the secondary-mirror spider; the file already redden stars via extinction but starts from white.
- Tactic 3: the hash excess `(h - cutoff)/(1 - cutoff)` is computed implicitly (`starNoise`) and thrown away; promoted to a stellar magnitude. `starNoise` is also reused as the twinkle phase (unchanged).
- Tactic 6: the nebula reads no history (A is display RGBA, C unused) — none applicable.

Formula admission (§12.4): two rows, both owned by this file — **Rayleigh/blackbody** and **Airy disc** (§12.2F). Family match: a nebula image is an astronomical image; the rows are in the lighting/optical table and the file already has `1/lambda` extinction and "twinkling stars". Operates on what exists: the star cell hash, `extinction`, the density mask, the twinkle. Deletion tests: delete either -> still exactly this nebula; keep only either -> not a nebula (needs the gas). Not a costume: no new noun (stars already there).

Cost plan: +~19 `hash3` per pixel (row of 11 cells + column of 10 cells, centre shared) against HEAD's 24 `noise3` (~190 hash3) -> ~+8–10 %. All extra math (blackbody, Airy, spikes) sits inside `if (h > cutoff)` for 0.1–1 % of cells. Cap 1.3x.

---

## Revision (written after implementation, see NOTES-forkC.md)

The nebula card's star scan (25 hashed cells per pixel, spikes on the brightest ~20 % *of the same stars*) measured 3.4–3.8× HEAD on SwiftShader and was replaced: faint stars = the pixel's own HEAD hash cell (round jittered dot); spiked stars = a sparse 8×8-cell tile lattice (≈20 % of HEAD density, tied to the Detail cutoff) with Airy core + diffraction cross; one `blackbody()` call per pixel on the light-weighted mean temperature rank. The two ideas (blackbody colour; Airy PSF + spikes) and their §12.2 rows are unchanged. Light-networks card implemented as written (plus a symmetric degree loop and a distance early-out as cost offsets).
