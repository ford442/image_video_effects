# Shader Upgrade Batches — Incremental Ideas Contract

> **This is the live process.** Paste this file (or §0) into Gemini / Grok / Claude / Antigravity before a batch.
> Longer plumbing reference: [`docs/agents/CLOUD_UPGRADE.md`](agents/CLOUD_UPGRADE.md).
> Bindings / uniforms: [`docs/BINDING_CONTRACT.md`](BINDING_CONTRACT.md) and [`docs/agents/WGSL_BUILTINS_GENERATIVE.md`](agents/WGSL_BUILTINS_GENERATIVE.md).
> Native idea toolkit (tactics, per-family formulae, WGSL snippets, prefer/avoid): §12 below. It is a menu, not a checklist; the law is §0–§11.

---

## 0. Copy-paste law (put this at the top of every batch prompt)

An upgrade **adds 2–4 named visual ideas to the existing effect**. It is not a new shader, not a reimagining, and not a formatting / uniform-alignment pass.

1. **Write an Idea Card for every shader before touching WGSL.** If you cannot name the additions in one sentence each, you are not ready to edit.
2. **Keep the algorithm, the look, and the saved `params`.** Same modes, same kernel family, same identity. Deepen what is already there.
3. **Plumbing is the floor, not the upgrade.** Canonical 13 bindings, 16×16, ACES, semantic alpha, exact C loads, live sliders, and `x-meta.upgrade.params` alignment must happen — they do not by themselves count as an upgrade.
4. **No generic overlay.** Do not stamp every file with the same spring cursor, ripple shockwaves, IQ cosine palette, and two “conveyors.” Ideas must be native to *this* effect.
5. **Refuse a header-only or rewrite-only result.** A shader that newly compiles, writes depth/A, and looks the same is not upgraded. A shader whose name still matches but whose picture is a different effect is not upgraded either.
6. **Bindings come from `#include "_prelude.wgsl"`.** Never paste the 13 binding declarations or `struct Uniforms` — CI fails on a pasted copy. If a file you touch still pastes them, run `python3 scripts/migrate_to_prelude.py --files public/shaders/<id>.wgsl` first. That swap is infrastructure, not an upgrade: never bump `Upgraded:` for it.

---

## 1. What “upgrade” means

The catalog is ~1,350 effects. Many already have a distinct identity: unsharp-mask sharpen, vignette, brush strokes, tile glitch, double exposure. The job is to make **that** picture richer — a new structure, a new motion, a new optical or tactile beat — while a viewer still recognizes the original effect in the first second.

| Kind of change | Counts as upgrade? |
|---|---|
| Two named, effect-specific visual ideas plus the contract floor | **Yes** |
| Identity preserved; kernel/mode/param roles kept; new detail is additive | **Yes** |
| Bindings, workgroup, ACES, alpha, `dataTextureA`, `x-meta.upgrade.params` only | **No** — that is hygiene |
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

- Canonical 13 bindings via `#include "_prelude.wgsl"` (never pasted), `@workgroup_size(16, 16, 1)`, bounds guard.
- Saved `params` byte-exact (ids, names, defaults, min/max/step, mapping order). Align `x-meta.upgrade.params` additively.
- All four sliders live and shader-specific — no shared intensity/speed/contrast shim.
- A-only writes unless the file already owns B for a documented reason. Do not invent B packing.
- Exact `textureLoad(dataTextureC, coord, 0)` for feedback. No filtering sampler on `rgba32float` history.
- ACES on **display** RGB. If A stores raw sim state, do not tone-map the stored fields.
- Semantic alpha (coverage, edge, glow, transmission) — not hardcoded `1.0`.
- `plasmaBuffer[0].xyz` bass/mids/treble when audio is claimed. Never `config.y` or `zoom_config.x` as audio.
- Persistent state only in `extraBuffer[133..138]` (or documented `[133..255]`), single-writer at `(0,0)`. Never `[0..132]`.
- Held pointer and capped click fronts **only if they belong on this effect.** A vignette does not need shockwaves. A brush does.
- Naga-clean WGSL. No reserved identifiers (`target`, `array`, …).

Cloud-VM proof is structural (Naga, extraBuffer, dead sliders, catalogs, Vitest, `npm run build`). Real-GPU visual QA is external and still required — do not claim the ideas “look right” from the VM.

---

## 4. Anti-patterns (seen in real batches)

1. **Hygiene as upgrade.** Header comment, ACES helper, `upgraded-rgba` tag, `x-meta.upgrade.params` — and the picture is unchanged.
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

Prefer a **theme that already lives in the files** (optical, glitch, liquid, PP) or an objective backlog rule (smallest remaining, missing `x-meta.upgrade.params`). Do not pick twelve unrelated IDs and then apply one overlay to all of them.

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
npm test -- --watchAll=false --ci
npm run build
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
- `x-meta.upgrade.params` may be added or aligned. Do not rename or re-default `params`.
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

## 8b. Record the batch (required, last step before commit)

```bash
npm run upgrades:record -- --note="<date> <batch name> (<model>) — <batch notes file>"
```

This logs every changed shader in `reports/shader-upgrade-ledger.json` and marks
its thumbnail stale. Use `--event=hygiene` for plumbing-only passes so they are
not counted as upgrades. Thumbnails are refreshed afterwards on a GPU machine
(Shader Scanner → *Changed since last thumbnail*), not by the agent.

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
- Gates: Naga N/N, extraBuffer, dead sliders, catalogs, Vitest, `npm run build`.
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
| **`docs/agents/WGSL_BUILTINS_GENERATIVE.md`** | **LIVE** | Bindings, uniforms, extraBuffer map, naga-safe builtins. |
| **`docs/BINDING_CONTRACT.md`** | **LIVE** | Engine bind group, uniforms, feedback copy order. |
| **`docs/AUTHORING.md`** | **LIVE** | Scaffold, gates, audits. |
| **`docs/agents/CLOUD_UPGRADE.md`** | **LIVE plumbing** | Floor snippets (ACES, alpha, audio). Creative law is this file, not CLOUD §4–§10 examples. |
| `docs/agents/weekly_upgrade_swarm.md` | **Historical log** | Completed-batch diary. Do not copy its overlay themes onto a new family. |
| `docs/agents/upgrade_swarm.md` | **Historical (2026-04)** | Size-expansion ideas. Do not treat target line counts as success. |
| `docs/agents/GENERATIVE_UPGRADE_SWARM.md` | **Historical (2026-04)** | Same. |
| `docs/agents/4_AGENT_SWARM_PROMPT.md` | **Historical** | Role split. Do not “replace primitive noise with a masterpiece.” |
| `docs/agents/grok_build_upgrade.md` | **Historical weekly new-shader plan** | For **new** shaders, not upgrades. Upgrades use this file. |
| `composer.md` | **Historical (2026-06)** | `upgraded-rgba` hygiene sprint. ACES-only batches are not upgrades. |
| `notes/SHADER_UPGRADE_MANIFEST.md` (local, untracked) | **Historical** | 16-shader April initiative. |
| `notes/shaders_upgrade_plan.md` (local, untracked) | **Historical queue** | Size tiers only. First principle now points here. |
| `docs/agents/prompt-templates/*.md` | **LIVE roles** | Toolkits. Identity-preserving rules at the top of each. Do not apply a whole toolkit to every file. |
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
Bindings come from #include "_prelude.wgsl" — never paste them; migrate a pasted
header with python3 scripts/migrate_to_prelude.py --files <file> (no Upgraded: bump).
Write agents/swarm-outputs/<you>-<date>-<batch>/BRIEFS.md before WGSL.
Cloud VM has no GPU — structural gates only; do not claim visual QA.
```


---

## 12. Native Idea Toolkit — tactics, formulae, snippets, admission rules

> **How agents should use this section.** §0–§11 are the law and are unchanged by this
> section. §12 exists to answer one question that the law leaves open: *"I know I must add
> 2–4 native ideas — where do I get them?"* Use it in this order and no other:
> **(1)** write the Idea Card from the current file (§2), **(2)** run the mechanism
> interrogation in §12.1 to name ideas in the shader's own vocabulary, **(3)** pick at most
> 1–2 formulae from the family table in §12.2 that pass the admission test in §12.4,
> **(4)** adapt the snippet in §12.3 *inside the existing main path*, **(5)** apply the floor
> (§3), **(6)** gate. A formula that fails the admission test is not "a bit of extra polish" —
> it is the generic overlay of §4 with a new name. This toolkit is a *menu per family*; it is
> never a checklist, and nothing here is required on any file.

### 12.1 Tactics for inventing *native* ideas

A native idea is one that a domain expert of the **real device or process the shader
imitates** would recognize. The tactics below produce ideas in the shader's own vocabulary;
the questions are meant to be answered in writing in `BRIEFS.md` for every file.

| # | Tactic | Interrogate the current file with… | Example of the output |
|---|---|---|---|
| 1 | **Deepen the kernel** | What does the kernel approximate? What is the next-better approximation of the *same* operator? | Box blur → Gaussian → bilateral range weight → guided filter; 5-pt Laplacian → 9-pt isotropic |
| 2 | **Follow the physics one step further** | The effect models X. What is the first-order side effect of X that the real device also shows? | Sharpen → anti-halo envelope; film → halation; lens → cos⁴ falloff; VHS → chroma delay |
| 3 | **Promote an intermediate** | Which quantity does `main()` already compute and throw away? | `maxGradient` → coherence mask; `totalWeight` → local density; raymarch step count → AO |
| 4 | **Second-order the parameter** | Each saved param controls one scalar. What is the *spatially varying* or *temporally varying* version of that scalar that still matches its name? | `radius` → radius scaled by local contrast; `fade` → fade that creeps in from the frame edge |
| 5 | **Name the artifact of the real device** | Scanner, projector, camera, tape deck, brush, water tank: list three artifacts a technician of that device would name. Pick the one not yet present. | Gate weave, dropout, dichroic fringe, bristle splay, surface tension bead |
| 6 | **Use the history the shader already owns** | How is `dataTextureC` read today (color / field)? What *one* extra piece of continuity does that reading afford without changing the packing? | Color history → hysteresis lock; height field → wave dispersion; paint alpha → drying |
| 7 | **Direction, not just magnitude** | Does the effect compute a gradient? Then it also has an orientation. Where would the real process be anisotropic? | Edge-directed sharpening; bristles along stroke tangent; tear along scanline only |
| 8 | **Energy accounting** | Does the effect add light? Where does that light come from in the real device, and what does it leave behind? | Bloom that subtracts from the source it spreads; halation that *desaturates* the clipped core |

Three tests every candidate must pass before it goes on the card:

- **Same-noun test.** Describe the idea in one sentence. If the sentence needs a noun from a
  different catalog family (ferrofluid, hologram, slime, galaxy) on a photographic/distortion
  shader, it is a costume. Rewrite or drop.
- **Deletion test.** Mentally delete the idea. Is the result still exactly *this* effect? Yes →
  the idea is additive (good). Now mentally delete the *original* mechanism and keep only the
  idea. Is it still recognizable as this effect? If **yes**, the idea has *replaced* the
  mechanism — that is a reimagining (§4.2).
- **Expert test.** Would a photographer / VJ / fluid-sim author say *"yes, that's what a real
  one does"*? If the honest answer is "it looks cool", it belongs in a new shader, not an upgrade.

### 12.2 Formula library by shader family

Rows are **candidates**, not requirements. Pick 1–2 per file. Where a formula already has a
live snippet elsewhere, the row links to it instead of repeating it:
[`algorithmist.md`](agents/prompt-templates/algorithmist.md) (curl, Worley, warped fBm,
kaleido, Halton, smin, attractors, complex/Möbius, physical-equation table),
[`ULTRA_SHADER_TECHNIQUES.md`](ULTRA_SHADER_TECHNIQUES.md) (analytic normals, bicubic, TAA,
temporal Monte Carlo, 4-field RGBA), [`WOLFRAM_SHADER_DATA.md`](WOLFRAM_SHADER_DATA.md)
(constants, Rayleigh, blackbody, Bessel, spherical harmonics, phyllotaxis),
[`CLOUD_UPGRADE.md §6`](agents/CLOUD_UPGRADE.md) (ACES, safe normalize, audio pulse — floor
snippets, not ideas), [`BRANCHLESS_PATTERNS.md`](BRANCHLESS_PATTERNS.md) (masks, `select`,
flattened loops — write every snippet below this way).

#### A. Post-process / photographic (`pp-*`, grades, film, print, lens blur)

| Formula | Core expression | What it adds to the *existing* mechanism | Native on |
|---|---|---|---|
| **Local contrast normalization (Wallis)** | `out = (x−μ)/(σ+ε)·σₜ + μₜ`, μ/σ from the taps already fetched | Turns a fixed-amount kernel into an adaptive one; flat areas stay quiet | sharpen, clarity, dehaze, levels |
| **Guided-filter base/detail** | `a = cov(I,p)/(var(I)+ε)`, `b = μₚ − a·μᵢ`, `q = a·I + b` | Edge-aware split so detail boost never crosses a real edge | sharpen, HDR local tone, dehaze |
| **Structure-tensor orientation** | `J = blur([Ex², ExEy; ExEy, Ey²])`, `θ = ½·atan2(2Jxy, Jxx−Jyy)`, `coh = (λ₁−λ₂)/(λ₁+λ₂)` | A direction and a confidence for every edge the kernel already detects → anisotropic kernels | sharpen, emboss, edge filters, oil-paint |
| **Anti-halo envelope** | `clamp(y, min(taps)−r, max(taps)+r)` | Sharpening without ringing (shipped in `pp-sharpen`) | sharpen, unsharp mask, local contrast |
| **Density-weighted grain (Selwyn-ish)** | `σ(L) = k·sqrt(L·(1−L))` | Grain peaks in midtones, vanishes in clear base and dense shadow — the signature of real film | grain, film, print |
| **Halation** | `h = blur₄(max(L−t,0))·(1.0, 0.35, 0.10)` added, core slightly desaturated | Red-biased glow around clipped highlights (light bouncing off the film base) | film, cine grade, projector |
| **H&D characteristic curve** | `D = D₀ + γ·log10(E)` with logistic toe/shoulder `1/(1+exp(−k(x−x₀)))` | Replaces a linear fade with a film-like response; one slider, same role | film, tone-map, exposure, bleach |
| **cos⁴ vignetting** | `I = I₀·cos⁴(atan(r/f))` | Physically shaped falloff instead of a radial smoothstep; `f` from the existing radius param | vignette, lens, camera grades |
| **Photon shot noise** | `σ ∝ sqrt(max(L,ε))` per channel, treble-free | Sensor noise that scales with signal — digital analogue of grain | digital grain, low-light, sensor sims |
| **CFA zipper** | luma from full-res, chroma from `floor(uv·res/2)·2` neighbours | Bayer-style colour aliasing on fine edges | digital camera, pixelate-camera, sensor sims |

#### B. Distortion / glitch (tears, VHS, CRT, datamosh, blocks, warps)

| Formula | Core expression | What it adds | Native on |
|---|---|---|---|
| **Schmitt-trigger lock** | `s = select(s_prev, 1, x>hi)`, `s = select(s, 0, x<lo)`, `s_prev` from exact C | Tracking errors that *latch* and release instead of flickering per frame | VHS tracking, sync loss, glitch tiles |
| **Sync-pulse timing** | tear `= saw(line·f_h + j)`, `j` low-passed through C; roll `= fract(t·v_hold)` | Horizontal tears that originate at the sync edge and a vertical roll that drifts, not jumps | VHS, CRT, broadcast glitch |
| **Chroma delay line (4:2:0)** | chroma sampled at `uv − (δ_x, 0)` at half res, luma full res | Colour smears right of luma edges — the real tape look | VHS, NTSC, composite |
| **Brown–Conrady radial** | `r' = r·(1 + k₁r² + k₂r⁴)`, tangential `+ (2p₁xy + p₂(r²+2x²))` | Lens distortion with a real two-term shape; `k₁` from the existing strength param | barrel/pincushion, fisheye, CRT glass |
| **Block DCT quantization** | per 8×8: `q = round(x/Q)·Q`, `Q` from existing block param | Compression banding inside blocks the effect already draws | datamosh, JPEG-glitch, block sort |
| **Macroblock motion carry** | shift block uv by the motion the *previous* frame's block had (from C) | P-frame smear that follows content | datamosh only |
| **Dropout bursts** | `burst = step(1−p, hash(line, floor(t·f)))·exp(−x·λ)` along the scanline | Horizontal white/black streaks with an exponential tail | VHS, film-scan, tape |
| **Field interlace** | `field = f32((gid.y + frame) & 1u)` as a mask | Alternate-line temporal offset, no new motif | CRT, interlace, broadcast |

#### C. Interactive / brush (paint, smudge, drag, lens, magnet — only files that already own the pointer)

| Formula | Core expression | What it adds | Native on |
|---|---|---|---|
| **Stroke tangent from paint field** | `t = perp(normalize(∇a))`, `a` = paint alpha in C | Bristle offsets *along* the stroke without any new state | brush, ink, oil-paint |
| **Speed-thinning** | `w = w₀/(1 + k·|v|)`, `v` from the file's existing spring velocity (`extraBuffer[135..136]`) | Fast strokes get thin, slow strokes pool — real brush kinematics | brush, calligraphy, trail |
| **Dwell pressure** | `a += held·dt·(1−a)` | Paint blooms under a held pointer | brush, stamp, wet paint |
| **Wet-edge accumulation** | `edge = max(−∇²a, 0)` darkens pigment at the stroke boundary | Watercolour edge darkening from the paint field itself | watercolour, ink wash |
| **Drying** | `a ← a·exp(−dt/τ)` | Paint that settles instead of fading linearly | wet paint, smudge |
| **Semi-Lagrangian smudge** | `col = C(uv − v·dt)` with `v` the pointer velocity, clamped uv | Real smear along the drag, no new solver | smudge, finger-paint, drag |
| **Paper granulation** | `a·(1 − g·hash(uv·N))` | Pigment settles into paper grain | watercolour, pastel, chalk |

#### D. Liquid / simulation (ripples, fluids, RD, jelly, waves — keep the solver, add one term)

| Formula | Core expression | What it adds | Native on |
|---|---|---|---|
| **Vorticity confinement** | `ω = ∂v_y/∂x − ∂v_x/∂y`, `N = ∇|ω|/(|∇|ω||+ε)`, `f = ε·h·(N × ω)` | Small-scale swirls the grid solver damped out | fluids, smoke, dye advection |
| **MacCormack advection** | `φ = φ_fwd + ½(φ − φ_back)`, clamped to the neighbourhood | Sharper advection with the same two samples | fluids, dye, liquid distortions |
| **Isotropic 9-point Laplacian** | weights `0.2` (edges), `0.05` (corners), `−1` centre | Removes the axis bias of the 5-point stencil | RD, waves, heat, jelly |
| **Damped wave equation** | `h' = 2h − h_prev + c²∇²h − k(h − h_prev)` | Real ring-down on a height field that already stores `h, h_prev` | ripples, water, jelly |
| **Deep-water dispersion** | `ω² = g·k·tanh(k·d)` → phase speed per wavelength | Long waves outrun short ones; rings spread into trains | ripples, ocean, puddle |
| **Surface tension** | `κ = ∇·(∇φ/|∇φ|)`, `f = −σ·κ·∇φ` | Beads and rounded fronts on an interface the shader already has | droplets, metaball liquid, jelly |
| **Boussinesq buoyancy** | `f_y = (α·T − β·ρ)·g` | Hot rises, dense sinks, from fields already stored | smoke, plume, ink-in-water |
| **Shallow-water continuity** | `∂h/∂t = −∇·(h·v)` | Mass-conserving height change for a flow field already present | puddles, spill, tide |

#### E. Generative / SDF / fractal (keep the motif; add one layer fused to it)

| Formula | Core expression | What it adds | Native on |
|---|---|---|---|
| **Orbit trap** | inside the existing loop: `trap = min(trap, |z − c|)` (or distance to line/circle) | Veins/texture from the iteration already running | Mandelbrot/Julia, KIFS, Mandelbulb |
| **Smooth iteration count** | `n + 1 − log2(log|z| / log B)` | Removes banding in escape-time colouring | escape-time fractals |
| **Fold count as material** | `folds += f32(p.x < 0.0)` per reflection in the IFS | Material/roughness by how many times a point was folded | KIFS, Menger, kaleidoscopic SDFs |
| **Over-relaxed sphere tracing** | step `ω·d`, `ω∈[1.2,1.6]`, fall back to `d` when `ω·d` overshoots (`d_i + d_{i−1} < ω·d_{i−1}`) | Fewer steps for the same march; spend them on more iterations | any raymarched SDF |
| **Step-count AO** | `ao = 1 − k·Σᵢ (i·δ − d(p + n·i·δ))/2ⁱ` for 5 taps | Crevice darkening on the surface already marched | raymarched SDFs |
| **SDF curvature** | `κ ≈ (Σ d(p±e·axis) − 6d)/e²` | Edge wear / rim highlight where the existing surface bends | hard-surface SDFs, crystals |
| **Additive domain twist** | `p.xz = rot(k·p.y)·p.xz` before the *existing* map | Motion through geometry without a new primitive | columns, towers, tendrils |
| **Golden-angle layout** | `θ = i·2.39996`, `r = c·sqrt(i)` (see Wolfram doc) | Natural spacing for dot/particle fields that already exist | dot fields, spores, seeds |

#### F. Lighting / optical (flares, bloom, glass, prisms, caustics, volumetrics)

| Formula | Core expression | What it adds | Native on |
|---|---|---|---|
| **Fresnel–Schlick / Henyey–Greenstein / Beer–Lambert** | see [`algorithmist.md`](agents/prompt-templates/algorithmist.md) table | Grazing reflectance, forward scatter, absorption — one term each | glass, fog, volumetrics |
| **Cauchy dispersion** | `n(λ) = A + B/λ²`, evaluate at 650/550/450 nm | Non-linear R/G/B separation instead of a fixed `±δ` | prisms, chromatic lens, glass |
| **Thin-film phase** | `δ = 4π·n·d·cosθₜ/λ`, `R(λ) ∝ cos²(δ/2)` | Interference colours that shift with thickness and angle | soap, oil-slick, bubble (**only** where thin-film already *is* the effect) |
| **Airy disc** | `(2·J₁(x)/x)²`, `J₁` polynomial approx, first zero at `3.8317` | Diffraction rings on a point highlight the effect already draws | bokeh, starburst, pinhole |
| **Lens-flare ghosts** | `uv_g = c + (c − uv)·sᵢ`, scaled per channel by Cauchy | Ghost chain along the optical axis the flare already has | flares, anamorphic streaks |
| **Snell vector refraction** | `r = η·i + (η·cosθᵢ − sqrt(max(1 − η²(1 − cos²θᵢ), 0)))·n` | A true refraction direction for a surface normal already computed | glass, water surface, lens |
| **Soft inverse-square** | `I/(d² + r₀²)` | Falloff with a core radius, no singularity | point lights, glow sources |
| **Energy-conserving bloom** | `src −= spread·k`, `out = src + spread` | Highlights that glow without doubling the exposure | bloom, glow, halation |
| **Rayleigh / blackbody** | see [`WOLFRAM_SHADER_DATA.md`](WOLFRAM_SHADER_DATA.md) | Spectral tint for haze and emitters | atmosphere, fire, stars |

### 12.3 Ready-to-adapt WGSL snippets (highest-value formulae)

Rules for every snippet: adapt names to the file, read taps the kernel **already** fetches
where possible, guard every division and root, keep it branchless (masks, `select`, `mix`),
and clamp before `aces()` — the catalog ACES fit maps negative input to bright output.
Derivative builtins (`fwidth`, `dpdx`) do **not** exist in compute shaders; use `1.0/res`
footprints and finite differences instead. Everything is scalar `f32` unless typed.

**A1 — Structure tensor (orientation + coherence) from a 3×3 luma neighbourhood.**
Reuse the kernel's taps if it has a 3×3; otherwise 4 extra loads.

```wgsl
// lumas: l[0..7] in the pp-sharpen 8-tap order (TL,T,TR,L,R,BL,B,BR)
fn structureTensor(l: array<f32, 8>) -> vec3<f32> {
  // Sobel gradients
  let ex = (l[2] + 2.0 * l[4] + l[7]) - (l[0] + 2.0 * l[3] + l[5]);
  let ey = (l[5] + 2.0 * l[6] + l[7]) - (l[0] + 2.0 * l[1] + l[2]);
  let jxx = ex * ex; let jyy = ey * ey; let jxy = ex * ey;
  let theta = 0.5 * atan2(2.0 * jxy, jxx - jyy);          // edge normal angle
  let tr = jxx + jyy;
  let det = jxx * jyy - jxy * jxy;
  let disc = sqrt(max(tr * tr * 0.25 - det, 0.0));
  let l1 = tr * 0.5 + disc; let l2 = tr * 0.5 - disc;
  let coh = (l1 - l2) / max(l1 + l2, 1e-5);               // 0 = isotropic, 1 = clean edge
  return vec3<f32>(cos(theta), sin(theta), coh);
}
// Use: let n = st.xy; let t = vec2<f32>(-n.y, n.x);  // tangent along the edge
// Edge-directed sharpening: fetch two taps along ±n only and weight by st.z.
```

**A2 — Local contrast normalization from taps already summed.**

```wgsl
// mean/var of the blur taps the kernel already loops over:
//   sumL += tapLuma * w;  sumL2 += tapLuma * tapLuma * w;   (inside the existing loop)
let mu   = sumL / max(totalWeight, 1e-4);
let vari = max(sumL2 / max(totalWeight, 1e-4) - mu * mu, 0.0);
let sigma = sqrt(vari);
let gain  = clamp(targetSigma / (sigma + 0.02), 0.5, 3.0);   // targetSigma from the existing amount param
let normalized = mu + (centerLuma - mu) * gain;
// Blend by the mask the file already has (edgeMask / coring), never globally.
```

**A3 — Density-weighted grain + halation (photographic).**
Grain is the one place a film-rate quantized seed is *native* (the real device changes grain
every frame); still blend with the exact C history the file already reads.

```wgsl
let L = clamp(dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
let density = sqrt(max(L * (1.0 - L), 0.0)) * 2.0;        // 0 at black/white, 1 at mid-grey
let frameSeed = floor(time * 24.0);                        // film cadence
let g = vec3<f32>(hash21(uv * 512.0 + frameSeed),
                  hash21(uv * 512.0 + frameSeed + 17.1),
                  hash21(uv * 512.0 + frameSeed + 29.3)) - 0.5;
rgb += g * grainIntensity * density;

// Halation: 4 cheap taps of clipped highlight, red-biased, energy taken from the core
let hr = 3.0 / res;
var hal = 0.0;
for (var k = 0; k < 4; k = k + 1) {
  let o = vec2<f32>(f32(k & 1) * 2.0 - 1.0, f32(k >> 1) * 2.0 - 1.0) * hr;
  let t = textureSampleLevel(readTexture, u_sampler, clamp(uv + o, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  hal += max(dot(t, vec3<f32>(0.2126, 0.7152, 0.0722)) - 0.85, 0.0);
}
hal *= 0.25 * halationAmount;
rgb += hal * vec3<f32>(1.0, 0.35, 0.10);
rgb = mix(rgb, vec3<f32>(L), hal * 0.5);                   // bleached core
```

**B1 — Schmitt-trigger tracking lock through exact C history.**
Stores the latch in the alpha of A only if the file already packs display RGBA and C.a is
not otherwise used; otherwise use an existing field. Say which in the Idea Card.

```wgsl
let prev = textureLoad(dataTextureC, coord, 0);
let lockPrev = step(0.5, prev.a);                          // 0 or 1
let drive = noise1(uv.y * 40.0 + time * 0.7);              // whatever the effect already uses to trigger tears
let hi = 0.65 + 0.2 * (1.0 - glitchAmount);
let lo = hi - 0.25;
var lock = lockPrev;
lock = select(lock, 1.0, drive > hi);
lock = select(lock, 0.0, drive < lo);
// tear only while locked; roll onset is the frame lock flips 0→1
let tear = lock * tearAmplitude * saw(uv.y * lines + lowPassJitter);
// … write lock into A.a (with the display RGB) so next frame reads it as C.a
```

**B2 — Brown–Conrady radial + Cauchy per-channel scale.**

```wgsl
fn brownConrady(p: vec2<f32>, k1: f32, k2: f32) -> vec2<f32> {
  let r2 = dot(p, p);
  return p * (1.0 + k1 * r2 + k2 * r2 * r2);
}
// Cauchy: n(λ) = A + B/λ², λ in µm; relative to green
fn cauchyScale(B: f32) -> vec3<f32> {
  let lam2 = vec3<f32>(0.650, 0.550, 0.450) * vec3<f32>(0.650, 0.550, 0.450);
  let n = 1.0 + B / lam2;
  return n / n.y;                                           // (<1, 1, >1)
}
// let c = (uv - 0.5) * aspectVec; let s = cauchyScale(dispersion);
// sample R at brownConrady(c * s.x, k1, k2), G at c * s.y, B at c * s.z; clamp uv.
```

**D1 — Vorticity confinement for a velocity field stored in C.xy.**

```wgsl
fn curlAt(c: vec2<i32>) -> f32 {
  let r = textureLoad(dataTextureC, c + vec2<i32>( 1, 0), 0).y;
  let l = textureLoad(dataTextureC, c + vec2<i32>(-1, 0), 0).y;
  let t = textureLoad(dataTextureC, c + vec2<i32>( 0,-1), 0).x;
  let b = textureLoad(dataTextureC, c + vec2<i32>( 0, 1), 0).x;
  return 0.5 * ((r - l) - (b - t));
}
// in main(): clamp coords to [1, res-2] before calling curlAt
let w  = curlAt(coord);
let gx = 0.5 * (abs(curlAt(coord + vec2<i32>(1, 0))) - abs(curlAt(coord - vec2<i32>(1, 0))));
let gy = 0.5 * (abs(curlAt(coord + vec2<i32>(0, 1))) - abs(curlAt(coord - vec2<i32>(0, 1))));
let n  = vec2<f32>(gx, gy) / max(length(vec2<f32>(gx, gy)), 1e-5);
let confine = vec2<f32>(n.y, -n.x) * w * confinementEps;  // N × ω in 2D
vel += confine * dt;
```

**D2 — Isotropic 9-point Laplacian (drop-in for the 5-point one).**

```wgsl
fn lap9(c: vec2<i32>, ch: i32) -> f32 {
  var s = 0.0;
  s += 0.20 * (textureLoad(dataTextureC, c + vec2<i32>( 1, 0), 0)[ch] + textureLoad(dataTextureC, c + vec2<i32>(-1, 0), 0)[ch]
             + textureLoad(dataTextureC, c + vec2<i32>( 0, 1), 0)[ch] + textureLoad(dataTextureC, c + vec2<i32>( 0,-1), 0)[ch]);
  s += 0.05 * (textureLoad(dataTextureC, c + vec2<i32>( 1, 1), 0)[ch] + textureLoad(dataTextureC, c + vec2<i32>(-1, 1), 0)[ch]
             + textureLoad(dataTextureC, c + vec2<i32>( 1,-1), 0)[ch] + textureLoad(dataTextureC, c + vec2<i32>(-1,-1), 0)[ch]);
  return s - textureLoad(dataTextureC, c, 0)[ch];
}
```

**E1 — Orbit trap and smooth iteration inside an existing escape loop.**

```wgsl
var trap = 1e9;
var i = 0.0;
for (var k = 0; k < MAX_IT; k = k + 1) {
  z = cmul(z, z) + c;                                       // the file's own iteration — do not change it
  trap = min(trap, length(z - trapCenter));                 // idea: orbit trap
  let esc = f32(dot(z, z) > 256.0);
  i += 1.0 - esc;                                           // branchless counter
}
let smoothIt = i + 1.0 - log2(max(log(max(length(z), 1.0001)) / log(16.0), 1e-5));
let vein = exp(-trap * veinSharpness);                      // 0..1, multiply into the existing colour
```

**E2 — Step-count ambient occlusion on an already-marched surface.**

```wgsl
fn aoFive(p: vec3<f32>, n: vec3<f32>) -> f32 {
  var occ = 0.0; var sca = 1.0;
  for (var i = 1; i <= 5; i = i + 1) {
    let h = 0.01 + 0.12 * f32(i) / 5.0;
    occ += (h - map(p + n * h)) * sca;                      // map() is the file's own SDF
    sca *= 0.5;
  }
  return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}
```

**F1 — Thin-film reflectance and Airy disc (compact, guarded).**

```wgsl
fn thinFilm(cosT: f32, thicknessNm: f32, n: f32) -> vec3<f32> {
  let lam = vec3<f32>(650.0, 550.0, 450.0);
  let delta = (4.0 * 3.14159265 * n * thicknessNm * max(cosT, 0.05)) / lam;
  let c = cos(delta * 0.5);
  return c * c;                                             // multiply into the existing specular/reflection term
}
fn airy(x: f32) -> f32 {                                    // (2 J1(x)/x)^2, polynomial J1 for x < ~8
  let xs = max(abs(x), 1e-4);
  let j1 = xs * (0.5 - xs * xs * (0.0625 - xs * xs * (0.0026042 - xs * xs * 0.0000543)));
  let v = 2.0 * j1 / xs;
  return v * v;
}
```

### 12.4 Implementation order — forced, not advisory

1. **Idea Card first** (§2), from the *current* file. `KEEP VERBATIM` must list the kernel,
   the modes and the param roles by name. No formula is chosen yet.
2. **Mechanism interrogation** (§12.1). Answer tactics 1, 2, 3 and 6 in writing. Every idea
   on the card is phrased with the shader's own nouns.
3. **Formula admission** — pick **at most two** rows from the table of *this file's* family in
   §12.2. Each must pass all three:
   - **Family match:** the row is in this shader's family table, or you can write one sentence
     why this shader *is* that family (a lens flare that is also a thin-film is fine; a sharpen
     that is "also optical" is not).
   - **Operates on what exists:** the formula consumes a quantity the file already computes
     (taps, gradient, height, velocity, iteration, normal) or the pointer/history it already
     owns. If it needs new state, new bindings, a new solver or a spring the file does not have,
     it fails.
   - **Deletion test** (§12.1) passes in both directions.
4. **Implement inside the existing main path.** Same modes, same kernel family, same param
   mapping. New tuning constants are literals or derive from an existing param's *existing*
   role; saved `params` stay byte-exact. Name each idea in a `// ── Idea n: …` comment at the
   place it acts, so a coordinator can point at it from the diff.
5. **Record the formula names** in `NOTES.md` and in the WGSL `Ideas:` line
   (e.g. `Ideas: density-weighted grain (§12.2A); halation (§12.2A)`).
6. **Floor** (§3), then gates (§5 closeout). A packing is stated and truthful (§8).

**Batch de-duplication.** The same §12.2 row may appear on at most **two** files in a batch
unless the batch theme *is* that mechanism (an all-VHS batch may use the chroma delay line
everywhere — and must then differentiate on the second idea). The coordinator lists the
formula names per file in `COORDINATOR_REVIEW.md`; a batch where ≥3 files share both
formulae fails §9's "no generic overlay" box regardless of Naga.

### 12.5 Prefer / avoid

The right column is not forbidden in the catalog — it is forbidden *as an upgrade on that
family*. Springs, ripple fronts, IQ palettes, holographic scanlines and oil-slick chroma all
have homes; those homes are the files whose identity they already are.

| Family | Prefer (native extension) | Avoid (overlay / costume) |
|---|---|---|
| Post-process / photographic | Better kernel, adaptive amount from local statistics, anti-halo, film-response curve, device artifacts (grain, halation, cos⁴, chroma delay) | Spring cursor, click wavefronts, IQ cosine palette, neon edge pop, raymarched anything, "clarity lens" on a filter that was never pointer-led |
| Distortion / glitch | Latched states via C, sync-model timing, block-domain quantization, lens models with real coefficients, field/scanline masks | Thin-film iridescence as the look, particle sparkles, springs, a second unrelated tear system stamped from the previous file |
| Interactive / brush | Kinematics from the spring the file already owns, paint-field gradient, dwell, drying, wet edge, granulation | Adding a spring to a non-pointer effect, replacing the brush with a solver or particles, galaxy/ferrofluid under the cursor |
| Liquid / sim | One extra force or term in the existing solver, better stencil, better advection, dispersion, tension | Replacing the solver with display-history sparkles, Gray-Scott on a non-RD liquid, promoting a raw-field A to "display history" |
| Generative / SDF | Orbit trap, fold material, step AO, curvature wear, additive twist, better marcher, golden-angle spacing | A different creature or fractal, swapping the palette to IQ cosine as the whole look, scanlines/glitch costume, bolting a liquid sim onto an SDF |
| Lighting / optical | One physical term (Fresnel, HG, Beer–Lambert, Cauchy, Airy, Snell), energy conservation, ghost geometry | Ripple shockwaves "for interactivity", neon edge detection, kaleidoscope folds on a flare |
| **Every family** | Branchless masks, guarded math, `clamp` before ACES, exact C loads, truthful A packing | Frame-hash strobing (except native grain), `fwidth` in compute, `pow` with a possibly negative base, `plasmaBuffer[1..]` as colour, two "conveyors" |

### 12.6 Worked example — `analog-film-degrade`, second pass with two §12.2 formulae

Current file (`public/shaders/analog-film-degrade.wgsl`, shipped 2026-09-06): per-channel
grain, gate-weave hairlines, C print-through; A = ACES display RGBA; params
`grain / fade / scratchFreq / vignette`. The grain today is a flat ±0.5 hash scaled by the
grain slider — identical in a white sky and a black coat, which no print does.

```
SHADER: analog-film-degrade
IDENTITY (one sentence): the source photo as a worn, projected film print — grain, fade,
  scratches, dust, vignette; still a photo filter a colourist would use.
KEEP VERBATIM: 4 params and their roles (grain → amplitude, fade → sepia/desat/C print-through,
  scratchFreq → weave + hairlines + dust, vignette → radial falloff); per-channel grain seeds;
  gate-weave hairlines; sepia/desat fade chain; 0.10·fade C print-through; ACES on display;
  A = display RGBA (unchanged).
MECHANISM INTERROGATION:
  tactic 2 (physics one step further): a print's grain is a function of density; bright
    light through the emulsion bounces off the base and fogs the red layer (halation).
  tactic 3 (promote an intermediate): `luma` is already computed for the fade chain — reuse
    it to weight grain and to find clipped highlights.
ADD (2 native ideas):
  1. Density-weighted grain — §12.2A "Selwyn-ish": σ(L)=k·sqrt(L(1−L)) multiplies the
     EXISTING gR/gG/gB. Midtones grainy, clear base and dense shadow clean. Grain slider
     keeps its role (overall amplitude).
  2. Halation — §12.2A: 4-tap clipped-highlight bloom, red-biased (1.0, 0.35, 0.10), with
     the core slightly bleached toward luma so energy is moved, not invented. Amount rides
     the existing `fade` slider (a faded print shows halation more), no new param.
FORMULA ADMISSION: both rows are in the photographic table; both consume luma the file
  already computes plus `readTexture` taps; deleting either leaves exactly this effect;
  keeping either alone is not a film filter → additive, not replacing.
FORBID on this file: springs, click fronts, IQ palette, holographic scan, raymarch, any new
  param, any change to the sepia mix constants.
A PACKING: ACES display RGBA (unchanged).
```

Diff sketch — the two ideas land where the quantities they need already exist:

```wgsl
  // (unchanged) let grainSeed = …; let gR/gG/gB = …;
  // ── Idea 1: density-weighted grain (§12.2A) ─────────────────────────
  // Real granularity peaks in the midtones and vanishes in clear base /
  // dense blacks. The flat hash grain is kept; only its amplitude changes.
  let srcLuma = clamp(dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114)), 0.0, 1.0);
  let density = sqrt(max(srcLuma * (1.0 - srcLuma), 0.0)) * 2.0;   // 0 → 1 → 0
  rgb += vec3<f32>(gR, gG, gB) * grainIntensity * mix(0.25, 1.0, density);

  // (unchanged) weave / hairlines / dust …

  // ── Idea 2: halation (§12.2A) ───────────────────────────────────────
  // Light that passes the emulsion reflects off the base and re-exposes the
  // red-sensitive layer: a warm halo around clipped highlights, with the
  // core bleached rather than brightened (energy moved, not added).
  let hr = 3.0 / res;
  var hal = 0.0;
  for (var k = 0; k < 4; k = k + 1) {
    let o = vec2<f32>(f32(k & 1) * 2.0 - 1.0, f32(k >> 1) * 2.0 - 1.0) * hr;
    let tuv = clamp(uv + o, vec2<f32>(0.0), vec2<f32>(1.0));
    let t = textureSampleLevel(readTexture, u_sampler, tuv, 0.0).rgb;
    hal += max(dot(t, vec3<f32>(0.299, 0.587, 0.114)) - 0.85, 0.0);
  }
  hal *= 0.25 * (0.4 + 0.6 * fadeAmount);
  rgb += hal * vec3<f32>(1.0, 0.35, 0.10);
  rgb = mix(rgb, vec3<f32>(srcLuma), clamp(hal * 0.5, 0.0, 0.5));

  // (unchanged) luma / sepia / fade chain / C print-through / vignette / ACES …
  let damage = clamp(abs(gR) * density + (1.0 - vignette) + hair + hal * 0.3, 0.0, 1.0);  // alpha stays semantic
```

Header `Ideas:` line becomes
`Ideas: per-channel grain; continuous gate-weave hairlines; C print-through; density-weighted grain (§12.2A); halation (§12.2A)`
with `Upgraded: 2026-09-06, <date>`. JSON `params` untouched; `features` unchanged (no new
audio or pointer claim). Record with `npm run upgrades:record` (§8b).

**Self-review against §12.4.** Identity preserved: a colourist still reads it as a film filter;
both ideas are findable from the two `// ── Idea n` comments; neither idea is reusable
verbatim on a sharpen, a VHS or a liquid, so it cannot become a batch overlay. The same two
formulae on a *second* film shader in the batch would still pass only if that file's card
chose a different second idea.

### 12.7 Coordinator additions (append to the §9 checklist)

- [ ] `BRIEFS.md` shows the mechanism interrogation answers (§12.1), not just the card
- [ ] Every formula used is named by its §12.2 row in `NOTES.md` and the `Ideas:` line
- [ ] No §12.2 row appears on more than two files in the batch (unless the batch theme is that mechanism)
- [ ] Each formula consumes a quantity the file already had — no new solver, state, binding or spring
- [ ] No `fwidth`/`dpdx`, no `pow` with an unguarded base, no negative input into ACES
