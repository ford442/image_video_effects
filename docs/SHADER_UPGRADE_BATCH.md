# Shader Upgrade Batches — Incremental Ideas Contract

> **This is the live process.** Paste this file (or §0) into Gemini / Grok / Claude / Antigravity before a batch.
> Longer plumbing reference: [`agents/CLOUD_UPGRADE.md`](../agents/CLOUD_UPGRADE.md).
> Bindings / uniforms: [`docs/BINDING_CONTRACT.md`](BINDING_CONTRACT.md) and [`agents/WGSL_BUILTINS_GENERATIVE.md`](../agents/WGSL_BUILTINS_GENERATIVE.md).

---

## 0. Copy-paste law (put this at the top of every batch prompt)

An upgrade **adds 2–4 named visual ideas to the existing effect**. It is not a new shader, not a reimagining, and not a formatting / uniform-alignment pass.

1. **Write an Idea Card for every shader before touching WGSL.** If you cannot name the additions in one sentence each, you are not ready to edit.
2. **Keep the algorithm, the look, and the saved `params`.** Same modes, same kernel family, same identity. Deepen what is already there.
3. **Plumbing is the floor, not the upgrade.** Canonical 13 bindings, 16×16, ACES, semantic alpha, exact C loads, live sliders, and `updatedParams` alignment must happen — they do not by themselves count as an upgrade.
4. **No generic overlay.** Do not stamp every file with the same spring cursor, ripple shockwaves, IQ cosine palette, and two “conveyors.” Ideas must be native to *this* effect.
5. **Refuse a header-only or rewrite-only result.** A shader that newly compiles, writes depth/A, and looks the same is not upgraded. A shader whose name still matches but whose picture is a different effect is not upgraded either.

---

## 1. What “upgrade” means

The catalog is ~1,350 effects. Many already have a distinct identity: unsharp-mask sharpen, vignette, brush strokes, tile glitch, double exposure. The job is to make **that** picture richer — a new structure, a new motion, a new optical or tactile beat — while a viewer still recognizes the original effect in the first second.

| Kind of change | Counts as upgrade? |
|---|---|
| Two named, effect-specific visual ideas plus the contract floor | **Yes** |
| Identity preserved; kernel/mode/param roles kept; new detail is additive | **Yes** |
| Bindings, workgroup, ACES, alpha, `dataTextureA`, `updatedParams` only | **No** — that is hygiene |
| Full rewrite, new motif, renamed modes, or “premium version” of a different effect | **No** — that is a new shader |
| Same spring + ripple + oil-slick overlay on vignette, sharpen, and liquid | **No** — that is homogenization |

Line count is not a quality metric. A +20 line bilateral range-weight on sharpen is a better upgrade than +80 lines of holographic neon that do not belong on a photo filter.

---

## 2. Idea Card (mandatory, one per shader, written first)

Paste this block into the batch notes **before** any WGSL edit. A batch without cards is incomplete even if Naga is green.

```
SHADER: <id>
IDENTITY (one sentence): what a viewer must still recognize
KEEP VERBATIM: kernel / modes / param roles / packing that are the effect
ADD (2–4 native ideas):
  1. <idea> — why it belongs on THIS effect
  2. <idea> — why it belongs on THIS effect
  3. <optional>
FORBID on this file: <generic overlays or motif theft that would erase identity>
A PACKING: display RGBA | raw sim state | existing documented packing
```

### What counts as a native idea

Native means it extends the existing mechanism, not a costume from another category.

| Shader family | Native ideas (examples) | Not native |
|---|---|---|
| Post-process (`pp-sharpen`, `pp-vignette`) | Better kernel (bilateral/coring), local amount lens, chromatic at edges, analog falloff | Ferrofluid spikes, IQ palettes, holographic scanlines |
| Image / photographic | Grain, registration, bleach, optical mix, print screen | Raymarched SDF scenes, slime mold |
| Distortion / glitch | Extra tear axis, tracking error, block phase, tile conveyor that is already in the effect | Thin-film iridescence as the whole look |
| Interactive-mouse | Stronger brush physics, wet-edge, pointer-owned trail that the shader already has | Adding a spring to a shader that is not pointer-led |
| Liquid / sim | One extra field or force that the solver already implies | Replacing the solver with display-history sparkles |
| Generative | One new geometric or temporal layer fused to the existing motif | A different creature / different fractal |

Two ideas is the default. Four is the ceiling. If the fourth idea is “also add ACES and ripples,” it is not an idea.

### Completeness rule

After the edit, a reviewer who reads only the Idea Card and the diff should be able to point at each numbered idea in the WGSL. If an idea is not findable, it was not added. If the diff is 70% header/ACES/spring boilerplate, the batch failed even if the ideas exist as comments.

---

## 3. Plumbing floor (do this, do not stop here)

These are required so the shader can live in the catalog. They are **not** the creative work.

- Canonical 13 bindings, `@workgroup_size(16, 16, 1)`, bounds guard.
- Saved `params` byte-exact (ids, names, defaults, min/max/step, mapping order). Align `updatedParams` additively.
- All four sliders live and shader-specific — no shared intensity/speed/contrast shim.
- A-only writes unless the file already owns B for a documented reason. Do not invent B packing.
- Exact `textureLoad(dataTextureC, coord, 0)` for feedback. No filtering sampler on `rgba32float` history.
- ACES on **display** RGB. If A stores raw sim state, do not tone-map the stored fields.
- Semantic alpha (coverage, edge, glow, transmission) — not hardcoded `1.0`.
- `plasmaBuffer[0].xyz` bass/mids/treble when audio is claimed. Never `config.y` or `zoom_config.x` as audio.
- Persistent state only in `extraBuffer[133..138]` (or documented `[133..255]`), single-writer at `(0,0)`. Never `[0..132]`.
- Held pointer and capped click fronts **only if they belong on this effect.** A vignette does not need shockwaves. A brush does.
- Naga-clean WGSL. No reserved identifiers (`target`, `array`, …).

Cloud-VM proof is structural (Naga, extraBuffer, dead sliders, catalogs, Jest, `SKIP_WASM_BUILD=1` build). Real-GPU visual QA is external and still required — do not claim the ideas “look right” from the VM.

---

## 4. Anti-patterns (seen in real batches)

1. **Hygiene as upgrade.** Header comment, ACES helper, `upgraded-rgba` tag, `updatedParams` — and the picture is unchanged.
2. **Reimagining.** `pp-sharpen` becomes a holographic neon scanner. The filename still says sharpen.
3. **Generic overlay.** Every file in the batch gets `extraBuffer[133..138]` spring, ripple rings, IQ palette, two conveyors, oil-slick chroma. Batch 56/67-style motion is a *theme you opt into per shader*, not a stamp.
4. **Param theft.** Rewiring saved sliders to new meanings. Presets must still load.
5. **Packing lies.** Writing display RGBA into A that previous code treated as a field, or writing a mask into A that the next frame reads as color.
6. **Line-count theater.** Target is not “~200 lines.” Target is the Idea Card, implemented.

---

## 5. How to run a batch (8–12 shaders)

### Size vs model

| Model | Batch size | Why |
|---|---|---|
| Gemini Flash / fast Grok | **6–8** | Flash templates under 10–12; ideas collapse to the overlay |
| Claude Opus / Grok 4 / strong general | **8–10** | Room for distinct cards without overlap |
| Hard ceiling | **12** | Past this, even strong models start cloning the first shader |

Do not run two agents on overlapping IDs. Claim the list in the batch notes before editing. `main` often lands concurrent upgrades; rebase ideas onto the newer identity rather than force-landing a rewrite.

### Selection

Prefer a **theme that already lives in the files** (optical, glitch, liquid, PP) or an objective backlog rule (smallest remaining, missing `updatedParams`). Do not pick twelve unrelated IDs and then apply one overlay to all of them.

Post-processing and photographic image shaders need *quieter* ideas than generative or liquid. A sharpen upgrade that a photographer still uses as sharpen is success.

### Per-shader loop

1. Read current WGSL + JSON. Write the Idea Card.
2. Implement the 2–4 ideas **in the existing main path** (same modes, same kernel family).
3. Apply the plumbing floor without replacing the algorithm to do it.
4. Gate that file (`naga` / `wgsl_precommit_gate.py --files`).
5. Next shader. Do not copy the previous file’s overlay.

### Batch closeout

```bash
python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl   # each
npm run audit:extrabuffer
npm run audit:dead-sliders -- --files <id1> <id2> …
node scripts/generate_shader_lists.js
npx react-scripts test --watchAll=false --ci
SKIP_WASM_BUILD=1 npm run build
```

Notes must list, per shader: Idea Card, what was kept verbatim, A packing, and which ideas are visible in the diff. Structural green without cards is not a complete batch.

---

## 6. Timeframe (library-scale, not one batch)

This is how the upgrade program has actually run, so later agents do not treat it as a two-week sprint.

| When | What happened |
|---|---|
| Mar–Apr 2026 | Size-based expansion of tiny shaders; Phase A/B/C swarm aimed at ~650–770 total |
| May 2026 | `CLOUD_UPGRADE.md` `upgraded-rgba` standard (RGBA, audio, depth, dataA) |
| Jun–Jul 2026 | Generative swarm + 4-agent roles; extraBuffer/dead-slider guardrails |
| Aug 2026 | Peak volume: batches ~30–71 plus themed 8–10 packs (optical, liquid, cyber). Catalog crossed ~1,350 |
| Sep 2026 | Same 8–12 agent batches continue; WASM/foundation work runs in parallel |

Catalog now: ~1,407 WGSL files, ~1,372 definitions, ~1,359 unified IDs. Roughly one-third carry an `Upgraded:` header; many August upgrades do, many older files do not. Remaining work is **hundreds of files**, not dozens.

At 8–12 shaders per agent task and a few agents in parallel, raw throughput can look like “done in a month.” That is the wrong clock. The binding/ACES/slider floor is close to saturated on recent cohorts. The remaining value is **distinct incremental ideas**, and that is slower than a hygiene pass. Budget:

- **Hygiene-only closeout** (if that were the goal): weeks.
- **Idea-bearing upgrades on the rest of the library:** months, at 6–10 *distinct* shaders per agent-day with a coordinator reading Idea Cards.
- **Second pass** on files that already have ACES/bindings but no native ideas: treat them as not upgraded.
- **Real-GPU visual QA and thumbnails** (~26% healthy coverage) remain the discoverability bottleneck. Do not let Cloud-VM Naga green substitute for looking at the effect.

When in doubt, ship a smaller batch with real ideas rather than a twelve-file overlay.
