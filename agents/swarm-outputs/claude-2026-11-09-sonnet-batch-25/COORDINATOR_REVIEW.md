# COORDINATOR_REVIEW — sonnet/batch-25 (optical: crystal / glass / bead / lens / frost), 2026-11-09

Branch `sonnet/batch-25` in `/root/iv-sonnet-batch-25` (from origin/main 53d939ec). Commit 67bc2312 = prelude migration (6 files, header-only, no `Upgraded:` bump); ideas/rescues commit follows. 4 forks (A 3, B 3, C 2, D 2) + 2 unanchored read-only reviewers (5 shaders each) + one fix round (forks A, B, D resumed; C needed none).
All visual evidence is SwiftShader (minirender, `A16=1` for rgba16float emulation). **No real-GPU visual QA.**

## Pass / fail against the cards (§9 checklist)
| id | pass | cards before WGSL | each idea pointable | KEEP VERBATIM held | A packing truthful | saved params byte-exact | springs/ripples native | naga/extraBuffer/dead-sliders |
|---|---|---|---|---|---|---|---|---|
| glass-bead-curtain | PASS | yes | 3 `// ── Idea` | yes (bead curtain, 4 sliders, semantic alpha, 2 % C ghost) | yes (A texels (0,0),(1,0) = state, masked on C read) | yes | spring+ripples already owned by HEAD | ok |
| glass-bead-curtain-iridescence | PASS | yes | 3 | yes | yes (same scheme) | yes | spring already owned | ok |
| chroma-lens-iridescence | PASS | yes | 3 | yes (lens orbit idle / follow while held kept) | yes | yes | spring already owned | ok |
| crystal-illuminator | PASS | yes | 4 | n/a — HEAD never compiled; intent kept (cursor = lamp, facets, transmission alpha) | ACES display RGBA, C not read | yes | click front re-expressed per facet (HEAD had it) | ok |
| crystal-mosaic | PASS | yes | 3 new (+2 kept) | yes (crease, lead came) | ACES display RGBA | yes | cursor lamp is native (cursor already drove rotation/SSS) | ok |
| crystalline-shatter | PASS (ideas subtle by nature, see below) | yes | 2 new (+3 kept) | yes | ACES display RGBA, C not read | yes | n/a | ok |
| glass-wall-prismatic | PASS | yes | 3 | yes | yes (A-texel state, masked) | yes | spring/click impulse already owned | ok |
| gen-depth-refracted-liquid-stained-glass | PASS | yes | 3 new (+4 kept) | yes | A/C = ACES display RGBA + tint history | yes | n/a | ok |
| frost-reveal-crystal | PASS | yes | 3 | yes (mask/phase/orientation/impurity packing) | raw sim state in C/A + sentinel in texel (0,0) | yes | pointer melts frost — native | ok |
| chromatic-mosaic-projector | PASS | yes | 3 new (+2 kept) | yes | pre-ACES display RGBA trail | yes | click ring already in HEAD | ok |

## Formula rows (§12.2) per file and batch de-dup (§12.4)
| row | files |
|---|---|
| Fresnel–Schlick (F) | glass-wall-prismatic (bevel sheen; HEAD's Fresnel only reached alpha) |
| Snell vector refraction (F) | crystal-illuminator |
| Beer–Lambert (F) | gen-depth-refracted-liquid-stained-glass |
| Thin-film phase (F) | glass-bead-curtain-iridescence, chroma-lens-iridescence (both extend a thin-film HEAD already had) |
| Cauchy dispersion (F) | chroma-lens-iridescence, crystalline-shatter; **plus** glass-wall-prismatic's lamp lobe, which reuses the file's own pre-existing `cauchyB` basis (no new row claimed by the fork). Strictly that is 3 files touching Cauchy; accepted because the third consumes a quantity HEAD already computed and is not a new formula. Flagged for the record. |
| Energy-conserving bloom (F) | crystalline-shatter |
| Lens-flare ghost (F) | chroma-lens-iridescence (the batch's single ghost/Airy use) |
| Isotropic 9-point Laplacian (D) | frost-reveal-crystal |
| none (tactic-derived only) | glass-bead-curtain, crystal-mosaic, chromatic-mosaic-projector |
No row appears on more than two files except the flagged Cauchy case. No two files share both formulae. Generic-overlay check: the one HEAD overlay in the batch (crystal-illuminator's full-screen rainbow clock rings) was CUT, not copied; nothing stamped across files.

## Rescues (HEAD was broken) — default look changes are expected
- **Did not compile at HEAD** (both were on the naga knownFailures ratchet): glass-bead-curtain (`let target` reserved), crystal-illuminator (duplicate `let aspect`, `__finalRGB`). Both now compile; `src/contracts/wgsl_validation.json` ratchet 10 → 8 at the branch point (9 → 7 after rebasing onto #1650, which removed `recursion-mirror-vortex`) and `npm run verify:naga-wasm -- --all` passes.
- **Dead `extraBuffer[133..138]` springs/impulses** (zeroed every frame; single-writer-at-(0,0) race — in the real app the "smoothed" cursor was raw/(0,0)/nondeterministic, minirender hid it): glass-bead-curtain, glass-bead-curtain-iridescence, chroma-lens-iridescence, glass-wall-prismatic, frost-reveal-crystal. Four moved to A-texel state with the 0.7371 sentinel, shared dt, f16 rest-snap; frost-reveal-crystal's spring was removed honestly (raw cursor) and the sim got a sentinel re-seed.
- **Dead click ripples** (`r.w` always 0): glass-bead-curtain.
- Others per NOTES: glass-wall-prismatic white balance (flat tile was a red filter), frost-reveal-crystal growth was dead (seed 0.030→0.033 in 1200 frames; `anisotropy` did nothing), chromatic-mosaic-projector "edge" terms measured seed distance not border distance, crystal-mosaic pivot drift + dead radial chroma branch, bead-curtain 2-D normal / per-pixel depth-sheared lattice / missing Fresnel reflection, lens iridescence invisible (screen-centred film angle).

## Default-look changes (192 px idle, meanL / stdL / meanA, HEAD → now; see each NOTES for held/audio/576)
- glass-wall-prismatic .453/.148/.937 → .497 (chroma .315 → .103): white-balance rescue, intended.
- gen-depth .415/.128/1 → .378 (chroma .152 → .179): modest, from Beer–Lambert/wisps.
- glass-bead-curtain-iridescence .527/.157 → .536/.156 (after review fix; first pass .566/.121 was a milky wash).
- chroma-lens-iridescence .535/.160/.386 → .545/.144/.394 (stdL −0.016 from film tint + Cauchy fringe; not touched in review round).
- crystal-mosaic .480/.185/.971 → .472/.186/.970; crystalline-shatter .492/.166/1 → .504/.158/1.
- frost-reveal-crystal .516/.166/.369 → .535/.150/.408 (cold start; HEAD never seeds at T0=2, so this is the seed rescue).
- chromatic-mosaic-projector .257/.114/.736 → .226/.109/.671 (≈ 12 % darker: more of the image is near a border than near a seed).
- glass-bead-curtain / crystal-illuminator: no HEAD look exists; compared against compile-fix-only scratch copies (bead .297 → .444, illuminator .359 → .377).

## Unanchored review (2 fresh agents) — triage
Verified before acting; all fixed unless noted. Each fix re-measured by the owning fork.
- glass-bead-curtain: **click latch** (held-pull used `u.config.y` = ripple COUNT, which never decays → pull stuck at 1 after the first click; verified in `frame.ts:251` + `WebGPURenderer.addRipple`) → alive-ripple scan; 3 s after a click the render equals the no-click render (1.8e-7, was 33 % of pixels). **bass inside a time-multiplied phase** (HEAD, 39.9 % of pixels per 0.01 bass → 0.76 %). Unbounded swing wake vs the 3×3 bead search → clamp 0.9 bead. Thread kink across bead borders → per-column sway phase. glass-bead-curtain-iridescence: wake clamp folded the lattice map (Jacobian) → 0.04; contact-fringe hash seam → continuous field; milky wash was mostly the fringe → luma-matched film (stdL .121 → .156). chroma-lens-iridescence: lensVel clamp ±3; internal-reflection ghost was invisible (0.5 % of pixels >0.02) → soft knee, now 7.1 % / max 0.126.
- crystal-mosaic: cursor lamp had unbounded reach (idle cursor re-lit 28 % of the frame) → `smoothstep(0.55,0.10,d)` falloff (far-field 0.4 %), Mouse Influence slider no longer dead 0.75→1; aspect-corrected influence zones here and in crystalline-shatter. crystalline-shatter: halo raised (removal now changes 12.9 % of pixels >0.05 on the default photo).
- chromatic-mosaic-projector: **inherited-C poison** (HEAD) → validated history + clamped feedback alpha (50s / NaN / Inf / 1e30 now render like a clean run); lattice distort soft-capped (3×3 vs 7×7 mismatch worst case 44 % → 3.6 %); fringe frequency follows on-screen cell size. frost-reveal-crystal: seed shrank at Growth Speed 0 → diffusion scales with reaction; NaN-safe `select()` gating.
- **Declined (documented):** crystalline-shatter `cellScale·(1+bass·0.5)` re-hash — pre-existing and written into its JSON description ("Bass pulses crack new cells"); Cauchy sign convention note (convention-dependent, unverifiable); a 5×5 Voronoi search in the projector (cost). Left as known: state-texel shaders share SENT 0.7371, so a direct switch between two of them adopts the other's (0,0) state for ≲0.5 s and self-heals (documented in batch-24).
- Process slips: forks A and B each ran `git checkout -- reports` once against the no-git rule (touched only tracked audit-report noise; no WGSL/JSON/notes affected).

## Timing (SwiftShader, sequential back-to-back, load ≈ 1–2; frameMs, HEAD → now)
256 px, 3 rounds: frost 14→17, projector 14→19, shatter 17→18, bead-iridescence 16→20, wall 15→16, lens 14→15, gen-depth 11→12, mosaic 11→11. 512 px, 5 rounds, medians: projector 52→61 (1.17×), **frost 47→62 (1.32×, over the ~1.25× guideline)**. Accepted: both are light shaders, the frost increase is the new forward-scatter taps + 9-point stencil loads; absolute cost is small. Re-time on a real GPU if the budget matters.

## Open items
- Thumbnails stale for all 10 (refresh on a GPU machine via the Shader Scanner → "Changed since last thumbnail").
- Every A-texel state scheme and the ripple path verified by emulation only (no real rgba16float / no real clicks): re-check bead curtains, lens, glass-wall and frost on hardware.
- Tuning constants judged on the synthetic photo: illuminator TIR share/slab thickness, mosaic chamfer width and lamp height, lens ghost/fringe strength, bead thread opacity, grisaille line (stair-steps on hard synthetic depth; real depth is soft).
- frost-reveal-crystal: crystals never thaw (field eventually fills beneath the frost); hex plates not dendrites.
- chroma-lens-iridescence stdL still ~0.016 under HEAD at idle; crystalline-shatter Cauchy idea only shows on sharp edges (13.6 % on an edge-rich source vs 0.3 % on the default photo).
