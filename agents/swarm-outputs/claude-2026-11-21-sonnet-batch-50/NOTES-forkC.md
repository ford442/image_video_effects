# NOTES — fork C (sonnet/batch-50): gen-symbiotic-light-networks, gen_kimi_nebula

Baseline ("HEAD") = the worktree file as handed over (coordinator had already migrated light-networks to `_prelude.wgsl`; nebula already used it). Scratch copies + every render/timing in `/tmp/claude-0/-root-image-video-effects/12631154-16b4-44ad-a621-195684eec032/scratchpad/c2/`. VM = SwiftShader; no real-GPU visual QA is claimed.

Files touched: `public/shaders/gen-symbiotic-light-networks.wgsl`, `public/shaders/gen_kimi_nebula.wgsl`, and `description` only in `shader_definitions/generative/gen-symbiotic-light-networks.json` and `gen-kimi-nebula.json` (saved `params` / `x-meta.upgrade.params` / `features` untouched). Not committed.

## gen-symbiotic-light-networks

**KEEP VERBATIM (verified unchanged):** 4 sliders and roles (x density, y competition, z intensity, w growth; JSON has no `params`, saved defaults live in `x-meta.upgrade.params` 0.5/0.4/0.4/0.3); node lattices `nodeSp1/nodeSp2`; hub degree (`smoothstep(1,6,deg)`); tube geometry (capsule distance, taper, core width, halo Gaussian `hw = 3.5 w`); mycorrhizal hue exchange; afterglow `max(seedLight, prevMem*0.95)`; mouse seeding; age/birth gating; vignette; semantic alpha; ACES on writeTexture only.

**ADD (2 ideas, both in `networkSegment`, marked `// ── Idea 1/2`):**
1. **Directed shuttle streaming** (domain-native, no §12.2 row). Pulses run from the larger hub (source) to the smaller end (sink) instead of always A→B, and faster on thick tubes: `shuttle = 1 + 0.5*(hubA+hubB)`. Equal-degree ends keep HEAD's direction. *Measured* (single frames 0.15 s apart, phase of the 3-cycle pulse along a tube, audio 0): tube 3→4 (leaf→hub) HEAD −0.204 cycles, NEW +0.303 (sign flipped, expected |0.310|); tube 4→14 (hub .65→hub 1.0) HEAD −0.217, NEW +0.430 (flipped, expected |0.410|). Tube 4→7 HEAD reading is contaminated by a near-colinear tube (3→4 shares node 4); NEW keeps HEAD's sign there as designed.
2. **Leak-fed halo** (§12.2F energy-conserving bloom). Along the flow coordinate the core transmits `1 - L`, `L = 0.5(1 - exp(-mu*s))`, `mu = 1.6/(1 + 1.5(hubA+hubB))` (thick tubes leak less), and the halo gains `1 + 1.29 L` (1.29 = core weight 0.8·∫core(w) / halo weight 0.10·∫halo(6.2 w), first-order conservation of composited energy). Mean raw luma at T0=40, 480², HEAD 6.354 vs NEW 6.350 (energy conserved); 2.9 % of pixels differ by >2/255, localised on tube cores/pulses.

**Cost / trims that pay for it:** (a) early-out `dist > 3*hw` before pulse/taper/leak work (Gaussian < 1.3e-4; core support is `width`): not bit-identical, differences ≤ ~1e-5 of the halo; (b) the per-pixel node-degree loop tested every pair twice (`i→k` and `k→i`, 2×256 `length()`); now each pair once, credited to both ends — **pixel-identical** (max abs diff 0 vs the pre-trim NEW render). Interleaved A/B (`mr_ab.mjs`, T0=40, mature network, 256²–320², box at load 18–58): paired medians 0.87, 0.95, 0.96, 0.90, 0.96, 0.99 → **≈0.95× HEAD**.

**A packing:** unchanged — raw afterglow memory (rgb linear pre-ACES) + display alpha, read back as colour memory by an exact `textureLoad(dataTextureC)`; ACES on `writeTexture` only. No new state, no extraBuffer, no springs/ripples.

**Rescues:** none needed (no NaN, audio via `plasmaBuffer[0].xyz`, semantic alpha, exact C load). **Open call (NOT changed):** the birth clock `age = clamp(t*0.1 - birthTime, 0, 1)` with `birthTime` up to 3 s·10 makes the picture a lone green mouse glow for the first ~10–30 s after load (full network ~40 s); a thumbnail taken in the first seconds sees almost nothing. Left alone because growth is this file's identity; speeding the clock (`t*0.1` → `t*0.3`) is a one-token change if the user wants it.

**Checks:** NaN 0 at defaults and at sliders 1,1,1,1 + loud audio + pointer, and at sliders 0,0,0,0; precommit gate, naga-wasm (2/2 with the nebula), dead-slider (JSON has no `params`, grepped by hand: `zoom_params.x/y/z/w` all read at lines 163–166), `audit_extrabuffer` PASS.

## gen_kimi_nebula (id gen-kimi-nebula)

**KEEP VERBATIM (verified unchanged):** 4 sliders + `NebulaControls`; fbm gas, domain warp, mids/treble layers; palette; the whole Stromgren / [OIII] / [SII] / PDR / dust-extinction / rim / EGG block (every item on the existing `Ideas:` line); click-ripple shells; wind swirl; the Detail cutoff semantics (higher = fewer, crisper stars); stars hide behind dense gas; twinkle (same `sin(time*5 + h*10 + treble*3)`); dust reddening of stars via `* extinction`; readTexture mix, bass chromatic offset, depth, alpha terms.

**ADD (2 ideas on the star field, marked `// ── Idea 3/4`; numbered after the file's existing Ideas 1/2):**
3. **Blackbody star colour** (§12.2F Rayleigh/blackbody). Each star carries a temperature rank (skewed: `2800 + 9500*rank^1.8` K — many cool K/M dwarfs, few hot blue-white B stars); colour = std `blackbody()` (copied body-identical with `srgbToLinear`) of the light-weighted mean rank, mixed 0.9 toward it from white, then multiplied by the file's existing dust `extinction` so field stars behind lanes go deep orange (HEAD: every star pure white).
4. **Airy-disc PSF + diffraction spikes** (§12.2F Airy disc). Bright stars: `airy(r*4.26)` core (first dark ring at 0.9 cell; J1 as a 6-term Maclaurin series, valid to x≈4.3, faded beyond), a soft glare wing, and a thin 4-point diffraction cross (≥0.8 px wide, fading over 2.5–5.5 cells). Faint stars: round compact dot with jittered centre instead of HEAD's flat one-cell square. HEAD's boxy "halo" (the *neighbour* cell's hash, so it sat one cell left of every star) is gone — replaced by the symmetric wing; this is a HEAD artifact fix, not a new look.

**Design revision after the card (cost):** the card promised "spikes on the brightest ~20 % of the same hashed stars" via a 25-cell row/column scan. That measured **3.4–3.8× HEAD** on SwiftShader: variants (V5) 25 bare `hash3` = +28 %; heavy math (`blackbody` ×25, `sin`, `exp`) runs even for the never-taken branch (SwiftShader does not skip `if`/early-return bodies), so cost scaled linearly with cells scanned (~0.11× HEAD per cell). Final structure: per pixel ONE faint-star call (this pixel's own HEAD hash cell → HEAD's hash and cutoff, so Detail is unchanged) + FIVE bright-star calls on a sparse 8×8-cell tile lattice (own + 4 axis neighbours; arms lie on the axes so diagonals never matter) whose density `pB = 12.8*(1 - starCutoff)` is ≈20 % of HEAD's star density and moves with the Detail slider; and ONE `blackbody()` call per pixel on the light-weighted mean rank (a single call is ~2.5 % of HEAD). Consequence to say loudly: the bright (spiked) stars are now a *separate sparse population on top of* HEAD's star cells (total star count ≈ HEAD × 1.2), not a subset of them; their positions are stable (no time term in the tile hash) while faint stars keep HEAD's `time*0.01` hash.

**Cost:** interleaved A/B (SRC=img, 256²–384², box load 18–58): paired medians 0.59, 1.08, 0.97, 1.16, 1.11, 1.17, p25 up to 1.25 → **≈1.1× HEAD** (cap 1.3×; noisy, coordinator to re-time on a quiet box).

**Diff vs HEAD (800², defaults, mouse 0.3,0.6 up, audio .3/.2/.1):** 2.42 % of pixels differ by >3/255, 1.16 % by >20/255 — all on stars; gas, bubble, lanes, shells untouched. meanL 0.555 (HEAD 0.56), meanA 0.373 (HEAD 0.374).

**A packing:** unchanged — ACES display RGBA in A, same RGBA as `writeTexture`; nothing reads C. ACES input is `max(…, 0)` (star light ≥ 0 by construction: Airy factor, kernels, arms are all ≥ 0).

**Rescues:** none beyond the boxy-halo artifact above; no `pow` of a possibly negative base (`pow(rank, 1.8)` with rank clamped to [0,1], `pow(Q,1/3)` etc. unchanged and positive), no dead sliders, audio via `plasmaBuffer[0].xyz`.

**Checks:** NaN 0 at defaults, Detail 0 and 1 with audio and held pointer, Detail 1 / Scale 1, and with two click ripples (`mr_c_abs.mjs`, absolute start times) on an image source; precommit gate, naga-wasm, dead-slider (1 def, 0 new dead), `audit_extrabuffer` PASS.

## For the coordinator (§12.4 de-dup / review)
- §12.2 rows used by this fork: energy-conserving bloom (light-networks only), Rayleigh/blackbody + Airy disc (nebula only). Direction/shuttle idea is not a table row. No spring, ripple, IQ palette, extraBuffer or new param added to either file.
- `Upgraded:` now `2026-09-27, 2026-11-21` on both; `Ideas:` lines extended on both; `Features:` unchanged.
- Gotcha worth a memory line: **on SwiftShader per-pixel loops over star/particle cells cost linearly even when the branch is never taken — gate by a cheap pass and evaluate transcendental-heavy math once per pixel.** Also `mr.mjs` readback needs sizes whose `size*16` is a multiple of 256 (500 fails, 512 works).
