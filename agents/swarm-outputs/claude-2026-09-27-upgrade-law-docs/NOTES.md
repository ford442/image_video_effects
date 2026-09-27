# 2026-09-27 — Upgrade plan docs aligned to the live law (docs only)

> An upgrade **adds 2–4 named, effect-native visual ideas** to the existing picture.
> Bindings / ACES / alpha / sliders / `updatedParams` / naga / springs-for-completeness
> are the **floor**, not the upgrade.
> — [`docs/SHADER_UPGRADE_BATCH.md`](../../../docs/SHADER_UPGRADE_BATCH.md) (live; unchanged — no contradicting sentence found)

No WGSL, JSON definitions, catalogs, `queue.json`, `docs/BINDING_CONTRACT.md`,
`agents/WGSL_BUILTINS_GENERATIVE.md` or dated new-shader briefs were touched.

## A. Upgrade-law banner (verbatim, under the H1)

- `shader_plans/MASTER_INDEX.md`
- `shader_plans/liquid_upgrades.md`, `chromatic_upgrades.md`, `generative_upgrades.md`,
  `distortion_upgrades.md`, `glitch_upgrades.md`, `glitch_shaders_upgrade_plan.md`,
  `lighting_upgrades.md`, `interactive_upgrades.md`
- `notes/shaders_upgrade_plan.md` — old "What Upgrade Means Here" block replaced by the banner
- `notes/SHADER_UPGRADE_MANIFEST.md` — banner above its existing historical line
- `agents/KIMI_CLI_SWARM_UPGRADE_PLAN.md` (matches `*upgrade*plan*`)

The category scouts and `MASTER_INDEX.md` also got a "Reading the per-shader entries" note:
each "Transform / Replace / Upgrade to simulate / → New Name" line is a candidate idea to
add, and parameter lists map onto the existing param roles. Saved `params` stay byte-exact.

## B. Framing softened (scout content kept)

- `MASTER_INDEX.md` — mission line, "Candidate idea (additive)" columns, tier-1 rows say
  the base motif stays, roadmap rewritten as order-of-work (Phase 4 = more ideas on files
  that already have the floor), springs pointer-led only, themes and ✓ grid are candidates
- `liquid_upgrades.md` — roadmap as native ideas per file; shared utils optional;
  "each upgraded shader should expose" 5 params → candidate roles only
- `distortion_upgrades.md` — roadmap reframed; uniform-struct sketch marked historical
  (engine uniforms fixed); helper library optional; "cohesive suite" conclusion reworded
- `generative_upgrades.md` — goal line; algorithm-swap entries (orb→attractor, Julia→Newton, …)
  read as a fused layer; gen_orb keeps the orb; line estimates are ordering only;
  templates → optional helpers; workgroup 8×8 → 16×16 floor; success metrics = ideas visible
- `lighting_upgrades.md` — goal line, "idea pool", est. lines = sizing hint, new-shader
  section labeled, shared lib optional, param standardization → new shaders only,
  "Transform from → to" = added-detail direction, conclusion drops "cohesive" system
- `chromatic_upgrades.md` — summary, Prismatic Shockwave and crawler RD lines additive
- `glitch_upgrades.md` — "Missing Science" is an idea pool, param mapping → new shaders only,
  new-shader proposals labeled
- `glitch_shaders_upgrade_plan.md` — research is an idea pool; "all glitch shaders should
  support" params → candidates; helper lib optional; CRT pass only where native;
  TemporalState uniform marked historical; Part 10 rewritten as per-file idea work
- `interactive_upgrades.md` — springs only where already pointer-led (fisheye, page curl);
  `extraBuffer[0..299]` layouts flagged as violating the floor; "all upgraded shaders
  should expose" → new shaders only
- `notes/shaders_upgrade_plan.md` — size = order only; no template building; huge files
  deferred, never "complete rewrite candidates"; automated passes = hygiene
- `notes/SHADER_PIPELINE_ENHANCEMENT.md` — live-law pointer + Idea Card criterion added
  to "An upgrade is successful if"; "template shader" → reference shader
- `notes/EFFECT_SHADER_UPGRADE_MANIFEST.md`, `notes/GENERATIVE_SHADER_UPGRADE_MANIFEST.md` —
  line-count expansion labeled history, not the definition of upgraded

## C. New-shader queue

- `shader_plans/README.md` — note that dated briefs are new shaders, category scouts are
  idea scouts, and the upgrade contract is separate

## D. Historical / plumbing pointer

- `agents/CLOUD_UPGRADE.md` (labeled live plumbing; §2.0 now says the live contract owns
  the creative law and ACES / bindings / alpha / springs are floor or opt-in tools)
- `agents/weekly_upgrade_swarm.md`, `agents/upgrade_swarm.md`,
  `agents/GENERATIVE_UPGRADE_SWARM.md`, `agents/4_AGENT_SWARM_PROMPT.md`,
  `agents/grok_build_upgrade.md`, `composer.md`,
  plus `agents/EFFECT_UPGRADE_SWARM.md`, `agents/shader-upgrade-round-2026-05.md`
