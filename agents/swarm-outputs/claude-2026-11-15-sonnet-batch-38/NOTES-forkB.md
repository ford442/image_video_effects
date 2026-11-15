# NOTES — fork B (reaction-diffusion, radiating-haze) — sonnet/batch-38

Both files: 3rd / 2nd pass; `Upgraded:` and `Ideas:` lines appended to, never replaced. No git commits. SwiftShader WebGPU + numpy only — **no real-GPU visual claim**.
Scratch: `/tmp/claude-0/-root-image-video-effects/3bc05086-3a8b-4229-9600-41329cbd28af/scratchpad/forkB/` (copies of the harness: `mr_sat.mjs` = saturated-disc source for the haze, `mr_rip.mjs` = ripple injection, `mr_perf2.mjs` = in-process paired HEAD/new timing; numpy port `rd_port.py`; ablation dirs `hz/`, `rd/`).
HEAD = tree at fork start (header-only `_prelude.wgsl` migration), copies in `…/scratchpad/head/` and `rd/head.wgsl`, `hz/head.wgsl`.

**Saved params / roles / ranges byte-exact in both JSONs** (only `description` was lengthened: haze +38 chars, RD +55 chars). `audit:dead-sliders` 0 new on both ids. No new params, no `extraBuffer`.

---

## 1. reaction-diffusion (3rd pass)

**KEEP VERBATIM held:** conveyor (`flowDir`, `baseCoord`, `advectPixels`), 0.55 anisotropic Laplacian mix, packets, ripple fronts, `mouseSeed`, mitosis pinch, the three colour ramps (a `frontGlow` term is added to their sum, ramps themselves unchanged), `totalAlpha` accumulation, ACES on `writeTexture` only, `max(…,0)` before ACES. Slider roles unchanged (x diffusion, y feed + packet speed, z kill, w accumulation→alpha only, as at HEAD).
**A packing:** raw `(U, V, packet, accumulation)` — unchanged, truthful (no ACES on A). `isoLap` is back to HEAD's 5-point `(l+r+u+d−4p)·0.25`.

### Rescues — both CONFIRMED with numpy port (`rd_port.py`, a line-for-line port of HEAD; it matches the GPU timeline) and SwiftShader

**R1 (U floor) — CONFIRMED, the shader was dead.** HEAD `a = max(prev.r, 0.75+seed·0.25)` re-supplies U ≥ 0.75 every frame, so the reaction can never exhaust it and V = 1 is an absorbing state.
- numpy N = 192, HEAD defaults: f=60 stripes (16 % active), **f=300 uniform grey** (V 0.024, pattern +0.96, std 0.012), f=600 stripes again, **f=900 V = 1 everywhere** (std 0.000, pattern −0.994 → black), f=1200 identical.
- SwiftShader 192 px, HEAD: f=60 travelling stripes, f=300 uniform grey, **f=900 pure black** (`rd_head_192_{60,300,900}.png`, side by side in `rd_head_timeline.png`). Numpy and GPU agree at 60/300/900.
- The flood time is size-dependent (numpy N = 128 had not flooded by 1500 frames), so "~15 s" is the 192-px figure.
- Fix (in-shader, saved params untouched): U keeps what the chemistry left (`select(prev.r, 0.75+seed·0.25, fresh)`, `fresh = prev.r+prev.g < 1e-4`, i.e. the photo only seeds a cold start). The `f·(1−a)` feed term is now the only U supply → Turing instability can happen.
- Without R1 (`offR1`), 192 px idle: meanL 0.770 / stdL 0.072 (washed out), with R1 0.743 / 0.165.

**R2 (diffusion scale) — NOT CONFIRMED as posed.** The HEAD diffusion (Du ≈ 0.006–0.025, Dv = Du/2 in per-step units) is small, but with the floor gone the system forms length-scale ≈ 6–9 px structure (corr length 6–7 px at N = 128 / 1500 frames), not pixel noise. ×8 diffusion on HEAD still floods (V = 1), on no-floor gives a flat V ≈ 0.32 field (std 0.03). So diffusion is not the lever; I did not touch it.
**What the numpy sweep found instead (Rescue 2 — kill range):** with the floor gone, the saved default (feed 0.044, kill = 0.035+0.5·0.045 = 0.0575) sits on the flat side of the Gray-Scott saddle-node line f = 4(f+k)² (my `gs_scan.py`: f=0.044,k=0.0575 → `uniform-active (V≈0.27)`; k=0.0625 → pattern). Fix: `killRate = 0.040 + z·0.045` (range shifted +0.005, same 0.045 span, same role). Default is now k = 0.0625 (pattern band: mean 0.15, std 0.13, 38 % of pixels > 0.2). Without R2 (`offR2`), 192 px idle: 0.732 / 0.180 vs 0.743 / 0.165 — a visible but small change at t < 2 s; it matters over time (flat state otherwise).
**Residual (honest):** the rescued sim is alive but not steady. numpy N = 160, 2400 frames (`f1.txt`, final constants without the two ideas): active fraction 0–72 %, below 1 % at 4 of 20 samples (f = 240, 960, 1080, 1440, 1920 are flat phases) → roughly 20–25 % of the time the frame is low-contrast before the next burst re-ignites from packets/seed. GPU 192 px long run (`rd/long.log`): f=420 stdL 0.116, 600 stdL 0.234, 900 meanL 0.116/stdL 0.042 (flat), 1500 stdL 0.114, 2400 stdL 0.060. HEAD after f≈900 is a frozen black frame forever; new keeps cycling. I did not try to eliminate the flat phases (would need a new solver/spring — forbidden by the card).

### Ideas (header: `Ideas: … autocatalytic front glow (native); photo-driven kill map (native)`)

| What | Where (`reaction-diffusion.wgsl`) | §12.2 row |
|---|---|---|
| Idea 3 (= card idea 1, **replaced**) autocatalytic front glow | L105-116: `rate = 1−exp(−reaction·14)`, orange→warm-white `frontGlow`·0.55 added to the colour sum | native |
| Idea 4 (= card idea 2) photo-driven kill map | L97-103: `killLocal = killRate + (clamp(seed,0,1)−0.5)·0.010`; `killRate` stays the global kill | native |
| Rescue 1 / 2 | L64-71 / L36-41 | — |

**RULE 15 — card idea 1 (isotropic 9-point Laplacian, §12.2D) was replaced, not silently swapped.** I implemented it exactly as carded (0.2/0.05/−1 stencil on `baseCoord`, ×0.25/0.3, same anisotropic mix) and measured it with the idea zeroed: **≤ 1.1 % of pixels |Δ| > 0.02** at 192 px (and still ≤ 1.1 % with diffusion ×3) — at pixel scale the diamond bias of a 5-point stencil is below the colour ramp's quantisation. Removing it also shed the dead code. Replacement: **autocatalytic front glow** — `reaction = U·V²` was computed and used only to update the field, yet it peaks exactly on the moving fronts. Same noun (the chemistry's own rate), deletion test: removing it flattens every front back to a smooth band edge (measured below); expert test: a reaction-rate map is how Gray-Scott is usually visualised. **The §12.2D row ("isotropic 9-point Laplacian — reaction-diffusion") is therefore UNUSED in this batch** — coordinator may re-allocate it. A `lap9` option remains in `rd_port.py` only.
Photo kill map: Δ = ±0.005 around the slider's kill. **Not entirely inside the pattern band:** at the default feed (0.044) `gs_scan` gives k = 0.0575 (darkest pixels, local kill 0.0575) `uniform-active`, k = 0.0625 (mid) pattern, k = 0.065–0.0675 (brightest) pattern fading toward extinct (11 % active), so shadows tend flat-active and highlights thin out — it never floods, but the 'pattern follows the photo' effect is partly 'activity follows the photo'.

**Visibility (ablation = idea zeroed in a scratch copy; % px max-channel |Δ| > 0.02 / mean|Δ|; `rcmp.py` labels "Idea1 9-point" mean the front glow, "Idea2" the kill map — labels in the script are stale, the files are correct; synthetic `SRC=img` source, default sliders 0.5,0.5,0.5,0.5):**

| case | front glow whole / pointer disc | kill map whole / pointer disc | all changes vs HEAD whole / disc |
|---|---|---|---|
| 192 idle | 12.4 % / – | 5.4 % / – | 13.6 % / – |
| 192 held (0.4,0.6, down) | 19.1 % / 36.3 % | 7.4 % / 3.5 % | 22.1 % / 39.4 % |
| 576 held (90 f) | 6.5 % / 34.3 % | 3.1 % / 5.0 % | 6.8 % / 34.5 % |
| 576 idle (60 f, t = 1 s) | not run separately | – | **0.00 % / mean 0.0011** |
(disc = r < 0.18 around the pointer. 192-px rows: frame count / t_end were not recorded in the logs — the 576 rows are 90 f, t_end 1.5 s held and 60 f, t_end 1.0 s idle.) Kill map is the weakest idea (3–7 %, only 3.5–5 % in the pointer disc); it is a slow morphology change, so it is judged over time, not in a 1–2 s render — the 576 idle 60-frame run shows nothing at all because the chemistry has not ignited yet at t = 1 s (HEAD and new both still flat there). **Not verified: kill-map visibility on real photos with strong tonal regions (the harness source is two soft discs on a ramp).**

**Other required renders:** audio 0.8/0.5/0.9 (192, 60 f): meanL 0.743→0.658, stdL 0.165→0.264 (audio changes the picture); `A16=1`: identical to rgba32float (0.743/0.165); ripple (custom `mr_rip.mjs`, 192 px, 90 f, click at 0.9,0.9): HEAD 0.536/0.367, new 0.609/0.280, glow off 0.556/0.351, kill-map off 0.612/0.278; `nan` 0 in every run. Slider sweep (192, 60 f, meanL/stdL; base 0.743/0.165): diffusion 0→0.793/0.001, 1→0.786/0.048; feed 0→0.703/0.225, 1→0.793/0.000; kill 0→0.701/0.212, 1→0.792/0.023; accumulation 0/1 → identical colour, meanA 0.511/0.988 (alpha only, as at HEAD). Every slider moves the picture; the extremes of diffusion/feed/kill leave the Gray-Scott pattern band (flat), which is a property of the chemistry, not a dead slider.

**Default-look change (meanL/stdL, 192 px; HEAD from `rd/batch1.log`, final from `rd/batch2.log`, same harness settings):** idle HEAD 0.709/0.239 → new 0.743/0.165; held HEAD 0.627/0.321 → new 0.685/0.233. (An earlier version of this idea — the 9-point stencil — measured 0.728/0.209 idle and 0.66/0.284 held; superseded.) Over 900+ frames HEAD is a frozen black frame, new keeps cycling (see residual).

**Cost:** paired in-process, 576 px, 40 frames, 4 runs: median per-frame new/HEAD 0.99, 1.08, 0.84, 0.89; ratio of per-variant minima 0.95, 0.99, 0.99, 1.02 → **≈ 1.0×** (one extra `exp`, one extra `select`).

**Open:** (1) flat phases of the rescued sim (above); (2) kill-map visibility on a real photo; (3) the `description` in the JSON now mentions the glow and the luma kill map.

---

## 2. radiating-haze (2nd pass)

**KEEP VERBATIM held:** HSV neutral rule incl. brown band (the neighbour taps use an equivalent channel-comparison form, see below), `satThresh = z·0.4+0.2`, 1-texel corona (Idea 1), cursor-origin waves `origin = mix(0.5, mouse, 0.85)` (Idea 2), `aura` formula, roles of the four sliders. **Deliberate deviations from "persist = max(prev·0.92, aura)":** `aura` → `auraTot = aura + haloAura` inside the `max` (the halo has to persist too), `prev` is read from the advected position (card idea 2), trail weight 0.3 → 0.4 (the drifting trail was below visibility at 0.3 — see Idea 4), and `max(hdr, 0)` before `aces()`.
**A packing:** raw `(persist, auraTot, strongMask, 1.0)` — A.a stays a hard 1.0 as the card says; header corrected to "A.g aura (halo included)". Display ACES RGB on `writeTexture`, alpha semantic (now uses `auraTot`).

### Rescue 1 (ring frequency) — CONFIRMED
HEAD `sin((dist − t·speed)·15)` with the aura clipped at `dist < radius+0.08` = 0.155 uv at default: 15 rad/uv → 0.37 of a wavelength inside the disc; on the saturated scene HEAD at t = 2 s shows no ring structure at all (barely any aura; `hz/crop576.png` left panel), while the final shows ring arcs lighting the rims of the red/blue discs and halo glow outside the blue/green ones. Fixed to **80 rad/uv** (2 rings in the default disc, disc size and front speed untouched). Visibility (below) ≈ 2.1 % of the frame / 28 % of the disc — it is the largest visible change of the file, i.e. the **default look changes**: a pulsing blob becomes concentric rings.
Evidence caveat: the stock harness photo is almost desaturated, so HEAD showed *no* aura at all; I built `mr_sat.mjs` (same harness, source = tinted ramp + six saturated discs near the pointer) and report on that scene. Numbers on a real photo scale with its saturated area near the pointer.

### Ideas (header: `Ideas: … source-hue halo gather (energy-conserving bloom, §12.2F); outward-advected persistence (native)`)

| What | Where (`radiating-haze.wgsl`) | §12.2 row |
|---|---|---|
| Idea 3 (= card idea 1) source-hue halo gather | `strongOf` L47-58, gather L113-148 (8-tap golden-angle disc, radius 0.016·height), `haloAura`/`rimDonate` L146-147, `auraTot` L149, composite L176-179 | energy-conserving bloom (F) |
| Idea 4 (= card idea 2) outward-advected persistence | L151-173: history read at `pixel − dirUV·(speed·0.7/60)·res` (exact `textureLoad`, texel centres, clamped, 4-tap hand lerp behind a 1-tap probe), trail weight 0.4 | native |
| Rescue 1 | L100-106 | — |

Idea 3: neutral pixels beside a coloured object receive that object's hue (`haloAura = (1−strongMask)·haloW·waveMask·depthGain·intensity·1.3`); the strong pixel gives up `0.25·(1−haloW)·waveMask·intensity` of its source (energy moves). The pixel's own neutral rule still holds (`aura = strongMask·…` unchanged); both outputs are ∝ waveMask so the gather runs only where waveMask > 0.002.
Idea 4: the persisted ring now travels outward at 0.7× the ring-front speed (assumes 60 fps; slower at low fps — documented in the comment).
**Strengthening that was needed:** first constants gave 2.3 % (halo) and 0.7 % (trail) of the disc; raised (halo radius 0.016·height, gain 1.3, rim donate 0.25, drift 0.7×, trail weight 0.3→0.4) to the numbers below. Still modest: the aura is a 7.5 %-of-frame disc by design.

**Visibility (ablations: gain→0 / drift→0 / freq→15; % px |Δ| > 0.02 / mean|Δ|; default sliders 0.5,0.6,0.4,0.5, pointer at 0.4,0.6, saturated-disc scene, 40 f, t_end 2 s; "disc" = r < radius+0.08 around the ring origin = 7.5 % of the frame):**

| size | Rescue 1 (ring freq) whole / disc | Idea 3 halo whole / disc | Idea 4 trail whole / disc | all vs HEAD whole / disc |
|---|---|---|---|---|
| 192 | 2.14 % / 28.4 % | 0.62 % / 8.2 % | 0.61 % / 8.1 % | 3.96 % / 52.5 % |
| 576 | 2.13 % / 28.2 % | 0.58 % / 7.7 % | 0.57 % / 7.6 % | 3.33 % / 44.2 % |
Alpha |Δ| > 0.02 in the disc: halo 6.3 % (192) / 4.9 % (576); trail 1.0 % / 0.9 %. Moving cursor (MPATH 0.3,0.5 → 0.6,0.6, 60 f): all vs HEAD 3.8 % whole / 30.9 % of the disc. **Both ideas are 8 % of the pointer region and ~0.6 % of the frame — below the "several percent of the frame" target; I could not raise them further without turning the aura into a whole-image glow (forbidden) or changing the neutral rule (forbidden).** The trail idea's alpha footprint is only ~1 %.
Slider/audio/A16 at pixel level vs base (192, 40 f): speed 0/1 → 4.1 / 5.1 %; intensity 0/1 → 4.5 / 3.7 %; **sat threshold 0/1 → 0.24 / 0.27 %** (the scene's discs are all strongly saturated and the background is below the threshold range, so this slider barely acts *in this scene*; static dead-slider audit passes); radius 0/1 → 4.1 / 6.4 %; audio (0.8,0.5,0.9) 2.6 %; moving cursor 5.5 %; `A16=1` 0.00 % (identical); nan 0.

**Default-look change (meanL/stdL/meanA, 576 px, saturated scene):** HEAD 0.447 / 0.072 / 0.402 → new 0.448 / 0.072 / 0.403 — whole-frame statistics barely move because the change is confined to the 7.5 % disc (where the mean |Δ| is 0.024-0.026). Idle vs held are identical (haze has no `down` input; the pointer position alone sets the origin).

**Cost (honest, not clean).** First pass (new/HEAD 1.4-2.6× in unpaired runs) led to: halo gather skipped where `waveMask ≤ 0.002`; trail lerp skipped unless a 1-tap probe sees history; and a second trim: per-tap `rgb2hsv` replaced by an equivalent channel-comparison neutral test (`strongOf`; the brown band 0.08 < h < 0.15 is only reachable with R as max channel and G ≥ B, where h = (g−b)/(6d), so the test is (g−b)/d ∈ (0.48, 0.9)) and per-tap `cos`/`sin` replaced by incremental rotation by the golden angle. The trim changes the picture by max 1.7e-5 (192 px, 40 f). Timing on this machine was load-noisy (load average 5–60; the min-of-drained-frames unpaired 4-round runs gave 0.9 … 2.2×). A harness copy (`mr_perf2.mjs`) alternates HEAD and new frame by frame in one process with separate A/C textures: **576 px, 40 frames, 4 runs, new/HEAD per-frame median 1.20, 1.30, 1.16, 1.37 (pre-trim 1.23); head-vs-head control runs gave 0.84, 0.90, 1.11, so one run is ± 15 %**. Ablations (halo off, trail lerp off, both off) all measured 1.1-1.3× and could not be separated from the noise, so I could not point to one hot spot. **Estimate ≈ 1.25×, at the edge of the 1.3× cap; the coordinator should re-time alone.** Structural expectation: ~4.5 % of the pixels run 8 taps, ≈ + 10-20 %.

**Open:** (1) cost right at the cap, not located; (2) visibility is 8 % of the pointer disc; (3) the 60 fps assumption in the trail drift; (4) sat-threshold slider hardly acts on the harness scene.

---

## Gates (final state of both files)
`wgsl_precommit_gate.py` 1/1 passed for each; `verify-naga-wasm.mjs --files` both valid (0 known, 0 new); `audit:dead-sliders -- --files radiating-haze` / `reaction-diffusion`: 0 new; `audit:extrabuffer`: 0 new violations. NB: running these audits rewrites `reports/dead_sliders_audit.*`, `reports/extrabuffer_write_audit.*` and `reports/wgsl_precommit_report.json` in the worktree (they show as modified for every fork) — I did not edit them by hand; the coordinator owns them.
`public/shader-lists/*`, `src/contracts/*`, search index, ledger: untouched.
