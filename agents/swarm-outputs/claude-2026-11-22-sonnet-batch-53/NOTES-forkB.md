# NOTES — fork B (neural-raymarcher, neural-raymarcher-gabor)

Harness: stock `mr.mjs` leaves `extraBuffer[0..132]` zero (only plasmaBuffer carries audio), which hides HEAD's extraBuffer audio reads. `agents/mrb.mjs` (my copy; env `AUDX=<fft value>`) writes audio into `extraBuffer[0..2]` and FFT bins `[5..132]` like the engine. Scratch: `/tmp/claude-0/-root-image-video-effects/0808efa3-e4d2-4c02-b58e-093c2450d257/scratchpad/b/` (`sheet1.png` HEAD defects, `sheet_final.png` HEAD vs NEW at defaults, `sheet_portal3.png`, `sheet_g2.png`/`sheet_g3.png`). Both files: 256 px, saved defaults, mouse 0.5,0.5, audio 0.3,0.2,0.1, `SRC=img` unless noted (`SRC=tex` = oriented gratings, used for the ablations).

## neural-raymarcher

**Idea Card (as shipped).** IDENTITY: the photo seen through a 5-shell zoom/flow march whose marched depth sets chroma split, rim glow, action-potential wavefronts and fog. KEEP VERBATIM: the 5-layer march (layerSpeed mix(p1,p2), sawtooth zoom, vortex spin, 0.015 flow noise, weights), param roles (p1/p2 near/far layer speed, p3 glow, p4 fog density), Ideas 1+2 (marched in-scatter, action-potential wavefronts), `calculateVolumetricAlpha`, ACES on display, `writeDepth = baseDepth`. ADD: Idea 3 firing-shell portal; Idea 4 depth-crease occlusion (§12.2E Step-count AO). FORBID: springs/ripples/IQ palette, second march, Fresnel/thin-film.

**A packing:** unchanged — A unused, C never read (nothing to load).

**Rescues (all change the default picture — loud):**
- R1 audio: HEAD `chroma = extraBuffer[0]` (engine bass 0..1) used raw as a UV offset × depth, `clickIntensity = extraBuffer[10]` (FFT bin 5). Proof: `mrb.mjs AUDX=0.5` on HEAD gives frame-sized ghost discs (`sheet1.png` row 1); silent HEAD has chroma 0 (the `0.02` fallback never runs). Now `plasmaBuffer[0].xyz`: bass → chroma ≤ 0.02·depth, mids → vortex. Silence = HEAD silent. Audio path alive: audio 0 vs 1 changes 80% of pixels (max 142/255).
- R2 edge glow inverted: `exp(-depthGrad·30)·depth·2` is a +2·depth *fill* on smooth depth and vanishes at steps; `depthGrad` was also measured against the marched average depth. Proof (before any edit): HEAD meanL 0.802; same file with `edgeGlow = 0` meanL 0.512; with ACES→clamp 0.908 (ACES is not the cause). Now the gradient comes from the central differences `reconstruct_normal` already takes (`|n.xy|/n.z`, no extra fetch), the glow is a rim `smoothstep(0.01, 0.1, grad)`, scaled `(0.5 + p3)` (default p3 0.5 = HEAD's ×1 amplitude). Side effect, intended: `membrane` (Idea 2) now peaks where depth really steps, as its comment always claimed.
- **Default look change:** meanL 0.802 → 0.509 (stdL 0.119 → 0.176), 99.9% of pixels differ > 2/255 (washed-out fill gone, photo visible, rim rings, crease shadow).

**Ideas in the diff:** Idea 3 `// ── Idea 3: firing-shell portal` (`shellTail`, `portal`, `shellColor`): ablation on SRC=tex changes 30–33% of pixels (max 40–53/255); the first version (sharp spike × 0.75) changed only 0–4% and was widened. Idea 4 `// ── Idea 4: depth-crease occlusion` (`occDir`, 3-tap loop, `ao`): ablation changes 9.75% of pixels (max 81/255) at defaults. Convention: catalog depth is DPT inverse depth (1 = near, per `atmos-fog-volumetric.wgsl`), so occluders are the higher texels, direction = −n.xy.

**Timing (interleaved `mr_ab.mjs`, 256, 8 cycles, load 10–26 from other forks):** ratio min 0.96, p25 0.95, paired-median 0.62 (noisy; an earlier 6-cycle run at load 26 read min 1.27 / paired 1.61). Net fetches are +2 (AO +3, centre +1, depthX/Y −2); coordinator should re-time on a quiet box.
**Gates:** precommit 2/2, naga-wasm 2/2, dead sliders 0 new, extraBuffer 0 violations (the file no longer touches extraBuffer). NaN 0 across slider/mouse/audio extremes (`p=0..1`, mouse corners, audio 0..1.5).

## neural-raymarcher-gabor

**Idea Card (as shipped).** IDENTITY: the same 5-shell neural march with a four-orientation Gabor bank over it, orientation-palette coloured; alpha = dominant orientation magnitude. KEEP VERBATIM: march/chroma/fog (glow slider = fog density here), 4 orientations + mouse-angle/camera-rotation offset, freq 0.125, σ from mouse x and gain from mouse y (legacy advanced params on zoom_config.y/z), quadrature energy (Idea 1), Heeger normalisation (Idea 2), per-orientation IQ palette (native to the analyzer chunk), activationVis blend, ACES, alpha semantics, A unused. ADD: Idea 3 Gabor phase colouring (`sin φ = odd/energy` rotates each palette's phase by up to ±0.12, energy-gated); Idea 4 iso-orientation surround suppression (surround bank = same taps ×2.5 spacing, carrier kept at 0.125 cycles/px; `gaborColor = mix(gaborColor, foggedColor, 0.65·iso·gate)`).

**A packing:** unchanged — A unused, C never read.

**Rescues (change the default picture — loud):**
- R1 audio, same as the sibling (plasmaBuffer; `audio-reactive` added to JSON features because it is now true; audio 0 vs 1 changes 50% of pixels).
- R2 rim: same fix as the sibling (no glow-slider scaling — `glow` is fog density in this file). `viewDotNormal` was computed and never used; removed.
- R3 zero-mean even kernel. Proof on HEAD: a perfectly flat source gives meanA 1.0 for both 0.2 and 0.8 grey, colour differs with brightness (meanL 0.512 vs 0.626) — Σg·cosφ ≈ 5.7 at σ = 2.5 so every channel measured brightness. After: flat source meanA 0 (both greys), alpha is a real orientation magnitude (default img meanA 0.967 → 0.431). `const ZERO_MEAN` (1.0; 0.0 restores HEAD).
- R4 (perf, pixel-identical): one 9×9 pass for all four orientations (shared luma taps and shared isotropic Gaussian; HEAD's Gaussian never depended on θ). Verified before enabling R3: max diff 1/255, 0.0% of pixels > 1/255 vs HEAD+R1+R2.
- **Default look change:** meanL 0.508 → 0.384 (stdL 0.097 → 0.105) at saved defaults, 100% of pixels differ; the saturated rainbow-by-brightness is gone and the photo/gratings show through under an orientation-coloured overlay.

**Ideas in the diff:** Idea 3 `// ── Idea 3: Gabor phase colouring` (`sinPhi`, `phShift`; ablation on SRC=tex changes 95% of pixels, mean 16/255 — the overlay covers the frame at Activation = 1; amplitude was cut from 0.2 to 0.12 after the first version reshuffled every hue). Idea 4 `// ── Idea 4: iso-orientation surround suppression` (`surround`, `iso`, `surroundGate`): on SRC=tex the centre block and quadrant seams stay vivid while uniform gratings relax to the photo (`sheet_g2.png`); ablation changes 92–100% of pixels (it is a global gain on the overlay, concentrated on uniform texture). A first Idea 4, coherence-gated fibre smear along the stripe tangent, changed 0.06% / 0.0% of pixels and was dropped.

**Timing (interleaved, 256, 8 cycles, load ~10):** ratio min 0.79, p25 0.82, paired-median 0.82 (324 fetches → 2×81; frameMs HEAD ~290–500 vs NEW ~230).
**Gates:** precommit 2/2 (with the sibling), naga-wasm 2/2, dead sliders 0 new, extraBuffer 0 violations. NaN 0 across extremes.

## Open calls / not verified
1. **Fog polarity (not changed).** Catalog depth is DPT inverse depth (1 = near) but both files fog with `exp(-depth·density·3)`, i.e. nearer = foggier. In the gabor file `glow` (default 0.5) therefore fades near objects into the navy by default; in neural-raymarcher the fog slider is p4 (default 0, so invisible by default). Left alone because it is a look/semantics call across Ideas 1 and the volumetric alpha; flipping to `exp(-(1-depth)·…)` is a one-line change per file.
2. **neural-raymarcher slider roles are template leftovers**: `camera_rotation` (p4) is fog density, `network_depth`/`activation_vis` (p1/p2) are near/far layer speed — saved ids/names/defaults/roles untouched, per the contract.
3. **Zoom sawtooth pop**: every layer's `fract` zoom snaps every 1/speed s (2 s at defaults, all five layers identical at p1 = p2); the marched depth (and so chroma, spike phase, fog) jumps with it. A two-phase crossfade would double the march; not done.
4. **Gabor kernel support** is capped at ±4 taps while σ goes to 4 (mouse x), so large-σ kernels are truncated at ~0.35 of peak; the elongated-envelope idea was dropped for the same reason.
5. Not verified: any real-GPU look; real photos (only the synthetic harness photo and the oriented-grating pattern were used); the portal band is subtle on smooth photos (its source layer is a magnified copy of the same smooth image).
