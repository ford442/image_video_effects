# NOTES — fork E (chromatic-reaction-diffusion-rgba, gen-cymatic-hex-mandala) — batch-39, 2026-11-15

Worktree `/root/iv-sonnet-batch-39`. No git operations. Edited only: `public/shaders/chromatic-reaction-diffusion-rgba.wgsl`, `public/shaders/gen-cymatic-hex-mandala.wgsl`, `shader_definitions/simulation/chromatic-reaction-diffusion-rgba.json`, `shader_definitions/generative/gen-cymatic-hex-mandala.json` (+ this file).
Evidence: SwiftShader WebGPU via `agents/mr.mjs` (saved-default sliders passed explicitly: RD `0.5,0.5,0.3,0.3`, hex `0.5,0.45,0.5,0.35`, `SRC=img`), numpy ports in the scratchpad (`forkE/rd_model.py`, `rd_eval.py`, `ramp.py`, `search.py`). "pct" = % of pixels whose max-channel |Δ| > 0.02 against the same file with that idea's term zeroed (scratch copies `rd_off3/off4.wgsl`, `hex_off1/off2.wgsl`). **No real-GPU claim of any kind.**

---------------------------------------------------------------------------------------------------------------------------------

## 1. chromatic-reaction-diffusion-rgba  (card 9)

**KEEP VERBATIM held:** 4-species state and reaction terms, feed/kill/separation/coupling mappings (x,y,z,w order), overlap quench, photo chroma seed, hover spiral, click fronts, pigment display + fringe, alpha, depth write, ACES on `writeTexture` only. Saved `params` byte-exact (only `description` text changed, +67 chars). **A packing: raw 4-species state, unchanged, no ACES on A.** Bindings already from the prelude (migrated header-only by the coordinator, no `Upgraded:` bump for that).

### Rescue 1 — numerical instability: CONFIRMED (numpy + SwiftShader)
HEAD: explicit Euler (`dt = 0.8`) with the UNNORMALISED 5-point Laplacian (checkerboard eigenvalue −8) and `Du = 0.82 (+sep·0.08)`, `Du_cool = 0.76` → `D·dt ≈ 0.66` vs the 2-D limit `D·dt ≤ 0.25`.
- numpy port, 192², 600 frames: both U layers are a saturated 0/1 checkerboard (mean 0.50, **std 0.50**, mean |∇²U| 3.74); warm V is dead (mean 0.017–0.034, std 0.08); cool V creeps up slowly. With the Laplacian scaled to a stable factor (0.3 or 0.25): U mean 0.48–0.54, std 0.17, V alive (0.17 / 0.11), checkerboard component 0.000.
- SwiftShader, 192², 640 frames (also A16): cool V is a **pixel-staircase labyrinth** of 1-px blocks, warm V only survives as the photo-seed dots; `meanL 0.343 stdL 0.242` is noise, not structure. Looked at the PNG (`forkE/rd_head_640.png`) — blocky, pixel-grid aligned. 300 frames idle: meanL 0.222 / stdL 0.218.
- Fix (smallest change): the card's stencil. The isotropic 9-point Laplacian (0.2 edges, 0.05 corners, −1 centre) is ≈ **0.3·∇²** (checkerboard eigenvalue −1.6), i.e. exactly the stable scale, so it is rescue and Idea 3 in one line. D constants are HEAD's. Pattern scale therefore changed only in that the sim now has a pattern: effective Du ≈ 0.25, Dv ≈ 0.09 (a Pearson-like ratio). **Pre-existing presets will look different because HEAD's sim never produced a coherent frame** (params and ranges unchanged).
- Alive across slider corners (numpy 128², 500 frames, feed/kill ∈ {0,.5,1}, sep/coupling ∈ {0,1}): mean V 0.03–0.28, no checkerboard, no NaN. Only feed 0 / kill 1 goes near-extinct (cool V 0.005) — the Gray-Scott extinction corner, expected.

### Idea 3 — isotropic 9-point Laplacian (§12.2D) — `chromatic-reaction-diffusion-rgba.wgsl` L32–40
Same stencil weights as the §12.2D row, 4 extra `loadState` (diagonals). Measured vs `0.3·(5-point)` (the rescue alone):

| frames / size | pct | mean \|Δ\| |
|---|---|---|
| 60 @ 192 | 26.0 % | 0.020 |
| 640 @ 192 | 13.4 % | 0.011 |
| 120 @ 576 | 15.5 % | 0.012 |
| held cursor 60 @ 192 (earlier variant) | 46.7 % (not re-run for the final constants) | — |

Honest caveat: a stencil change decorrelates a chaotic pattern, so the pixel Δ overstates "visible improvement". The direct isotropy measure (numpy, 500 frames, gradient-orientation 4θ moment, 0 = isotropic, + = grid-aligned): warm V 0.049 → **0.036**, cool V 0.053 → **0.038**, U 0.059 → 0.045 (≈ −25 %). The photo seeding and the 37×29 seed grid add their own axis bias, so it does not reach 0.

### Idea 4 — photo-luma-scaled diffusion length (native, tactic 4) — L41–51
`dLen = mix(0.4, 1.3, photoLuma)` multiplies both diffusivities of each species pair (Du:Dv ratio, hence the pattern regime, unchanged). Rides the existing `src` fetch (moved above the reaction; the later fetch was removed).
- Cap: the reaction Jacobian adds to the Euler amplification, so the pure-diffusion limit (`m ≤ 1.84`) is not the real limit. numpy worst case (feed 1, kill 0, separation 1, white photo, coupling ×1.7) first goes unstable at **~1.6**; first draft `mix(0.5,1.6)` was over that. Shipped cap 1.3 (≈ 18 % margin). Stress set (white/black photo × 6 slider corners × 700 frames) clean for 0.5–1.25, 0.4–1.3, 0.4–1.4, 0.4–1.5.
- Wavelength gradient, numpy, grey luma ramp 0.1→0.9 with NO chroma seeds (so only D varies): spatial frequency dark → bright **0.153 → 0.112 (1.36×)**; flat D: 0.119 everywhere (1.00×). Less than the √D prediction (1.5×), as spots saturate.
- SwiftShader vs flat D: 50.5 % (60 f @192), 47.1 % (640 f @192), 29.5 % (120 f @576); mean |Δ| 0.046 / 0.041 / 0.032.

### Floor / looks
- Slider sweep 0→1 (300 frames, 192²): feed 98.0 %, kill 98.6 %, chromaticSep 47.8 %, crossCouple 99.8 % of pixels change. All live. `audit:dead-sliders` 0 new.
- Default look HEAD → new (192², 300 f): idle meanL/stdL 0.222/0.218 → **0.363/0.122**; held 0.312/0.258 → 0.379/0.141; audio (0.8,0.5,0.9) 0.149/0.168 → 0.367/0.117. HEAD's higher stdL is pixel noise. 60-frame @256 (coordinator table): 0.084/0.053 → ~0.39/0.18.
- A16 (real rgba16float A) 300 f: meanL 0.363 / stdL 0.122 = the A32 run. `nan` 0 everywhere.
- **Open / owner's call:** with U stable at ≈1 the pigment formula (untouched, "KEEP") adds `U_warm·(1.25,.10,.02) + U_cool·(.02,.28,1.55)` everywhere, so the substrate reads as a lilac wash with warm/cool V structures on it and the photo shows through at ~12 % (`mix(src, pigment, 0.68 + coupling·0.65)`). HEAD had the same mix factor but a speckled 0/1 U. Dimming the U terms would be a display change the card forbade; not done.
- Idea comments are numbered 3 and 4 (HEAD's overlap quench / chroma seed keep their "Idea 1 / 2" comments).
- §12.2 rows: isotropic 9-point Laplacian (D). Idea 4 is native.
- Gates: `wgsl_precommit_gate` pass, `verify-naga-wasm --files` valid, `audit:dead-sliders` 0 new, `audit:extrabuffer` pass (no extraBuffer use).

---------------------------------------------------------------------------------------------------------------------------------

## 2. gen-cymatic-hex-mandala  (card 10)

**KEEP VERBATIM held:** radial wave `sin(dist·freq·TAU − t·(1.2+p3·1.5))` and its audio mapping (mids → freq, bass → amplitude/decay), `exp(−dist·(1.2−bass·0.3))` envelope, edge tiles + treble node sparks (same hash), angular hue palette, trail blend `mix(prev·(0.9−p4·0.1), col, 0.28+p4·0.18)`, depth attenuation, `hue_preserve_clamp`, ACES, IGN dither, 4 saved params and roles (JSON `params` byte-exact; `description` +77 chars). **A packing: A.rgb = pre-ACES colour trail (unchanged), A.a = Chladni sand density** (HEAD stored an unused copy of `bassEnv`). Nothing reads A.a except this file's own sand.

### Rescue 1 — the "hex" lattice: CONFIRMED by render
HEAD `hexCoords` split each axial parallelogram into two triangles (`step(f.y, f.x)`) and took the edge in the skewed frame (its axial y coefficient 2/√3 where flat-top hexes need √3/3). The HEAD render (`forkE/hpng_aud192_head.png`) is a skewed rectangle/triangle checker, not hexagons. Replaced by the standard two-interleaved-lattice nearest-centre form, floor-based fold (WGSL `%` is truncated), `z` = hex distance 0 at centre → 0.5 at the edge; thresholds `0.38/0.42` kept, written as `1 − smoothstep(0.38, 0.42, z)` (HEAD's `smoothstep(0.42, 0.38, …)` had low > high, undefined in WGSL). `hexCoords(ruv·scale·0.6)` keeps HEAD's cell count (~5 across at the default). `edge` is still the lit cell INTERIOR (that is what HEAD drew), grout is the 0.42–0.5 band.

### Rescue 2 — filtering sampler on rgba32float C: CONFIRMED by reading
`textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0)` → exact `textureLoad(dataTextureC, pixel, 0)`. Output alpha: HEAD writes `col·alpha` with alpha floored at 0.1. **Not changed**: eight other `gen-*` files write the same premultiplied convention (`col * alpha, alpha`), the canvas is `alphaMode: 'opaque'`, and alpha is semantic (density). This is why idle is still dark (see looks).

### Idea 1 — hex-symmetric modal wave (native; Bessel) — L85–99
`J_m(x) ≈ √(2/πx)·cos(x − mπ/2 − π/4 + (4m²−1)/(8x))` with m = 6 (the hex symmetry); the amplitude falloff is the file's own `exp(−dist)` envelope, so only the phase is kept; the Hankel term `17.875/kr` is what makes the m=6 nodal circles scallop against the m=0 ones (pure asymptotic J0 and J6 would be the same circles). Core fade `smoothstep(3,10,kr)`. `wave = ampl·(radialWave + 0.7·modal6·cos(0.9t))`: the radial rings are untouched; the petals pulse. The §12.2 table has no Bessel row; the formula is from `docs/WOLFRAM_SHADER_DATA.md`.
Measured vs `modal6 = 0` (new vs off1, sand still on in both):

| case | 192² | 576² |
|---|---|---|
| idle (90 f) | 15.9 % (mean 0.0156) | 15.8 % (0.0156) |
| held cursor | 15.2 % (0.0152) | — |
| audio 0.8,0.5,0.9 | 51.3 % (0.0432) | 51.4 % (0.0431) |

### Idea 2 — Chladni sand (native, tactic 6) — L115–125
`sand` lives in A.a: `prev.a·(0.90+0.08·p4)·(1 − 0.25·antinode) + nodal·0.10·(0.7+0.8·bass)`, nodal = `1 − smoothstep(0, 0.22, |standing|)` with `standing = cos(phase0) + 0.9·modal6` (the plate's static m=0 + m=6 figure; its zero set moves slowly because the petals rotate at 0.12 rad/s and when mids move `freq`). Shown as warm-white grains (`·0.8`, added after the colour-trail store so the trail is not double-counted) and adds `0.3·sand` to the alpha density. `trail_persistence` keeps its colour-trail role and also sets how long grains stay. First frame C = 0 → sand builds in ~10–15 frames.
Measured vs `sand = 0` (new vs off2):

| case | 192² | 576² |
|---|---|---|
| idle | 10.4 % (mean 0.0086) | 10.5 % (0.0086) |
| held cursor | 10.3 % (0.0085) | — |
| audio | 13.3 % (0.0202) | 13.3 % (0.0202) |

### Floor / looks
- Slider sweep 0→1 (idle, 90 f, 192²): hex_scale 41.1 %, wave_frequency 27.2 %, ring_intensity 18.8 %, trail_persistence 15.3 % of pixels change. All live. `audit:dead-sliders` 0 new.
- Default look HEAD → new (meanL/stdL; identical at 192² and 576²): idle **0.015/0.013 → 0.028/0.027**; audio 0.107/0.094 → **0.167/0.115**. Looked at the PNGs: true hexagons, six-lobed scalloped rings, fine grain on the nodal lines (`forkE/hpng_*_new.png`).
- **Still dark at silence** (meanL 0.028): the premultiplied-alpha convention and the 0.1 alpha floor were left alone (see Rescue 2). The new ideas are visible at idle (sand 10 %, modal 16 %) but dim. Raising idle brightness is a catalog-wide convention question, not this file's.
- A16 (rgba16float A) 200 f with audio: meanL 0.167 / stdL 0.116 = the A32 run. `nan` 0.
- The wider ring amplitude (`radialWave + 0.7·modal6`, up to 1.7× where petals add) makes audio frames ~55 % brighter on average.
- §12.2 rows: none from the table (modal wave is native cymatics; Bessel from the Wolfram doc). No row shared with another file.
- Gates: `wgsl_precommit_gate` pass, `verify-naga-wasm --files` valid, `audit:dead-sliders` 0 new, `audit:extrabuffer` pass.

---------------------------------------------------------------------------------------------------------------------------------

## Cost (indicative — NOT reliable)
Machine load was 18–60 for the whole run (sibling forks). Min-of-drained-frames, interleaved, 10 rounds @384², RD: HEAD min per round ranged 7.4–65 ms and NEW 20.5–86.6 ms; median of per-round ratios **1.16**, spread 0.57–7.26, ratio of overall minima 2.77 (driven by one 7.4 ms HEAD outlier). Hex @384², 10 rounds: idle median ratio **1.16** (0.89–2.71; min-of-mins 2.23), audio median **0.96** (0.62–2.83; min-of-mins 1.39). Per-round HEAD minima for the same shader spread 6–23 ms. That is noise, not a measurement; the coordinator re-times alone. Static accounting: RD 5 → 9 `loadState` (+4) and one `mix`, same single photo fetch; hex: same one depth load, the filtered C sample became one exact load, + ~3 `cos` and 1 `smoothstep` per pixel.

## Not verified
Real-GPU look (everything above is SwiftShader / numpy). RD default look changed completely (HEAD sim was broken) — eyeball the lilac substrate wash. Hex idle is still dim by the catalog's premultiplied convention. Hex sand's behaviour under rapid `mids` changes (nodal lines move; grains re-collect over ~10–15 frames) was reasoned, not driven.
