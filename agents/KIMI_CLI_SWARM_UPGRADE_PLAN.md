# Kimi-CLI Swarm Upgrade Plan — v2 (Enhanced Operating Procedure)

> **Status**: Active — v2.1 (Enhanced Kimi Agent Swarm OP)  
> **Last Updated**: 2026-05-31  
> **Owner**: Grok (Swarm Process Architect) + Kimi implementation  
> **Scope**: Make the Kimi Code CLI the highest-volume, highest-consistency shader implementation engine in the Pixelocity weekly upgrade swarm while minimizing downstream Claude cleanup.

---

## How kimi-cli is invoked today (unchanged constraints)

`scripts/scan-shaders-naga.py` and `scripts/run-upgrade-swarm.js` call:

```bash
kimi-cli --no-stream   < prompt via stdin
```

**Hard constraints Kimi prompts must respect**:
- stdin-only (no `--system` flag)
- 120s wall-clock budget — concrete bullets and repeated critical rules beat long CoT
- `--no-stream` → stdout parsed as one blob; we rely on **exactly one** ```wgsl fenced block
- No filesystem or tool access — everything (header, tactics, creative brief, similar shaders, output contract) must be inlined
- Line cap discipline is effective (`current + 30~50`)

---

## Kimi Strengths to Lean On (v2)

1. **Pattern completion of self-contained WGSL** when given the exact 13-binding header + target line budget.
2. **Localized high-volume repair** — when handed a clear error + theme + the canonical header, it is extremely reliable at canonical binding fixes, alpha semantics, and audio reactivity injection.
3. **Honoring explicit output schemas** when the critical rule is stated at the **top, middle, and footer** of the prompt.
4. **Re-using injected snippets** (the 12 graphical tactics, warpedFBM, kaleido, bass_env, etc.) with high fidelity.
5. Speed and structured output when the prompt is tight and the "wow mandate" + creative brief are vivid.

---

## Weaknesses & Mitigations (v2 — what changed)

| Weakness | Old Mitigation | v2 Mitigation |
|----------|----------------|---------------|
| Drifts to generic "cool noise" | 1-sentence theme | **Grok creative brief + "wow mandate" + 2–3 "differentiate from these existing shaders"** injected per task |
| Hallucinates bindings | Restate header | Header is now **first** after the creative brief + triple output contract |
| Trailing prose after fence | `_extract_first_wgsl_block` + instruction | **Triple instruction** (top/mid/footer) + **post-generation kimi-output-guard** that rejects any response with text after the fence |
| Over-comments / low math density | Line cap | Line cap + "math density > commentary" + guard that counts advanced tactic usage |
| Repetitive or safe-but-not-transcendent results | None | Mandatory "similar shaders" differentiation block + weekly "this week we push X" aesthetic directive |
| No standard header on new shaders | None | **New shader creation path** starts from a minimal canonical skeleton that already contains the full AGENTS.md Standard Hybrid Header |

---

## Kimi Agent Swarm Operating Procedure — v2 (The Core Process)

### Phase 0 — Pre-Week (Grok)
- Grok runs Discovery & Ideation.
- Produces `swarm-outputs/weekly-ideation-YYYY-WW.md` containing 6–10 ranked briefs.
- Each brief contains: name, one-sentence hook, visual reference aesthetic, technical differentiator, suggested params, anti-patterns, wow mandate, target lines, role.

### Phase 1 — Weekly Handoff (Grok → Kimi boundary)
- For every item that will go to Kimi, a **kimi-brief** is generated:
  `swarm-tasks/kimi-briefs/<shader-id>.md`
- This file contains only the high-signal creative brief + 2–3 "similar but clearly differentiate from" summaries + the wow mandate.
- This is the single highest-leverage new artifact.

### Phase 2 — Per-Shader Kimi Invocation (the prompt Kimi actually receives)

Every prompt follows this rigid order:

1. **Creative Spark Block** (first thing Kimi sees)
   - The exact one-sentence hook + visual reference + wow mandate from the ideation brief.
   - "This week we are pushing: [aesthetic/technical direction]."

2. **Differentiation Block**
   - 2–3 similar existing shaders with one-sentence "what they do" + "your version must not feel like this."

3. **Output Contract (stated three times)**
   - "Output **ONLY** the complete WGSL inside one ```wgsl fence."
   - "Nothing — not a blank line, not 'here is the improved version' — may appear after the closing ```."
   - "If you violate this, the pipeline will reject the output and you wasted the turn."

4. **Immutable Contract Block**
   - Full 13-binding header (verbatim, first time it appears)
   - Uniforms struct
   - @workgroup_size rule

5. **If NEW shader creation**: "Begin the WGSL with the exact Standard Hybrid Header from AGENTS.md (date + By: Kimi Code CLI (weekly swarm)). You are completing from the canonical skeleton below."

6. **Context** (tight)
   - Current WGSL (or minimal canonical skeleton for new work)
   - Role toolkit excerpt (Visualist/Algorithmist/etc.) focused on functions, not essays
   - The 12 Kimi Graphical Tactics

7. **Line budget + final triple reminder**

**For repair work** (naga/bind-group/etc.): the same contract, but the "creative brief" becomes a crisp one-sentence diagnosis + "apply the canonical binding rename + meaningful alpha + audio reactivity pattern."

### Phase 3 — Post-Generation Guard (before any write)
A guard (script or manual checklist) enforces:
- Exactly one ```wgsl block and zero bytes after it
- All 13 canonical bindings present
- (For creation) Standard Hybrid Header present with correct fields
- At least two advanced tactics from the supplied set used
- No naive `vec4(..., 1.0)` final write in non-background shaders (heuristic)
- Line count within budget

Failures land in `swarm-outputs/kimi-rejects/` with the raw output + the exact prompt that produced it (for prompt evolution).

### Phase 4 — Handoff to Claude
Kimi (or the orchestrator) also writes:
`swarm-outputs/kimi-notes/<shader-id>.notes.kimi.md` (max 3 bullets)
- What I changed / the core technique introduced
- What I'm proud of (the surprising or high-wow bit)
- What might need a human eye (performance at 2048², edge cases, etc.)

Claude then performs the final optimization + polish pass (header standardization, last 10% visual transcendence, naga/runtime verification).

### Batching Strategy
- Kimi dispatch remains **sequential** (local CLI stability + 120s budget).
- Group the weekly batch into 2–3 **themed micro-batches** (e.g., "all bind-group canonical renames", "new generative seeds", "audio-reactive upgrades").
- This allows batch-level context injection ("this micro-batch must differentiate from the existing 14 liquid shaders by pushing 3D tensor advection + transmission alpha").

---

## Required New Artifacts (create these in the first week of v2)

| Artifact | Location | Purpose |
|----------|----------|---------|
| `weekly-ideation-YYYY-WW.md` | `swarm-outputs/` | Grok's ranked creative briefs |
| `kimi-briefs/<id>.md` | `swarm-tasks/kimi-briefs/` | High-signal handoff from Grok to Kimi (one per task) |
| `kimi-output-guard.js` (or .py) | `scripts/` | Post-generation validator that enforces the triple contract before write |
| `*.notes.kimi.md` | `swarm-outputs/kimi-notes/` | 3-bullet handoff from Kimi to Claude |
| `kimi-rejects/` | `swarm-outputs/kimi-rejects/` | Raw failed outputs + the prompt that generated them (learning loop) |

---

## The Single Recommended Kimi Prompt Template (use this verbatim as the skeleton)

```markdown
# KIMI SWARM TASK — [CREATION|UPGRADE|REPAIR] — [shader-id or batch-name]

## CREATIVE BRIEF (Grok ideation — this is the spark)
[One-sentence visual hook + reference aesthetic + wow mandate]

This week / this repair batch we are pushing: [direction]. Do not produce generic patterns.

## DIFFERENTIATE FROM (mandatory)
- [existing shader A]: does X via Y — your version must feel clearly distinct
- [existing shader B]: ...

## OUTPUT CONTRACT (read three times — non-negotiable)
1. Your **entire response after the closing ``` of the WGSL block must be completely empty**. No explanations, no "done", no blank lines.
2. If this is a NEW shader, the very first lines of the WGSL **MUST** be the exact Standard Hybrid Header from AGENTS.md with today's date and "By: Kimi Code CLI (weekly swarm)".
3. Alpha must carry semantic meaning (bloom weight, depth, effect strength, Fresnel, etc.). Never end a non-background shader with `vec4(rgb, 1.0)`.
4. You must use at least two techniques from the supplied tactics or role toolkit.

## IMMUTABLE 13-BINDING CONTRACT (copy EXACTLY)
```wgsl
@group(0) @binding(0) var u_sampler: sampler;
... (full 13 bindings + Uniforms struct) ...
```

## CURRENT SOURCE / CANONICAL SKELETON
```wgsl
... (current file or minimal correct skeleton) ...
```

## ROLE TOOLKIT (Visualist / Algorithmist / Interactivist / Optimizer — excerpt)
... (only the concrete functions and patterns needed) ...

## 12 KIMI GRAPHICAL TACTICS (apply where appropriate)
... (the full 12 tactics block) ...

## LINE BUDGET & FINAL REMINDER
Target: ~XXX lines (±15%). Math density over commentary.

If any text appears after the final WGSL fence, the pipeline **will reject** this output and you will have wasted the turn. Stop the moment you close the fence.
```

---

## 12 WGSL Graphical Tactics (unchanged — still excellent)

(The full set of 12 tactics from v1 — hue_preserve_clamp, ACES, IGN dither, aa_step, smin, warpedFBM, kaleido, HEX_TAPS, bass_env, depth-aware fog, anti-moiré LOD, premultiplied writeback — remain the canonical injection set. They are reproduced in every Kimi prompt under the "12 KIMI GRAPHICAL TACTICS" section.)

---

## Concrete Implementation Steps for v2 Adoption (this week)

1. **Directory & Artifact Setup** (done 2026-05-31)
   - `swarm-tasks/kimi-briefs/`
   - `swarm-outputs/kimi-notes/`
   - `swarm-outputs/kimi-rejects/`

2. **Guard Script** (`scripts/kimi-output-guard.js` or Python)
   - Takes raw kimi-cli stdout + the shader id + mode (creation/upgrade/repair)
   - Enforces the four rules above
   - On success: returns clean WGSL + writes the `.notes.kimi.md` stub
   - On failure: writes everything to `kimi-rejects/` and exits non-zero

3. **Prompt Builder** (optional but high ROI)
   - `scripts/build-kimi-prompt.js --id=<shader> --mode=repair|creation` that assembles the template above from the kimi-brief + queue item + current source.

4. **Update existing callers**
   - `scripts/scan-shaders-naga.py::ask_kimi` — adopt the new triple-contract prompt + call the guard before writing
   - `scripts/run-upgrade-swarm.js` — when `--dispatch --kimi`, use the new `generateKimiPromptV2` that includes the creative brief + differentiation block + guard step

5. **Pilot on 2026-05-31**
   - Use the new procedure on the bind-group repair backlog + 2 new shader creation tests
   - Document results in `agents/5_31_26_kimi.md`

6. **Update AGENTS.md** (small addition)
   - New short section: "Kimi Code CLI Invocation Contract for Swarm Work"

7. **Update PLAN.md** (`agents/grok_build_upgrade.md`)
   - Reference this v2 document and the new artifacts in the weekly cadence table

---

## Success Metrics for v2

- Kimi acceptance rate through the guard ≥ 85% on first try (target 95% after one week of prompt tuning)
- Average Claude cleanup time per Kimi shader drops from ~15–25 min to < 8 min
- Every new shader created via Kimi has the full Standard Hybrid Header and at least one "surprising" behavior noted in its `.notes.kimi.md`
- Zero binding hallucinations on repair batches after the first 20 shaders processed under v2

---

## Out of Scope (still)

- Giving Kimi filesystem access or multi-file edit capability
- Replacing the Grok ideation role or the Claude optimization/review role
- Changing the 13-binding contract or Renderer.ts

---

*This v2 plan turns Kimi from a high-volume but occasionally leaky implementation tool into the reliable, high-consistency engine of the weekly shader swarm while preserving every constraint of the local kimi-cli invocation model.*

**Next action**: Execute the 2026-05-31 pilot defined in `agents/5_31_26_kimi.md`.