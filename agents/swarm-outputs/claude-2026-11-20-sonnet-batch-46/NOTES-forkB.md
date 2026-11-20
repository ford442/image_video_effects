# NOTES — fork B (sonnet/batch-46): distortion_gravitational_lens, kinetic-dispersion

VM = SwiftShader, no real GPU: structural + render proof only; no claim that the ideas "look right" on hardware. HEAD for A/B = the worktree file after the coordinator's header-only prelude migration (scratchpad `forkB/head/`). Renders: `agents/mr.mjs` (`SRC=img`), timing: `agents/mr_ab.mjs` (interleaved, 512², 60 cycles, ≥4 rounds, box load 7–21 so single readings lie).

---

## distortion_gravitational_lens — first pass

**Idea Card ADD (2, §12.2F):**
1. **Critical-curve magnification glow** — `lensAt()` returns the analytic Jacobian of the existing deflection (`A = -(g I + (g'/r) δδᵀ)`), summed over all masses in the existing loop; `det(I − A/2)` → `crit = exp(−(det/0.2)²)` → `color *= 1 + 0.8·crit·lensStrength` (magnified background light) + HEAD's cool ring tint (`vec3(0.8,0.9,1.0)·ringGain·0.5`). Findable: `// ── Idea 1` at `lensAt` and in `main`. The ring now bends/merges around the orbiting cluster masses (held click or max `mass_count` merges two curves into a peanut).
2. **Doppler-beamed accretion disk** — inside the existing annulus: `β = 0.38√(r_in/r)`, `β_los = −0.8β·cosφ`, `D = 1/(1−β_los)`, `accretionDiskColor(..., D)` (T→D·T through the existing bands, intensity ×D → D³), ÷ angular mean of D³ (`(1−b²)^2.5/(1+b²/2)`). Findable: `// ── Idea 2` in `main` + the `doppler` argument.
3. Ray-footprint arc filter — **built and dropped** (cost +0.2–0.3×, only 1.9% of pixels differed >2/255 on a stress texture). See BRIEFS.

**KEEP VERBATIM:** 4 params + roles; `Mass` struct; deflection law (`−normalize(δ)·K/(dist+0.001)`, 0.1R cutoff — now evaluated as `−δ·g`, mathematically identical, one sqrt instead of sqrt+normalize); orbiting-mass layout; per-channel `(1±aberration)` split; black outside the image; annulus 3R..15R, `sin(20φ+2t)` pattern, r^-3/4 blackbody bands; redshift tint; `x/(1+0.5x)` tone map; vignette; depth = |deflection|; `sourcePos` sign.

**A packing:** display RGBA (tone-mapped, post-vignette). HEAD wrote nothing to A; nothing reads C.

**Rescues:**
- *Wrong audio source:* `audioPulse = zoom_config.w` is `mouse_down`. Click behaviour kept exactly (`held`: mass +2, disk gain +2); real audio (`plasmaBuffer[0].x` bass) added (mass +0.8·bass, disk +1.5·bass). No click + no audio → identical to HEAD, so `audio-reactive` in the JSON is now true.
- *Degenerate Einstein-ring highlight:* `einsteinRadius()` was fed the pixel's own distance → ring glow only inside r < 0.023 (a dot). Function removed; replaced by Idea 1.
- Floor: `dataTextureA` written; alpha semantic = `mix(0.55,1,coverage)` lifted by ring/disk emission (HEAD hardcoded 1.0; in-image pixels stay 1.0, voids 0.55).

**Flagged, NOT fixed (look-defining — user decision):**
- `sourcePos = rayPos − totalDeflection·0.5` has the opposite sign to the standard lens equation: HEAD is a *diverging* lens (radial pinch streaks) rather than a converging one with an inverted interior. Kept (identity). The new Jacobian is derived from the same expression, so flipping the sign later is one line (`+ totalDeflection·0.5`) and the critical curve stays at θE = √(K/2).
- UV-space distances, no aspect correction → elliptical lens on 16:9.

**Diff vs HEAD:** default params, cursor centre, 256², t=1 s: 7.5% of pixels differ >3/255 (4.4% >12/255) — ring + disk asymmetry; rest bit-identical. NaN 0 at default / held+audio / all-min / all-max.
**Timing (interleaved, SwiftShader, 512²):** per-round paired medians 1.19, 1.04, 1.31, 1.23 → ≈1.2× HEAD. (First build with idea 3 + separate deflection/Jacobian: 1.55–1.8× → dropped idea 3, folded deflection+Jacobian into one `lensAt`.)
**Gates (1/1 each):** wgsl_precommit_gate ✅, verify-naga-wasm ✅ (0 invalid), dead sliders 0 (2 defs scanned), audit_extrabuffer PASS (no extraBuffer use).
JSON: `description` appended; `params` / `features` untouched.

---

## kinetic-dispersion — first pass on `Ideas:` (older `Upgraded: 2026-05-31` → `2026-05-31, 2026-11-20`)

**Idea Card ADD (2, §12.2B):**
1. **Schmitt-trigger shatter latch** — `drive` (HEAD's `intensity`) engages the latch above 0.6, holds above 0.25, otherwise relaxes ×0.955/frame via exact `textureLoad(dataTextureC, coords, 0)`; `intensity = max(drive, 0.7·latch)`. Moving cursor leaves a fading wake of still-shattered blocks; click cracks linger. Findable: `// ── Idea 1`.
2. **Block-boundary seam** — nearest block edge from `fract(coords/granularity)`, neighbour block across it hashed with the same time term, 1 px glint (`vec3(0.55,0.68,1.0)·0.35`) scaled by `|rnd−rndNb|·intensity·scatter·depthScatter` (Scatter slider owns it; 0 → none), faded out below 2–5 px blocks. Findable: `// ── Idea 2` + `// Idea 2: cracked-edge glint`.

**KEEP VERBATIM:** 4 params + roles (sensitivity ×50·bass_env, scatter ×0.1·voiceGain, aberration ×0.05·(1+0.5 treble), granularity 1..50 px); per-block FFT voices (`extraBuffer[5..132]` reads); ripple click bursts + flash; `curl2D`; depth scatter; white-noise mix; bass shockwave; horizontal R/B split; semantic alpha on writeTexture; `plasmaBuffer[0].xyz`.

**A packing:** `A.rgb` = display RGB (HEAD); **`A.a = −latch`** (HEAD: semantic alpha, never read). Read back as `clamp(−C.a, 0, 1)` so any foreign shader's positive alpha left in a shared A cannot be mistaken for a latch on a shader switch. writeTexture alpha is unchanged.

**Rescue — dead + racy spring:** HEAD held the pointer spring in `extraBuffer[133..137]`; `writeExtraBuffer` (`src/renderer/webgpu/audioDepth.ts:49`, `frame.ts:281`) re-uploads all 256 floats each frame, zeroing 133..138 → spring never persists, `springVel` = 0, `velBoost` = 0, and every non-(0,0) thread reads `mouse` from a buffer only thread (0,0) writes, unordered → on a real GPU the first resident workgroups read `(0,0)` (influence centred top-left) and later ones the cursor. Fixed: `mouse = mouseRaw`; spring block, `springVel`, `velBoost` removed (they computed 0). **Behaviour note:** `agents/mr.mjs` keeps `extraBuffer` between frames, so HEAD *in the harness* has a working spring whose `velBoost` (up to +0.5, applied to the whole frame, not masked by distance) shatters the entire picture while the cursor moves — the app never did that. The new file matches the app's real behaviour, not the harness's HEAD.
**Not fixed / decision for the user:** the "mouse-velocity" in the description is still not real (no place to keep pointer velocity in an in-place upgrade; same finding as batch-45 data-moshing). The latch wake is a stateless stand-in that makes motion visible.
**Not added:** ACES (the effect passes the source photo through outside the field; a global tone curve would change every pixel). `upgraded-rgba` tag was already in JSON `features` (unchanged).

**Diff vs HEAD:** static cursor default, 256², t=1 s: 18% of pixels differ >3/255 (12% >12/255) — all inside the influence disc (block seams); corner 32×32 identical. NaN 0 (default, clicks+max params, block size 1 px / 50 px, scatter 0). Moving-cursor render shows the wake fading (24 frames @ 50 ms).
**Timing:** per-round paired medians 0.81, 0.96, 1.04, 1.07 → ≈1.0× HEAD (the removed spring block pays for the C load + extra hash).
**Latch decay is per-frame** (0.955/frame): half-life ≈ 15 frames = 0.25 s at 60 fps, 0.75 s at 20 fps. No dt source without state.
**Gates (1/1 each):** wgsl_precommit_gate ✅, verify-naga-wasm ✅, dead sliders 0, audit_extrabuffer PASS (kinetic now only reads 5..132).
JSON: `description` appended; `params`, `features`, `x-meta` untouched.
