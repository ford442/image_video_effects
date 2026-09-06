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

---

## 7. Worked Idea Cards

**Shipped reference batch (2026-09-06):** photo / print / grade eight. Cards in [`agents/swarm-outputs/grok-2026-09-06-photo-eight/BRIEFS.md`](../agents/swarm-outputs/grok-2026-09-06-photo-eight/BRIEFS.md). Open the WGSL and grep `Ideas:`.

| ID | Native ideas actually in the file | Path |
|---|---|---|
| `pp-bloom` | hue-preserving extract; horizontal anamorphic streak | `public/shaders/pp-bloom.wgsl` |
| `pp-tone-map` | continuous curve mix; hue-preserving contrast | `public/shaders/pp-tone-map.wgsl` |
| `analog-film-degrade` | per-channel grain; continuous hairline; C print-through | `public/shaders/analog-film-degrade.wgsl` |
| `color-blindness` | matrix interpolation; unused param as confusion hatch | `public/shaders/color-blindness.wgsl` |
| `crumpled-paper` | fibre along crease tangent; ironing memory in C.a | `public/shaders/crumpled-paper.wgsl` |
| `retro-gameboy` | round LCD dots; honest A/C ghost | `public/shaders/retro-gameboy.wgsl` |
| `conv-bilateral-dream` | joint depth range; luma-range weights | `public/shaders/conv-bilateral-dream.wgsl` |
| `tilt-shift` | hex CoC aperture; defocus specular bloom | `public/shaders/tilt-shift.wgsl` |

None of these files got a spring+ripple overlay. That is the point.

### Good — post-process stays post-process (from that batch)

```
SHADER: pp-bloom
IDENTITY: HDR threshold bloom added onto the source photo, with optional anamorphic Y stretch
KEEP VERBATIM: intensity / anamorphic / threshold / quality tap-count; soft-knee extract; additive composite
ADD:
  1. hue-preserving bright extract — keep highlight tint
  2. horizontal anamorphic streak along the already-stretched axis
FORBID: springs, click shockwaves, IQ palettes
A PACKING: ACES display RGBA (HEAD stored the blur in A)
```

See also `pp-tone-map` in the same batch: four curves kept, slider now *mixes* them.

### Bad — same filename, different effect

```
SHADER: pp-sharpen
ADD:
  1. spring-damper cursor in extraBuffer[133..138]
  2. click ripple shockwaves
  3. holographic neon edge pop (IQ palette)
  4. ACES + plasmaBuffer
```

That is the generic overlay. Modes survive as comments. The picture is a scanner. **Reject.**

### Good — interactive effect that already owns the pointer

```
SHADER: brush-strokes
IDENTITY: wet brush that paints the photo under the cursor
KEEP VERBATIM: brush radius / texture / color / speed params, distance-to-mouse stroke, existing trail if any
ADD:
  1. bristle offset along the stroke tangent (this is a brush)
  2. wet-edge accumulation from exact C history (paint, not a new sim)
FORBID: replacing the brush with a particle galaxy or a liquid solver
A PACKING: display RGBA with paint in the RGB; do not pack velocity into A unless HEAD already did
```

### Good — liquid that already has a solver

```
SHADER: liquid-jelly
IDENTITY: wobbly mass with finite-speed shear
KEEP VERBATIM: height/velocity (or display-history) packing already documented, saved viscosity/size params
ADD:
  1. jiggle overshoot streaks along existing shear
  2. arrival-gated wave so distant pixels wait for the front
FORBID: Gray-Scott, IQ candy palette as the whole look, extraBuffer springs if the mass is not pointer-tethered
A PACKING: keep HEAD's packing (raw or display) — do not "promote" to display history if it was a sim
```

If you cannot fill KEEP VERBATIM from the current file, you have not read it. Stop.

---

## 8. Header, JSON, and packing (tell the truth)

### WGSL header

The 7-line banner is not the upgrade. When you do add it, **name the ideas**:

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Analog Film Degrade
//  Category: image
//  Features: audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-06
//  Ideas: per-channel grain; continuous gate-weave hairlines; C print-through
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
```

Copy the `Ideas:` / `A packing:` lines from a shipped file (`public/shaders/analog-film-degrade.wgsl`), not a blank template.

Do not put `fast-motion` in Features unless this file actually opted into a fast-motion brief. Do not date-stamp `Upgraded:` for a metadata-only pass.

### JSON

- Saved `params` (ids, names, defaults, min/max/step, mapping onto `zoom_params.xyzw`) stay **byte-exact**.
- `updatedParams` may be added or aligned. Do not rename or re-default `params`.
- `"upgraded-rgba"` in `features` only when **ACES is in WGSL and the Idea Card is implemented**. Tag-without-ideas is the 2026-06 metadata-drift bug.
- `"audio-reactive"` only when `plasmaBuffer[0].xyz` actually modulates something visible.
- `"mouse-driven"` only when the pointer changes the picture. A unused `zoom_config` read is not mouse-driven.
- Document A packing in a short `feedback` / notes field if the definition already has one; do not invent new schema keys.

### A / B / C packing

| Write | Meaning |
|---|---|
| `dataTextureA` | Next frame's `dataTextureC`. Must match how **this** shader reads C. |
| Display RGBA in A | Only if C is read as color/history. |
| Raw sim in A | Only if C is read as fields (height, velocity, RD, occupancy). **Do not ACES the stored fields.** Tone-map on `writeTexture` only. |
| `dataTextureB` | Do not start using it. Keep it if HEAD already owns it for a documented reason. |
| Depth | Geometry or a truthful relief derived from the effect. Not a place to hide sim state. |

HEAD packing wins when it is already consistent. If HEAD stored a mask in A and read C as color, that is a packing lie — fix it to display RGBA **and say so in the Idea Card**, not in silence.

### Springs and ripples

`extraBuffer[133..138]` springs and `u.ripples[]` shockwaves are **tools for effects that already live under the pointer**. They are not part of the floor.

- Brush, drag, lens, magnet: yes, if HEAD already tracks the mouse.
- Sharpen, vignette, levels, a still photographic grade: no, unless the original already used the pointer as a local amount.
- Do not add a spring “for contract completeness.”

---

## 9. Notes, MEMORY.md, and coordinator review

### Where to write the batch

`agents/swarm-outputs/<agent>-YYYY-MM-DD-<batch-id>/`

Required files:

- `BRIEFS.md` — every Idea Card, written **before** WGSL
- `NOTES.md` — per shader: kept verbatim, packing, which ideas are in the diff
- `COORDINATOR_REVIEW.md` — pass/fail per file against the cards

Do not skip briefs because Naga is green.

### MEMORY.md / USER.md closeout (required shape)

Do **not** list the plumbing floor as the upgrade. That is how the 2026-09-06 ten-pack closeout read: 13 bindings, ACES, springs, ripples — and one named idea.

Write:

```
## YYYY-MM-DD — <batch name> (<N> shaders)

- IDs: …
- Per shader, the ideas actually added:
  - pp-sharpen: bilateral range-weight; unsharp coring. Modes kept. No spring.
  - brush-strokes: bristle tangent; wet-edge C accumulation. Radius param kept.
- Floor: bindings / 16×16 / exact C / A packing as documented / saved params exact.
- Gates: Naga N/N, extraBuffer, dead sliders, catalogs, Jest, SKIP_WASM_BUILD=1 build.
- Real-GPU visual QA: external.
```

If a file only received the floor, say **hygiene, not upgraded** and do not bump `Upgraded:`.

### Coordinator checklist (fail the file)

- [ ] Idea Card exists and was written before the diff
- [ ] Each numbered idea is pointable in the WGSL
- [ ] KEEP VERBATIM still holds (modes, kernel family, param roles)
- [ ] Diff is not ≥70% header / ACES / spring / ripple boilerplate
- [ ] No generic overlay shared with the previous file in the batch
- [ ] A packing matches how C is read
- [ ] Saved `params` unchanged
- [ ] Springs/ripples only if native
- [ ] Naga + extraBuffer + dead sliders on this file

A batch with 10/10 Naga and 0 Idea Cards is **incomplete**.

---

## 10. Live vs historical docs (agents: read the live column)

Future agents land in this repo and open the first markdown hit. **These files disagree.** Use this map.

| File | Status | Role |
|---|---|---|
| **`docs/SHADER_UPGRADE_BATCH.md`** | **LIVE** | Creative contract. Idea Cards, anti-patterns, batch size, timeframe. |
| **`agents/WGSL_BUILTINS_GENERATIVE.md`** | **LIVE** | Bindings, uniforms, extraBuffer map, naga-safe builtins. |
| **`docs/BINDING_CONTRACT.md`** | **LIVE** | Engine bind group, uniforms, feedback copy order. |
| **`scripts/AUTHORING.md`** | **LIVE** | Scaffold, gates, audits. |
| **`agents/CLOUD_UPGRADE.md`** | **LIVE plumbing** | Floor snippets (ACES, alpha, audio). Creative law is this file, not CLOUD §4–§10 examples. |
| `agents/weekly_upgrade_swarm.md` | **Historical log** | Completed-batch diary. Do not copy its overlay themes onto a new family. |
| `agents/upgrade_swarm.md` | **Historical (2026-04)** | Size-expansion ideas. Do not treat target line counts as success. |
| `agents/GENERATIVE_UPGRADE_SWARM.md` | **Historical (2026-04)** | Same. |
| `agents/4_AGENT_SWARM_PROMPT.md` | **Historical** | Role split. Do not “replace primitive noise with a masterpiece.” |
| `agents/grok_build_upgrade.md` | **Historical weekly new-shader plan** | For **new** shaders, not upgrades. Upgrades use this file. |
| `composer.md` | **Historical (2026-06)** | `upgraded-rgba` hygiene sprint. ACES-only batches are not upgrades. |
| `notes/SHADER_UPGRADE_MANIFEST.md` | **Historical** | 16-shader April initiative. |
| `notes/shaders_upgrade_plan.md` | **Historical queue** | Size tiers only. First principle now points here. |
| `agents/prompt-templates/*.md` | **LIVE roles** | Toolkits. Identity-preserving rules at the top of each. Do not apply a whole toolkit to every file. |
| `scripts/run-upgrade-swarm.js` | **LIVE generator** | Must emit Idea Cards. Ignore any leftover `target_lines ±20%` folklore in old queue JSON. |

If two docs conflict, **this file wins on what an upgrade is.** BINDING_CONTRACT / WGSL_BUILTINS win on what the engine does.

---

## 11. Paste block for a new agent task

```
Read docs/SHADER_UPGRADE_BATCH.md first (especially §0, §2, §7, §9).
You are upgrading these existing catalog shaders: <id list>.
For each: write an Idea Card, then add 2–4 native ideas in the existing main path.
Do not reimagine. Do not treat ACES/bindings/updatedParams/springs as the upgrade.
Do not stamp a spring+ripple+IQ overlay across the batch.
Saved params stay byte-exact. Document A packing. Naga each file.
Write agents/swarm-outputs/<you>-<date>-<batch>/BRIEFS.md before WGSL.
Cloud VM has no GPU — structural gates only; do not claim visual QA.
```

