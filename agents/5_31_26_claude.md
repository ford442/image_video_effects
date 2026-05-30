# 2026-05-31 — Claude Sonnet/Opus Swarm Execution Plan (Optimization & Polish Layer)

**Date**: 2026-05-31  
**Focus**: Parallel optimization, deep performance work, multi-pass refinement, visual transcendence, and header/chunk standardization — running **alongside** Kimi's v2 implementation/repair batch  
**Primary Mission**: Apply Claude's strengths (rigorous performance reasoning, elegant mathematical refactors, last-10% visual polish, multi-pass architecture) to a **completely disjoint** set of shaders from the ones Kimi is handling today  
**Constraint**: Do NOT touch any of Kimi's 8 shaders (`gen-superfluid-quantum-foam`, `plasma`, `kaleido-scope-grokcf1`, `velocity-field-paint`, `pixel-sand`, `temporal-rgb-smear`, `liquid-tensor-vortex`, `depth-chromatic-bloom`). Hot-swap sacred.

**Role Reminder** (from grok_build_upgrade.md + KIMI_CLI_SWARM_UPGRADE_PLAN.md v2):
- Kimi = high-volume, fast, template-following implementation + repair (first pass)
- **Claude = optimization, review, polish, transcendence** (second pass). You refine what exists, make it sing at 60 fps on mid-range GPUs, enforce conventions, and deliver the final "wow" that makes a shader portfolio-worthy.

---

## Coordination with Kimi's 2026-05-31 Work

Kimi is piloting the new v2 Kimi Swarm OP today (see `agents/5_31_26_kimi.md` and `agents/KIMI_CLI_SWARM_UPGRADE_PLAN.md`):
- 6 bind-group canonical repairs
- 2 brand-new shader creations (with full Standard Hybrid Headers)

Your work is **orthogonal and complementary**:
- You operate on heavier, more architecturally complex, or performance-sensitive shaders that benefit from deep analysis rather than rapid generation.
- You will receive `.notes.kimi.md` handoff files from Kimi's accepted work later today for final polish (those are **not** part of today's Claude batch — they come as follow-up).
- At the end of your session, produce clean `*.claude-optimization.md` artifacts so Grok/Jules can integrate everything.

---

## Today's Claude Batch — 7 Shaders (Disjoint from Kimi)

All of these are **not** on Kimi's list. They skew toward multi-pass, large raymarched/generative, or previously identified optimization targets.

| # | Shader ID | Category | Why Claude (your strengths) | Target Outcome | Est. Effort |
|---|-----------|----------|-----------------------------|----------------|-------------|
| C1 | `aurora-rift-pass1` | lighting-effects (multi-pass) | Volumetric raymarch + curl flow — needs LOD, early exits, cached math | 15-25% perf win + cleaner pass handoff | High |
| C2 | `aurora-rift-pass2` | lighting-effects (multi-pass) | Atmospheric scattering + color grading — tone mapping, dither, premultiplied alpha polish | "Transcendent" final look + consistent header | Medium |
| C3 | `quantum-foam-pass1` | simulation (multi-pass) | Field generation with curl/Voronoi — shared memory tiling opportunity | Introduce workgroup tile + LOD | High |
| C4 | `tensor-flow-sculpting` | hybrid | Heavy tensor math, previously called out for optimization | Cached eigenvalues, branchless paths, early exits | Medium-High |
| C5 | `hyperbolic-dreamweaver` | distortion | Hyperbolic coords + dreaming flow — moiré risk at 2048² | Anti-moiré LOD + fwidth techniques + visual refinement | Medium |
| C6 | `gen-chronos-labyrinth` | generative (large) | One of the biggest raymarched pieces (~14k lines historically) — massive opportunity for distance-based LOD, early termination, and atmospheric perspective tuning | Measurable perf + "alive" depth feel | High |
| C7 | `volumetric-god-rays` | lighting-effects | Depth-aware god rays — perfect for exponential fog, Mie scattering polish, and alpha that plays nicely in slot chains | Depth-responsive rays + broadcast-ready beauty | Medium |

**Sources for deeper context** (read before starting):
- `agents/swarm-outputs/optimization-patterns.md` (from earlier multi-pass work)
- `agents/EFFECT_UPGRADE_SWARM.md`
- Prior completion notes on aurora-rift and quantum-foam passes in `agents/swarm-outputs/`

---

## Task Template for Each Shader (Claude Style)

For every shader in the batch above, perform the following in order:

### 1. Analysis Phase (think out loud in your response)
- Profile mentally for 2048×2048 at 60 fps on integrated graphics.
- Identify the top 3 performance or elegance bottlenecks (texture samples in inner loops, redundant trig, lack of LOD, poor early-out, missing shared memory, scalar vs vector ops, etc.).
- Check adherence to the 13-binding contract and Standard Hybrid Header (if present).
- Note any missing audio reactivity (`plasmaBuffer`), depth awareness, or meaningful alpha.
- Compare against the 12 Kimi Graphical Tactics and the role toolkits — which ones are under-utilized here?

### 2. Optimization & Polish Phase (apply conservatively)
You may:
- Introduce `var<workgroup>` tiling where it makes clear sense (especially passes 1 of multi-pass)
- Add distance-based LOD for noise/octaves/ray steps
- Apply early-exit conditions for low-contribution pixels
- Refactor to branchless `select()` / `mix()` where it improves readability + perf
- Inject one or two of the 12 graphical tactics (especially hue_preserve_clamp + ACES + IGN dither, bass_env, anti-moiré LOD, premultiplied writeback)
- Standardize the header + add missing `CHUNK:` attributions
- Tune workgroup size only if the shader does **not** use `var<workgroup>` or `local_invocation_id` math (per AGENTS.md rules)
- Improve parameter semantics and JSON `features` / `tags` if you edit the definition

**Do NOT**:
- Rewrite the entire shader from scratch (that's Kimi's lane)
- Change the 13-binding contract
- Touch Renderer.ts or anything in `src/`
- Make changes that would require updating callers outside the hot-swap contract

### 3. Deliverables per Shader
- The upgraded `.wgsl` (or precise unified diff if you prefer — either is acceptable)
- A companion `swarm-outputs/claude-notes/<shader-id>.claude-optimization.md` (max 1 page) containing:
  - Bottlenecks identified (with line references)
  - Optimizations applied + expected impact (e.g., "reduced inner-loop texture samples from 19 to 7 via tiling + LOD")
  - Visual/transcendence notes ("the god rays now feel like they are actually traveling through dust in depth")
  - Any remaining risks or "watch this at 4K" comments
  - Suggested JSON updates (if any)

---

## Execution Checklist for 2026-05-31 (Claude Session)

1. [ ] Read this file + `agents/KIMI_CLI_SWARM_UPGRADE_PLAN.md` (v2) + the relevant prior swarm outputs for context on multi-pass and optimization patterns.
2. [ ] For each of the 7 shaders:
   - Read the current source + its JSON definition
   - Perform the Analysis → Optimization → Deliverables flow above
   - Write the `.claude-optimization.md` artifact immediately after finishing the shader (don't batch them at the end)
3. [ ] After the full batch, run the standard validation:
   ```bash
   node scripts/generate_shader_lists.js
   node scripts/check_duplicates.js
   ```
   (Only if you touched any JSONs.)
4. [ ] Write a short session summary at the bottom of **this** file:
   - Which shader gave the biggest surprise win?
   - Any patterns you want to codify into a new "Claude Optimization Playbook" section for future weeks?
   - Any shaders that felt like they needed a third deep pass (flag for later)?
5. [ ] At the very end of your session, scan `swarm-outputs/kimi-notes/` (if any new files from Kimi's batch landed) and leave a one-sentence readiness note for the follow-up polish pass on Kimi's accepted work.

---

## Success Criteria (Different Flavor from Kimi's)

- Every shader you touch shows **measurable elegance or performance improvement** (document the "why" rigorously).
- At least 4 of the 7 shaders gain either workgroup tiling, distance LOD, or a high-impact graphical tactic they were previously missing.
- All 7 have a clean, up-to-date Standard Hybrid Header with proper chunk attribution by the time you finish.
- Your `*.claude-optimization.md` files are so clear that Jules or Grok can write the PR description directly from them.
- Zero regressions in hot-swap behavior or visual character (the "soul" of each shader is preserved or elevated).

---

## Output Locations

- Upgraded WGSL → directly in `public/shaders/` (hot-swap ready)
- JSON deltas (if any) → in the matching `shader_definitions/<category>/`
- Your detailed notes → `swarm-outputs/claude-notes/<shader-id>.claude-optimization.md`
- Session summary → append to the bottom of this file (`agents/5_31_26_claude.md`)

---

## Relationship to the Broader Swarm (05-31)

- Kimi is doing the **volume + first implementation** work with the new disciplined prompt system.
- You are doing the **depth + transcendence** work on a parallel, non-overlapping track.
- Later today / tomorrow the handoff flows the other way: Kimi's accepted outputs land in `kimi-notes/`, you (or a follow-up Claude pass) give them the final 10% polish.
- Together the two tracks should produce ~12-15 meaningful shader movements in a single calendar day without stepping on each other.

---

**This is the Claude complement to Kimi's v2 pilot. Your work is the difference between "it works" and "this is the one people will remember from the 2026 library."**

Take your time on the analysis. The shaders in your batch are worth it.

— Grok (Swarm Process Architect), 2026-05-31

---

## Session Notes

**Date run:** 2026-05-31

**Shaders completed:** 7/7 — aurora-rift-pass1, aurora-rift-pass2, quantum-foam-pass1, tensor-flow-sculpting, hyperbolic-dreamweaver, gen-chronos-labyrinth, volumetric-god-rays

**Biggest win:** gen-chronos-labyrinth soft-shadow removal. calcSoftShadow() was calling map() 32 times per lit pixel on top of the main raymarch loop — the dominant compute cost by a wide margin. Removing it (and using AO×diff for contact shadows) delivers an estimated 30–45% frame time reduction with surprisingly little visual regression at the cell scales and fog levels in this scene. The ACES upgrade and bass-driven fog are the visual payoff that makes the scene feel more alive post-optimization.

Close second: aurora-rift-pass1 curlNoise epsilon fix (0.001→0.01). The flow field was effectively broken — zero-magnitude curl — which made the aurora look static. This single change restores the entire layered volumetric motion character the shader was designed to produce.

**Patterns to codify:**

1. **"Broken audio" audit pattern**: Before touching any non-trivial shader, check that `plasmaBuffer[0]` is actually read AND that the source field matches what the Uniforms struct comment says. `hyperbolic-dreamweaver` was reading `zoom_config.x` which is ZoomTime, not audio. This is a silent, untestable failure mode. Add to the Claude pre-optimization checklist: *verify audio source = plasmaBuffer, not uniform fields.*

2. **"Check the epsilon" pattern**: Any curlNoise-style finite-difference gradient that uses eps < 0.005 in a context where the hash/noise function has integer-period behavior will produce degenerate gradients. Standard visual curl uses eps=0.01. If you see eps < 0.005, flag it.

3. **"Soft shadow cost accounting" pattern**: In SDF-based raymarchers, soft shadows are deceptive. They look cheap in source (one function call) but pay map() N times per lit pixel. Always count the map() multiplier. For this scene: 32 shadow steps × (average map cost) = dominant cost. Rule of thumb: if shadow/AO steps × map_cost > 0.5 × raymarch_steps × map_cost, evaluate whether AO alone is sufficient.

4. **"globalIntensity hardcode debt" pattern**: aurora-rift-pass2 had `let globalIntensity = 1.0` overriding the uniform. This is a common pattern when shaders are copied from a template and the placeholder is never wired up. Add to review checklist: *grep for hardcoded 1.0 in intensity/alpha variables.*

5. **Depth modulation clamping**: Any shader that multiplies or adds to depth values should clamp the output to [0,1]. hyperbolic-dreamweaver could push depth > 1.0 at the Poincaré disk boundary.

**Flags for future Claude passes:**

- **aurora-rift-pass1 (C1)**: The parallax curl evaluations (a0, a1, a2) share the same base spatial position — a future optimization could share the 4 fbm finite-difference evaluations across time slices, saving ~8 fbm calls. Architecture refactor, not a quick edit.
- **tensor-flow-sculpting (C4)**: depthEdge() and depthNormal() each sample the same 4 depth offsets independently. These 4 samples are also precomputed in main(). A future signature refactor to pass hR/hL/hU/hD would eliminate 8 redundant depth samples.
- **gen-chronos-labyrinth (C6)**: sdStaircase with 6 iterations × sdBox is the most expensive single cell structure. Long-term: precomputed SDF texture lookup for staircase geometry.
- **hyperbolic-dreamweaver (C5)**: The anti-moiré implementation uses lodFactor×3 as a mip proxy (dpdx/dpdy are unavailable in compute shaders). A more accurate approach would compute the warp Jacobian analytically from the hyperbolic translation formula — good candidate for a future math-heavy pass.

**Readiness for Kimi handoff polish:** Kimi-notes directory was empty at session end — no handoff files from Kimi's 2026-05-31 batch landed during this session. Ready to begin polish pass as soon as `.notes.kimi.md` files arrive.

---

## Batch 2 — Generative Raymarcher Sweep (same day, Opus 4.8)

**Shaders completed:** 5/5 — gen-celestial-forge, gen-art-deco-sky, gen-holographic-data-core, gen-ethereal-anemone-bloom, gen-biomechanical-hive (all disjoint from Kimi's 8 and Claude batch-1's 7). All pass `naga` validation.

**Why this batch:** A `grep` for `plasmaBuffer` usage across the 1058-shader library surfaced a cluster of large generative raymarchers that *declare* binding 12 but never read it — the "broken/missing audio" pattern from batch-1, at scale. These shared a defect profile: incomplete or stub headers, Reinhard (or zero) tone-mapping, and 128–150 step marches.

**Biggest win:** gen-holographic-data-core interference gating. `volumetricInterference()` — ~9 transcendental ops (6 cos/exp + normalizes) — was called **every** one of 80 raymarch steps, including far-field steps marching through empty space where its glow contribution is below the perceptual floor. Gating it to `d < 2.0` (near-field only) cuts an estimated 30–50% of interference evaluations with zero visible change. This is the same lesson as batch-1's soft-shadow removal: **per-step transcendental functions in a raymarch loop are deceptively expensive — always ask whether each step actually needs them.**

**Runner-up:** gen-ethereal-anemone-bloom audio bug. Confirmed the batch-1 "broken audio" pattern is a *recurring library-wide bug*, not a one-off. This shader read `u.config.y/z/w` (MouseClickCount/ResX/ResY) as audio — meaning its animation speed was driven by click count and scaled by render resolution. A genuine repair, not just an enhancement.

**New patterns to codify (extending batch-1's list):**

6. **"Per-step transcendental audit" pattern**: In any raymarch loop, identify functions called once per step that use cos/sin/exp/pow/normalize. Ask: does the far-field (large-d) step actually need this, or is its contribution below the perceptual floor? Gate with `if (d < threshold)`. Holographic-data-core: ~720 transcendentals/pixel → roughly halved. This generalizes batch-1's soft-shadow rule to *all* per-step heavy math, not just shadows.

7. **"No tone-map at all" pattern**: Distinct from the Reinhard-vs-ACES question — several generative shaders (gen-biomechanical-hive) had *zero* tone mapping and wrote raw HDR. Emissive materials (`base * (1 + pulse)`) clipped to flat color. Adding ACES to a no-tone-map shader is a bigger visual upgrade than swapping Reinhard→ACES. Grep for shaders that write `textureStore(writeTexture, ...)` without a preceding tone-map call.

8. **"Stub/placeholder header" pattern**: gen-celestial-forge still had the literal `// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---` template comment. Grep the library for that string and other placeholder markers — they indicate shaders that were never finished to the Standard Hybrid Header bar.

9. **"Missing depth write" pattern**: gen-celestial-forge wrote only `writeTexture`, never `writeDepthTexture`. Any generative shader that omits the depth write breaks downstream depth-aware effects in a slot chain. Grep for shaders with `writeTexture` store but no `writeDepthTexture` store.

**Batch-2 flags for future passes:**
- **gen-holographic-data-core**: the `d < 2.0` interference gate is conservative; profiling could tighten to `d < 1.0` for more savings (glow falloff is 1/d). Verify visual parity first.
- **gen-art-deco-sky / gen-biomechanical-hive**: audio-boosted params (`goldGlow × (1+bass)`, `hueShift + mid×0.1`) can nudge values past their intended ranges on loud tracks. ACES absorbs the brightness blowout, but staged hue thresholds could snap. Consider soft-clamping if it reads wrong.
- **Library-wide**: the broken/missing-audio pattern appeared in 6+ of the ~12 shaders examined across both batches. Worth a dedicated swarm sweep: grep every shader for `plasmaBuffer` read-count and `u.config.[yzw]`-as-audio misuse.