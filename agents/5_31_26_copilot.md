# 2026-05-31 — Copilot CLI Swarm Execution Plan (Tactical Edits Layer)

**Date**: 2026-05-31  
**Focus**: High-volume, low-ambiguity, surgical tactical edits — running in parallel with Kimi (v2 implementation/repair) and Claude (deep optimization + polish)  
**Role**: Copilot CLI = precise, mechanical, high-certainty edits that do not require deep creative ideation or heavy performance reasoning

**Four-way parallel swarm on 2026-05-31**:
- Kimi (v2) → volume implementation + bind-group repair
- Claude → deep optimization + multi-pass + visual transcendence
- Grok → creative direction + high-signal signature upgrades
- **Copilot** → tactical mechanical hygiene at scale

All four tracks are deliberately disjoint.  
**Strict Constraint**: Do NOT touch **any** shaders assigned to Kimi, Claude, or Grok today.

**Grok's shaders (also forbidden for Copilot)**: `ambient-liquid-coupled`, `alpha-reaction-diffusion-rgba`, `alpha-multi-state-ecosystem`, `gen-abyssal-chrono-coral`, `gen-auroral-ferrofluid-monolith`, `alucinate-hdr`

**Kimi's shaders (forbidden)**: `gen-superfluid-quantum-foam`, `plasma`, `kaleido-scope-grokcf1`, `velocity-field-paint`, `pixel-sand`, `temporal-rgb-smear`, `liquid-tensor-vortex`, `depth-chromatic-bloom`

**Claude's shaders (forbidden)**: `aurora-rift-pass1`, `aurora-rift-pass2`, `quantum-foam-pass1`, `tensor-flow-sculpting`, `hyperbolic-dreamweaver`, `gen-chronos-labyrinth`, `volumetric-god-rays`

---

## Copilot Tactical Mission

You excel at:
- Applying known, proven mechanical patterns at scale (canonical binding renames, header insertion, simple JSON metadata fixes)
- Small, safe, reviewable diffs
- Cleanup that is 95%+ mechanical once the pattern is known
- Adding Standard Hybrid Headers + basic chunk attribution to shaders that are "almost there"
- Minor param renaming in JSONs when the semantic intent is obvious
- Ensuring every shader has the current 13-binding contract (no invention, just alignment)

You do **not** invent new visual techniques, major refactors, or creative "wow" upgrades — those belong to Kimi, Claude, and Grok (see `5_31_26_grok.md`).

---

## Today's Copilot Tactical Batch — 10 Shaders (Disjoint)

All of these are small-to-medium effects that are likely to benefit from precise, low-risk mechanical work.

| # | Shader ID | Primary Tactical Task(s) | Expected Output Style | Notes |
|---|-----------|---------------------------|-----------------------|-------|
| T1 | `_hash_library` | Ensure it uses only the current 13-binding contract + has a minimal Standard Hybrid Header. No functional changes. | Precise diff | This file is special — be extremely conservative |
| T2 | `adaptive-mosaic` | Apply canonical binding rename pattern if old names present. Add Standard Hybrid Header stub. | Small edit block | Likely has old texture names |
| T3 | `aero-chromatics` | Binding alignment + add basic header + ensure `plasmaBuffer` is declared even if unused | Header + binding fix | Quick metadata pass |
| T4 | `aerogel-smoke` | Canonical bindings + Standard Hybrid Header + simple alpha comment | Header + 1-2 line alpha note | Smoke effects often have alpha issues |
| T5 | `analog-film-degrade` | Binding cleanup + retro-glitch JSON features/tags refresh (add "retro", "glitch", "film" if missing) | Binding + JSON delta | Tactical JSON hygiene |
| T6 | `anamorphic-flare` | Binding alignment + insert Standard Hybrid Header with "Chunks From: anamorphic-flare" self-ref | Header insertion | Common flare family |
| T7 | `artistic_painterly_oil` | Binding fix + header + ensure `writeDepthTexture` pass-through if depth is read | Small structural edit | Artistic category often lags on modern bindings |
| T8 | `ascii-flow` | Canonical bindings + header + minor JSON param label cleanup if obviously wrong | Binding + JSON | ASCII/retro family |
| T9 | `alpha-hdr-bloom-chain` | Binding + header + confirm it writes premultiplied alpha (add comment only if obvious) | Binding + 1 comment | HDR chain — be careful |
| T10 | `ambient-liquid` | Binding alignment + Standard Hybrid Header (liquid-effects category) | Header + binding | Good simple liquid baseline for future work |

**Rule**: If a shader already has the full modern 13-binding contract and a recent Standard Hybrid Header, **skip it or do only the tiniest JSON metadata hygiene**. Do not invent work.

---

## Tactical Edit Protocol (Copilot)

For every shader in the batch:

1. Read the current `.wgsl` and its `.json` definition.
2. Run a mechanical checklist:
   - Does it declare exactly the 13 canonical bindings in the exact current order and names?
   - Does it have a Standard Hybrid Header (even a minimal one)?
   - Are there any obvious old names (`outputTex`, `videoSampler`, `iTime`, `mouse`, `outTex`, etc.)?
   - Does the JSON have at least the required fields + reasonable `features`/`tags`?
3. Make the smallest possible correct edit that brings it into alignment with the current contract.
4. Output format preference (in order):
   - Precise unified diff (best for review)
   - Or clearly marked "replace this exact block with this exact block"
5. Write a 2–4 bullet note to `swarm-outputs/copilot-edits/<shader-id>.copilot-edits.md`:
   - What mechanical pattern was applied
   - Any JSON changes (if any)
   - Confidence level (High / Medium — never Low on tactical day)
   - One sentence on anything that looked suspicious but you left alone

**Never**:
- Add new visual algorithms
- Change workgroup size unless it is a trivial 1:1 rename of an obviously wrong value on a shader with no `var<workgroup>`
- Invent new parameters
- Touch multi-pass coordination logic

---

## Execution Checklist

1. [ ] Confirm you have the latest `agents/KIMI_CLI_SWARM_UPGRADE_PLAN.md` (v2) and the two sibling daily plans (`5_31_26_kimi.md`, `5_31_26_claude.md`) for context.
2. [ ] For each of the 10 shaders:
   - Perform the Tactical Edit Protocol
   - Write the small `.copilot-edits.md` artifact immediately
3. [ ] After the batch, run:
   ```bash
   node scripts/generate_shader_lists.js
   node scripts/check_duplicates.js
   ```
   if you touched any JSON files.
4. [ ] Append a short session log at the bottom of **this file**:
   - How many shaders needed actual binding work vs. just header insertion?
   - Any shaders that were surprisingly clean?
   - Any patterns you noticed that should be turned into a reusable "Copilot Tactical Macro" for future weeks?
5. [ ] Do a final pass over your edits and mark any that feel like they might benefit from a quick Claude glance (rare, but possible).

---

## Output Locations

- WGSL edits → directly into `public/shaders/` (hot-swap)
- JSON deltas (minimal) → `shader_definitions/<category>/`
- Your notes → `swarm-outputs/copilot-edits/<shader-id>.copilot-edits.md`

---

## Success Criteria

- 100% of the 10 shaders now declare the exact current 13-binding contract.
- At least 8 of 10 have a Standard Hybrid Header (even if minimal).
- All diffs are small, reviewable, and low-risk.
- Zero functional regressions introduced.
- Your notes are clear enough that a human reviewer can accept the batch in < 10 minutes.

---

**You are the precision surgical tool of the swarm today. Do the boring, necessary, high-certainty work so Kimi and Claude can stay in their high-leverage lanes.**

— Grok (Swarm Process Architect), 2026-05-31

---

## Session Log (fill during/after run)

**Shaders processed:** 10  
**Binding fixes applied:** 0 actual bind-group repairs; all 10 shaders already matched the current 13-binding contract.  
**Headers inserted:** 10 header standardization passes (9 full Standard Hybrid Header refreshes plus 1 minimal completion on `analog-film-degrade`).  
**JSON hygiene passes:** 9 definition files updated (`category` normalization on all 9, plus `depth-aware` on `aero-chromatics`, `glitch` + URL normalization on `analog-film-degrade`, and an `ascii` tag on `ascii-flow`).  
**Notable patterns observed:** This batch had metadata drift rather than binding drift: older header categories lagged current library placement, several JSON definitions still omitted `category`, and two shaders (`aerogel-smoke`, `alpha-hdr-bloom-chain`) mainly needed alpha semantics documented instead of behavior changes.  
**Candidates for future Copilot macros:** 1. Auto-insert Standard Hybrid Headers from shader ID + folder category. 2. Add missing JSON `category` from parent directory. 3. Detect alpha-as-metadata cases and prefer comment-only clarification. 4. Optional Claude glance: `alpha-hdr-bloom-chain` if downstream passes ever require true premultiplied alpha, and `ambient-liquid` if category-family cleanup becomes worth the churn.  