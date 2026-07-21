# Lane C — WGSL Pattern Audit (Common Mistakes & Bad Practices)

**Date:** 2026-07-21 · **Scope:** `public/shaders/*.wgsl` — 1314 files · **Mode:** read-only pattern audit (grep-scale + manual spot-read verification)
**Contract reference:** `docs/BINDING_CONTRACT.md` (13 core bindings 0–12, opt-in 13)

Raw data artifacts (same dir): `lane-c-data.json`, `lane-c-pass2.json`, `lane-c-oob.json`, `lane-c-noguard.json`, `lane-c-exotic-stores.json`, `lane-c-extrabuf.json`, `lane-c-divzero.json`.

---

## Scoreboard

| # | Category | Result | Severity |
|---|----------|--------|----------|
| 1 | Division-by-zero risk | **538 risky unguarded divisions in 312 files** (of 3310 division exprs in 1120 files) | 🟡 Medium |
| 2 | textureLoad/Store OOB | **220 files store with no bounds guard**; 16 files with unclamped neighbor loads | 🟡 Low–Medium |
| 3 | textureSample in non-uniform CF | **0** — clean (all compute uses `textureSampleLevel`) | ✅ |
| 4 | Precision/portability (f16, let-reassignment) | **0 f16, 0 real let-regressions** (8 scanner hits = verified false positives) | ✅ |
| 5 | Bindings vs canonical contract | **0 non-canonical bindings**; 1 binding (11) dead in 100% of files; 13 files never write depth | 🟢 Minor |
| 6 | Loop problems | 0 unbounded loops; **boids.wgsl = 2048-iteration fixed loop**; 1 intentional 1024-invocation workgroup | 🟡 Low–Medium |
| 7 | Non-atomic RMW races | **68 ungated writes to reserved `extraBuffer[0..4]` in 30 files** + trail-feedback races in ~6 files | 🔴 **High** |
| 8 | NaN/Inf hazards | 821 files with ≥1 unguarded pow/sqrt/log/normalize (mostly low-risk); several real hazards | 🟡 Medium |
| 9 | GLSL-isms | **0** — clean | ✅ |

---

## 1. Division by zero — 🟡 Medium

Scanned every `/ expr` (comments stripped); excluded guarded forms (`max/abs/clamp(d, …)`, `+ 1e-N`) and provably-safe denominators.

**Most common unguarded risky denominators (occurrences):**
`min` 94 (mostly `min(res.x, res.y)` — safe), `aspect` 118 (safe), `k` 120 (mixed), `dot` 49, `detailContrast` 45, `density` 44, `scale` 40, `count` 38, `r` 35, `delta` 34, `spacing` 32, `radius` 31, `dist` 30, `zoom` 23, `d` 23, `len` 17.

**Verified-real risks (spot-read):**
- `/ zoom` where zoom derives from a uniform that can be 0 → `gen-neon-cyber-mandala.wgsl:222` (`0.12 / zoom`), `dimension-slicer-guided.wgsl:98` (`1.0 / zoom`).
- `/ count` in the guided-filter family (shared template): `conv-guided-video-filter`, `conv-guided-filter-depth`, `blueprint-reveal-guided`, `chromatic-focus-guided`, `digital-reveal-guided`, `ink-dispersion-guided`, `dimension-slicer-guided` — `meanG = sumG / count` where `count` accumulates per-tap; 0 only if window collapses, but no `max(count, 1.0)` guard.

**Top offender files (unguarded risky-div count):**
gen-neon-cyber-mandala (7), quantum-prism (6), dimension-slicer-guided (5), gen-biomechanical-hive-julia (5), gravity-lens (5), fabric-step (4), flip-matrix (4), gen-biomechanical-hive (4), hex-pulse (4), kimi_flock_symphony (4), lenia-on-video (4), magnetic-chroma (4), radial-hex-lens (4), ripple-blocks (4).

**Note:** many heuristic hits are safe by construction (verified: `gen-biomechanical-hive-julia` density = `mix(4.0,10.0,param)`). WGSL f32 div-by-0 → Inf/NaN propagates to `textureStore` (black/NaN pixels) — no crash, but visual corruption.

**Fix:** wrap parameter-derived denominators: `x / max(d, 1e-4)`; guard `count` with `max(count, 1.0)` in the guided-filter template (fix once, propagates to ~8 files).

---

## 2. textureLoad / textureStore out-of-bounds — 🟡 Low–Medium

Renderer dispatches `ceil(scaledW/16) × ceil(scaledH/16)` workgroups (`GraphRunner.ts:94`, `frame.ts:640`) — **edge workgroups overrun the texture whenever canvas dims aren't multiples of 16**, so guards are required. Per WebGPU spec, OOB `textureStore` is discarded (safe), OOB `textureLoad` returns an **indeterminate value** (garbage, not crash).

- **220 files** have `textureStore` with **no bounds guard at all** (neither `textureDimensions` nor `u.config.zw` check). Representative: `physarum.wgsl`, `gen_orb.wgsl`, `aurora-rift*.wgsl`, `lenia.wgsl`, `reaction-diffusion.wgsl`, `spectrogram-displace-pass1/2`, `temporal-echo.wgsl`, `liquid-*` family, `spec-*` family. Repo standard guard: `if (any(coord >= dimsI)) { return; }` (only 78 files use `textureDimensions`; ~870 guard via `u.config.zw`).
- **16 files with unclamped neighbor `textureLoad` offsets** (edge garbage in feedback sims): `navier-stokes-dye`, `chromatic-reaction-diffusion(-rgba)`, `gen-bioluminescent-reaction-diffusion`, `hybrid-reaction-diffusion-glass`, `melting-oil(-blackbody)`, `sim-heat-haze-field(-blackbody)`, `sim-sand-dunes(-rgba)`, `sim-ink-diffusion`, `sim-decay-system-rgba`, `byte-mosh`, `polka-dot-reveal`, `gen_capabilities`.
- ✅ **No clampless offset `textureStore`** found (0 scatter-store OOB).
- ✅ All 31 fixed-texel `vec2<i32>(0,0)` stores (mouse-history pattern in ~25 "*-coupled"/"*-em" files + `pixel-sorter`) are properly gated by `gid == (0,0)`.

**Fix:** add the canonical early-return guard to the 220 files (mechanical); clamp neighbor loads: `clamp(c + off, vec2(0), dimsI - 1)`.

---

## 3. textureSample in non-uniform control flow — ✅ Clean

**0 occurrences** of implicit-LOD `textureSample(` anywhere in the 1314 files. All compute shaders use `textureSampleLevel` (explicit LOD 0.0) — correct for compute. No `@fragment` shaders ship in this folder, so no divergent-derivative hazard exists.

---

## 4. Precision / portability — ✅ Clean

- `f16`: **0 occurrences** (no `f16` enable-extension risk).
- Immutable-`let` regressions (history: `notes/IMMUTABLE_LET_FIX_REPORT.md`, 147 files fixed 2026-03-08): re-ran the scope-aware v2 scanner → 8 files / 11 hits, **all manually verified as false positives** — component writes (`col.r = …`, `metrics.mach = …`) on `var`-declared values, which the regex mistakes for `let r` reassignment (`\b` matches after `.`). Files: anamorphic-caustic-flare, bubble-chamber, gen-depth-refracted-liquid-stained-glass, gen-strange-field-flow, gen-thermal-rainbow-topography, neon-edges, retro-phosphor-stipple, supernova-remnant. **Zero true regressions.**
- `stella-orbit.wgsl` uses `ptr<function, T>` + `*(p)` dereference — unusual (naga-generated style) but **valid WGSL**, no action.

---

## 5. Unused / non-canonical bindings — 🟢 Minor

- ✅ **0 bindings outside the canonical contract**: no `binding > 13`, no nonzero `@group`, nothing the 14-entry bind-group layout would reject.
- Unused-declared bindings (declaration never referenced — harmless with auto-layout, but noise):
  - **binding 11 `comparison_sampler`: unused in 1314/1314 files (100% dead)** — candidate for contract cleanup.
  - binding 8 `dataTextureB`: unused in 1239 (94%); binding 10 `extraBuffer`: 1218 (93%); binding 9 `dataTextureC`: 681 (52%); binding 12 `plasmaBuffer`: 484 (37%); binding 4 `readDepthTexture`: 337; binding 1 `readTexture`: 363; binding 5: 393; binding 0: 236.
  - 151 files reference ≤5 of their 13 declared bindings.
- `writeTexture` never written (binding 2 dead): `ripple-tank-pass1/2`, `wave-inject`, `wave-step` — **intentional** multipass sim stages (verified; final pass composites).
- `writeDepthTexture` never written in 13 gen-* files (e.g. gen-bismuth-singularity-loom-engine, gen-prismatic-cyber-chrono-nebula-peacock, gen-sentient-cyber-chrono-void-serpent) → **stale previous-frame depth** leaks into depth-aware chains. Minor.

---

## 6. Loop problems — 🟡 Low–Medium

- 26 files use `loop {}`; **all contain `break`/`return`** — no unbounded loops. 6 use `loop{}` without a `continuing` clause (valid WGSL, style only): bitonic-sort, fractal-ice-palace, gen-barnsley-fern, gen-electric-kaleidoscope-storm, gen_orb, temporal-rgb-smear.
- **`boids.wgsl:126` — fixed `for (i < 2048u)`** per-invocation loop reading 4 `extraBuffer` floats per iteration (the only bound >500 repo-wide). At full-canvas dispatch this is ~2048×N ops/px — **timeout risk on weak iGPUs**. Consider a tiled/shared-memory reduction or spatial hash.
- `deep-workgroup-multi-effect-blend.wgsl`: `@workgroup_size(16,16,4)` = **1024 > 256** default `maxComputeInvocationsPerWorkgroup` — **intentional** (`requiresDeepWorkgroup: true` in header + `shader_definitions/advanced-hybrid/deep-workgroup-multi-effect-blend.json`); device policy must request the raised limit. Info only.

---

## 7. Non-atomic read-modify-write races — 🔴 High (top finding)

### 7a. Ungated writes to contract-reserved `extraBuffer[0..4]` — 68 writes / 30 files

Contract (`BINDING_CONTRACT.md`): extraBuffer[0..2] = CPU-written bass/mid/treble, [3] reserved, **[4] = historyHead ring pointer (CPU-written)**, [5..132] = FFT. These shaders do `var prev = extraBuffer[k]; …; extraBuffer[k] = smoothed;` with **no `gid == (0,0)` gate** → every invocation of the dispatch RMWs the same address (massive intra-GPU race, nondeterministic feedback), and they **stomp CPU-written audio/historyHead every frame**.

| File | Indices | Worst aspect |
|------|---------|--------------|
| **gen-ghost-flame** | 3, **4** | overwrites **historyHead** → corrupts history ring for all temporal shaders |
| **elastic-chromatic** | 0–4 | full audio block + historyHead |
| **gen-cybernetic-mycelium-neural-web** | 0–4 | same |
| **gen-neural-bioluminescence-matrix** | 0–4 | same |
| **gen-showcase-nebula-core** | 0–4 | same |
| **gen-sierpinski-tetrahedron** | 0–4 | same |
| **gen-worley-cellular-noise** | 0–4 | same |
| phantom-lag | 0–3 | |
| pixel-stretch-cross | 0–3 | |
| gen-alpha-aurora, gen-bioreactor-bloom, gen-celestial-weave, gen-chrono-mycelial-tapestry, gen-cryogenic-frost-plasma-matrix, gen-echo-dunes, gen-ethereal-quantum-hologram-bonsai, gen-fireworks-audio-symphony, gen-hyper-dimensional-bismuth-matrix, gen-luminous-cauldron, gen-magnetic-ferrofluid-sculpture, gen-magnetic-kelp, gen-neon-snowfall, gen-neuro-fluid-plasma-lotus, gen-opal-circuit, gen-prismatic-quantum-fractal-nautilus-engine, gen-resonant-quantum-plasma-dragon-eye, gen-sentient-ferro-silicate-swarm, gen-topological-phase-weave, gen-vortex-cathedral, holographic-crystal, oscilloscope-overlay, waveform-glitch | 0 | ungated smooth-bass RMW race |
| magnetic-interference | 0,1 | |
| gen-translucent-nebula | 1 | |
| gen-prismatic-crystal-growth | 2 | |
| electric-eel-storm | 3 | |

### 7b. Gated but contract-violating scratch use
- `echo-trace.wgsl` — writes extraBuffer[0..7] (gated by `gid==(0,0)`, but stomps bass/mid/treble/**historyHead** + FFT bins 5–7).
- `gen-percolation-threshold.wgsl:83-84` — writes extraBuffer[0..119] as lattice scratch → stomps audio block **and FFT bins**.
- Agent-state sims (physarum×3, gen-physarum-sacred-geometry, gen-wasm-hls-physarum-swarm, boids, kimi_flock_symphony, neon-cursor-trace, ripple-tank-pass2) use extraBuffer from slot 0 as agent arrays — per-invocation slots are race-free intra-dispatch, but agent 0 overwrites the audio slots (contract conflict).

### 7c. Trail-feedback scatter races (write-write, lost updates)
- **`pixel-sand.wgsl:210-213`** — particles move to `outPos`; two cells can target the same destination → nondeterministic winner, plus `writeTexture` at `outPos` leaves holes/stale pixels. **High.**
- **`physarum.wgsl` / `physarum-gemini` / `physarum-grokcf1`** — `textureLoad(dataTextureC, particleCoord)` → `textureStore(dataTextureA, particleCoord)`; multiple agents per texel → lost trail updates (visually tolerable for physarum, still a race). Medium.

**Fix:** (a) gate all persistent-state writes with `if (all(gid.xy == vec2(0u)))` and move shader scratch above index 132 (or to dataTextureB); (b) never write index 4 from WGSL; (c) for scatter sims use deterministic priority rules or atomic-free double-buffer with per-texel ownership.

---

## 8. NaN / Inf hazards — 🟡 Medium

821 files contain ≥1 unguarded `pow`/`sqrt`/`log`/`normalize` (raw heuristic; most are safe camera-basis `normalize(ta - ro)` or clamped color pows). Verified notable:

- **`sand-dunes.wgsl:83-86`** — blackbody: `pow(t - 60.0, -0.133…)` (negative base → NaN) when `t < 60`, and `log(t)` when `t <= 0`; only the outer `clamp(…, 0, 1)` saves the pixel, and clamp(NaN) is implementation-defined. **Medium-High.**
- **`gen-magnetic-ferrofluid-sculpture.wgsl:129`** — `normalize(mousePos - pos)` → NaN when cursor is exactly on the pixel. Same pattern in other mouse-distance shaders.
- `gen-sonoluminescent-chrono-geode-matrix.wgsl:90` — `/ pow(s, 4.0)` with param-derived `s` → Inf at s→0.
- Heaviest raw counts: gen-hyper-dimensional-bismuth-matrix (15), gen-magnetic-ferrofluid-sculpture (15), sand-dunes (15), stella-orbit (14), gen-bismuth-(crystal-)citadel (13+13).

**Fix:** `pow(max(base, 0.0), x)` / `pow(abs(base), x)`; guard `normalize(v)` with length check or add epsilon (`v + vec3(1e-6)`); `log(max(t, 1e-4))`.

---

## 9. GLSL-isms — ✅ Clean

0 occurrences of `gl_FragCoord`, `gl_FragColor`, `gl_Position`, `texture2D(`, `#version`, `varying`/`attribute`/`precision` qualifiers (word-level scan; earlier hits were English prose in comments).

---

## Top 10 files needing fixes (priority order)

1. **gen-ghost-flame.wgsl** — ungated extraBuffer[3,4] writes; stomps historyHead (🔴)
2. **elastic-chromatic.wgsl** — ungated extraBuffer[0..4] (🔴)
3. **gen-cybernetic-mycelium-neural-web.wgsl** — ungated extraBuffer[0..4] (🔴)
4. **gen-neural-bioluminescence-matrix.wgsl** — ungated extraBuffer[0..4] (🔴)
5. **gen-showcase-nebula-core.wgsl** — ungated extraBuffer[0..4] (🔴)
6. **gen-sierpinski-tetrahedron.wgsl** — ungated extraBuffer[0..4] (🔴)
7. **gen-worley-cellular-noise.wgsl** — ungated extraBuffer[0..4] (🔴)
8. **pixel-sand.wgsl** — particle-move write-write race + writeTexture holes (🔴)
9. **physarum.wgsl** (+ physarum-gemini/grokcf1) — trail RMW race at computed coords; extraBuffer[0] stomp (🟠)
10. **sand-dunes.wgsl** — `pow(t-60, neg)`/`log(t)` NaN domain hazards (🟠)

Runners-up: gen-percolation-threshold (extraBuffer[0..119] stomp), echo-trace (0..7), phantom-lag & pixel-stretch-cross (0..3), gen-alpha-aurora / oscilloscope-overlay / waveform-glitch (ungated [0] race), boids (2048-iter loop), gen-neon-cyber-mandala & dimension-slicer-guided (`/zoom`), the 8-file guided-filter family (`/count`).

## Cross-cutting recommendations

1. **Add a lint rule** (extend `bindgroup_checker.py`): flag any `extraBuffer[N] =` with literal `N ≤ 4` — would have caught all of finding 7a.
2. **Mechanical guard pass**: insert `if (any(coord >= dimsI)) { return; }` into the 220 guard-less shaders (or centrally guarantee dispatch-exact coverage — not possible with ceil-dispatch).
3. **Fix the guided-filter template once** (`max(count, 1.0)`) — clears ~8 files of div-zero risk.
4. **Contract decision**: binding 11 (`comparison_sampler`) is dead in 100% of 1314 shaders — keep for future shadow effects or drop from the layout.
