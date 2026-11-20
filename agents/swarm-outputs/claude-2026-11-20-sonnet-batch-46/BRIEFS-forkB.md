# BRIEFS — fork B (sonnet/batch-46): distortion_gravitational_lens, kinetic-dispersion

Written BEFORE any WGSL edit. HEAD = worktree file after the coordinator's header-only prelude migration (copied to the scratchpad `forkB/head/` for A/B renders and timing).

---

## 1. distortion_gravitational_lens  (FIRST pass, no `Ideas:` line)

### HEAD read-through (defects found)
- **Wrong audio source (rescue).** `audioPulse = u.zoom_config.w` is `mouse_down`, not audio; the file claims `audio-reactive` but never reads `plasmaBuffer`. It drives the primary mass (`2.0 + pulse*2.0`) and the disk gain (`1 + pulse*2`) — i.e. a *click* pumps the hole. Fix: `held = u.zoom_config.w` keeps the click behaviour byte-for-byte; `audioPulse = plasmaBuffer[0].x` (bass) added at a smaller weight. No click, no audio → identical to HEAD.
- **Degenerate Einstein-ring highlight (rescue).** `einsteinRadius(mass, length(toPrimary))` is called with the *pixel's own distance*, so `einsteinR = 0.1414·distPrimary`, `ringDist = 0.859·distPrimary`, and `smoothstep(0.02, 0, ringDist)` only fires inside r < 0.023 of the cursor: a white dot, not a ring. The file's headline feature ("Einstein ring formation") never drew. Replaced by Idea 1 (critical curve from the real lens Jacobian).
- **Flagged, NOT fixed (look-defining, user decision):** (a) `sourcePos = rayPos - totalDeflection*0.5` has the opposite sign to the standard lens equation (β = θ − α): HEAD is a *diverging* lens, sources are sampled from *outside* the pixel, so the picture is radial pinch streaks around the cursor rather than a converging lens with inverted interior images. I keep the sign (identity / saved look); the new Jacobian code is derived from the same `sourcePos` expression, so a later sign flip is a one-line change. (b) UV-space distances have no aspect correction → the lens is elliptical on 16:9.
- Floor gaps: `dataTextureA` never written; alpha hardcoded `1.0`; depth store OK.

IDENTITY: a cursor-anchored point-mass gravitational lens (plus orbiting cluster masses) that bends the photo around it, with a blackbody accretion disk, redshift and chromatic split.

KEEP VERBATIM: 4 params + roles (`lens_strength` → 0.5+x, `mass_count` → 1..5, `disk_intensity`, `aberration`); `Mass` struct; `deflectionAngle` (K/(r+0.001), 0.1·R singularity cutoff); orbiting-mass layout (angle/radius formulae); per-channel `(1±aberration)` deflection split; zero outside the image (black voids); disk annulus 3R..15R with `sin(20φ + 2t)` pattern and r^-3/4 blackbody bands; gravitational-redshift tint; `x/(1+0.5x)` tone map; vignette; depth = |deflection|. `sourcePos` sign.

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): the lens samples one point per channel. The next-better approximation of the same operator is a *ray-footprint* filter: the pixel's footprint maps through the lens Jacobian to a stretched parallelogram in the source plane — near the critical curve that is many source pixels long, and a single tap aliases it.
- Tactic 2 (physics one step further): a lens that magnifies area conserves surface brightness, so flux per pixel diverges on the critical curve (μ = 1/|det J|). Real cluster lenses show bright critical curves and tangential arcs. A real accretion disk is *not* symmetric: orbital speed Doppler-beams the approaching side (I_obs = D³·I_em, T_obs = D·T, D = 1/(1−β_los)).
- Tactic 3 (promote an intermediate): the deflection loop already evaluates every mass' α at the pixel; its derivative (the Jacobian) is a free by-product — analytic, no extra loop, no extra taps.
- Tactic 6 (history): the lens is stateless (A is unread). No history idea. A = display RGBA (written for the contract; nothing reads it).

ADD:
1. **Critical-curve magnification glow (§12.2F "energy-conserving brightness / Einstein-ring magnification")** — analytic 2×2 Jacobian summed over all masses, `det = (1−½Axx)(1−½Ayy) − ¼Axy²`, `crit = exp(−(det/0.2)²)`. Magnifies the lensed light (`color *= 1 + crit·…`) and adds HEAD's cool ring tint along the curve. Replaces the dot-at-the-cursor (rescue) and, because it uses the summed Jacobian, the cluster masses bend/split the ring (cat's-eye curves around the orbiting masses). Native: it is the Einstein ring.
2. **Doppler-beamed accretion disk (§12.2F blackbody row + relativistic beaming)** — inside the existing annulus: β(r) = 0.38·√(r_in/r), line-of-sight β_los = −0.8·β·cos φ (inclined disk, approaching side on the left), `D = 1/(1 − β_los)`, disk temperature `T·D` fed through the existing blackbody bands, intensity ×`D` on top of the existing T² (→ D³ total) and normalised by the angular mean of D³ so the disk's average brightness stays at HEAD's. Native: it is the signature of every black-hole disk image.
3. ~~Ray-footprint arc filter~~ — **DROPPED after implementation.** Built (3 taps along the long axis of the Jacobian footprint, gated to >1/4 px extra footprint); SwiftShader A/B put it at +0.2-0.3× on top of ideas 1-2 (1.55-1.8× HEAD, over the 1.3× cap), and a stress-texture A/B (`SRC=tex`) showed only 1.9% of pixels differing >2/255, near-invisible. Removed; card ends at two ideas.

FORMULA ADMISSION: (1) optical table, consumes `deflectionAngle`'s own quantities; deleting it leaves exactly HEAD's lens; keeping only it is still this lens → additive. (2) blackbody row; consumes `radius`, `innerRadius`, `toPrimary` already in the disk branch; deleting it leaves HEAD's symmetric disk. Not reserved rows (no Cauchy dispersion, no NLM/patch similarity). All branchless (`select`/`step`/`clamp`), guarded `max(r,1e-4)`, positive-base `pow` only.
FORBID: springs/ripples (the pointer already owns the effect via mass 0 — no new tether), IQ palette, Cauchy dispersion, NLM, thin-film, any new param, changing the deflection law / sign / aspect.
A PACKING: display RGBA (new write; HEAD wrote nothing to A; no C read).

---

## 2. kinetic-dispersion  (FIRST pass on `Ideas:`; older `Upgraded: 2026-05-31`)

### HEAD read-through (defects found)
- **Dead + racy pointer spring (rescue).** `mouse = extraBuffer[133..134]`, `springVel = extraBuffer[135..136]`; thread (0,0) writes the spring each frame. But `writeExtraBuffer` (`src/renderer/webgpu/audioDepth.ts:49`, `frame.ts:281`) re-uploads all 256 floats every frame, zeroing 133..138. So every frame `prevTime = extraBuffer[137] = 0` → first-touch branch → spring "seeds" at the raw cursor, velocity 0, `velBoost = 0`. Worse: every *other* thread reads `mouse` from the buffer with no ordering against thread (0,0)'s write — on a real GPU the first resident wave of workgroups reads `(0,0)` (influence centred on the top-left corner) and later waves read the cursor, so the influence field is a nondeterministic patchwork. Rescue: `mouse = mouseRaw` (what the shader effectively did when it worked), spring block and dead `velBoost` removed. The harness (`agents/mr.mjs`) keeps `extraBuffer` between frames, so HEAD renders *better* there than in the app (spring works) — A/B vs HEAD therefore differs by the (real) spring lag; flagged.
- Per-frame `rnd` flicker, `curl2D` hash "curl", FFT voices, click bursts, audio shock all OK. `plasmaBuffer[0].xyz` indexed ✓. A + depth + semantic alpha written ✓. No ACES (pass-through source outside the field — not adding one).

IDENTITY: a cursor-centred shatter field that splits the photo into blocks, displaces each at random with RGB fringing, driven by FFT bins and click cracks.

KEEP VERBATIM: 4 params + roles (`sensitivity` → field strength ×50·bass_env, `scatter` → per-block kick ×0.1·voiceGain, `aberration` → R/B split ×0.05·(1+0.5 treble), `granularity` → block size 1..50 px); per-block FFT voice gain; ripple click bursts (crack kick + 0.15 flash); `curl2D`; depth-scatter; white-noise mix; bass shockwave; semantic alpha; display A (RGB unchanged).

MECHANISM INTERROGATION
- Tactic 3: `springVel` was computed and thrown away (dead). The per-block random `rnd` is computed and only used *inside* the block — never compared to the neighbour's, though the tear is exactly the *difference* between adjacent blocks.
- Tactic 5 (device artifact): a block codec/shatter effect's signature artifact is the visible *blocking seam* where neighbouring blocks have different offsets.
- Tactic 6 (history): HEAD writes A but never reads C. Exact `textureLoad(dataTextureC)` of last frame's own A is a free channel; `A.a` was semantic alpha that nothing read.
- Tactic 2 (physics one step further): a fractured medium doesn't heal instantly — cracks relax.

ADD:
1. **Schmitt-trigger shatter latch (§12.2B "Schmitt-trigger lock")** — per pixel: `engaged = intensity > 0.6`, hold while `> 0.25`, otherwise decay ×0.965/frame, via exact `textureLoad(dataTextureC, coords, 0)`; `intensity = max(intensity, 0.85·latch)`. The field leaves a fading wake of still-shattered blocks behind the cursor (and click cracks linger), so motion becomes visible without any velocity state (the dead spring can't supply it). Latch stored as **`A.a = −latch`** (HEAD's A.a was the semantic alpha; writeTexture keeps the semantic alpha), read back with `max(−C.a, 0)` so a foreign shader's positive alpha in a shared A can't spoof a latch on shader switch.
2. **Block-boundary seam (§12.2B block-domain "blocking artifact")** — for each pixel, distance to the nearest block edge (from `fract(coords/granularity)`), the neighbour block across that edge, `jump = |rnd − rnd_nb|` (same hash, same time term) → a 1 px cool glint along edges where the two blocks' displacements differ, scaled by `jump·intensity·scatter·depthScatter` (so the **Scatter** slider still owns it; 0 → none) and faded out below 2–5 px blocks. Native: cracked tiles show their cracks.

FORMULA ADMISSION: both rows are in the distortion/glitch table; both consume values the file already computes (`intensity`, `rnd`, `blockUV`, `granularity`, `scatter`, `depthScatter`); deleting either leaves exactly HEAD; neither is reusable on the lens file. Not Cauchy dispersion. No new param, no extraBuffer state.
FORBID: springs/extraBuffer state (dead), IQ palette, a second tear system, thin-film, new params, ACES on the pass-through photo.
A PACKING: A.rgb = display RGB (same as HEAD); **A.a = −shatter latch** (HEAD: semantic alpha, never read). writeTexture alpha stays semantic.
