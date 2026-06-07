# Swarm Coordination — 2026-06-06

**Date:** 2026-06-06  
**Focus:** Shift toward **upgrading & optimizing** existing generative shaders + building flagship showcase shaders.  
**Philosophy:** Upgrade > Create new (we already have 320+ generative shaders).

---

## Sprint Status (end of Batch 2)

| Phase | Shaders | Status | Report |
|-------|--------:|:------:|--------|
| Batch 1 — ACES only | 10 | ✅ Done | `agents/swarm-outputs/batch-1-validation.md` |
| Metadata drift sweep | 97 | ✅ Done | `agents/swarm-outputs/metadata-drift-validation.md` |
| Batch 2 — full plumbing | 10 | ✅ Done | `agents/swarm-outputs/batch-2-validation.md` |
| **Total upgraded today** | **117** | ✅ | — |
| Batch 3D — multi-pass (Claude) | 5 | ✅ Done | `agents/swarm-outputs/claude-notes/*.claude-optimization.md` |
| Batch 3A/B/C | 24 | 🔲 Ready | `agents/swarm-tasks/batch-3-queue.json` |

### Batch 2 highlights
- 10/10 naga pass; 4 JSON files synced with full feature stack
- Duplicate ACES caught in `gen-mandelbox-explorer`, `gen-apollonian-gasket`
- Heaviest lift: `atmos_volumetric_fog` (ACES + audio + temporal + chromatic + dataA from near-scratch)
- All notes: `agents/swarm-outputs/kimi-notes/` (Batch 2 set)

### Remaining generative gaps (post-Batch 2 audit)
| Gap | Count |
|-----|------:|
| Missing chromatic aberration | 169 |
| Missing `dataTextureA` write | 122 |
| Metadata drift (`upgraded-rgba` ↔ no ACES) | **0** |

---

## Strategic Priorities (This Week)

| Priority | Area | Goal | Owner |
|---------|------|------|-------|
| P1 | **Batch 3 Upgrades** | 3A chromatic (4) → 3B dataA (10) → 3C chromatic sweep (10) | Kimiclaw + Codex |
| P2 | **Showcase Quality** | 1–2 flagship showcase shaders as quality references | Kimi Claw |
| P3 | **Performance & Structure** | LOD, early-exit, duplicate-fn cleanup on upgraded shaders | Claude + Codex |
| P4 | **Audio Reactivity** | Consistent `bass_env` + param mapping across upgraded shaders | All |
| P5 | **Documentation** | Queue files, validation reports, showcase criteria | All |

**Deferred (separate sprint):** GitHub #799 WASM context, #800 shader gallery UI

---

## Batch 3 Launch Queue

Machine-readable: [`agents/swarm-tasks/batch-3-queue.json`](swarm-tasks/batch-3-queue.json)

### 3A — Chromatic only (4 shaders) · Kimiclaw · **NEXT**

Already have ACES + dataA + temporal. Add chromatic chunk only.

| # | Shader ID |
|---|-----------|
| 1 | `gen-translucent-nebula` |
| 2 | `gen-alpha-aurora` |
| 3 | `gen-ghost-flame` |
| 4 | `gen-prismatic-crystal-growth` |

> `electric-eel-storm` excluded — chromatic added in Batch 2.

### 3B — dataTextureA plumber (10 shaders) · Kimiclaw · after 3A

Reads `dataTextureC` but missing `textureStore(dataTextureA, ...)`.

| # | Shader ID |
|---|-----------|
| 1 | `gen-bioluminescent-abyss` |
| 2 | `cosmic-jellyfish` |
| 3 | `cosmic-web` |
| 4 | `gen-3d-sierpinski-chaos` |
| 5 | `gen-4d-projection-dream-weavers` |
| 6 | `gen-abyssal-chrono-coral` |
| 7 | `gen-abyssal-leviathan-scales` |
| 8 | `abyssal-quantum-leviathan-skeleton` |
| 9 | `gen-alien-flora` |
| 10 | `gen-art-deco-sky` |

### 3C — Chromatic sweep (10 shaders) · Kimiclaw · after 3B

Repurposed: ACES-gap batch is empty (drift = 0). Target shaders with ACES + dataA but no chromatic.

| # | Shader ID |
|---|-----------|
| 1 | `aurora-curtain` |
| 2 | `bioluminescent-bloom` |
| 3 | `gen-belousov-zhabotinsky` |
| 4 | `gen-bio-luminescent-jelly` |
| 5 | `gen-celestial-nanite-swarm-nebula` |
| 6 | `gen-crystal-lattice-growth` |
| 7 | `gen-crystalline-mandala-bloom` |
| 8 | `gen-dla-copper-deposition` |
| 9 | `gen-dynamic-tessellation-ornate-fractal-tiles` |
| 10 | `gen-fourier-epicycles` |

### 3D — Multi-pass flagships (5 shaders) · Claude · ✅ Done

| # | Shader ID | Notes |
|---|-----------|-------|
| D1 | `gen_reaction_diffusion` | RD state in dataA |
| D2 | `gen-murmuration-phantom` | extraBuffer flock (also Batch 2) |
| D3 | `gen-navier-stokes-ink` | Velocity advection |
| D4 | `gen-belousov-zhabotinsky` | Multi-scale RD |
| D5 | `gen-conway-game-of-life` | CA state bug fix + generation counter |

### 3E — Polish pass (3 shaders) · Claude · **Blocked on 3A**

| # | Shader ID | Blocked on |
|---|-----------|------------|
| E1 | `gen-translucent-nebula` | Kimiclaw 3A + `.notes.kimiclaw.md` |
| E2 | `gen-prismatic-crystal-growth` | Kimiclaw 3A + `.notes.kimiclaw.md` |
| E3 | `electric-eel-storm` | Kimiclaw notes (chromatic done; needs LOD polish) |

---

## Agent Task Board

### Kimi Claw
**Role:** Bulk Batch 3 implementation + showcase shader creation  
**Instructions:** [`agents/swarm-tasks/kimiclaw_6626.md`](swarm-tasks/kimiclaw_6626.md)

| Task | Status | Batch | Shaders | Notes |
|------|--------|-------|---------|-------|
| **3A chromatic** | To Do | 3A | 4 | Highest impact, lowest risk — launch first |
| **3B dataTextureA** | To Do | 3B | 10 | After Codex validates 3A |
| **3C chromatic sweep** | To Do | 3C | 10 | After Codex validates 3B |
| Write `.notes.kimiclaw.md` per shader | To Do | all | 24 | Required before Claude 3E |
| Generate **Ethereal Silk** showcase | To Do | showcase | 1 new | Organic silk/veil; mouse claim |
| Generate **Fractal Ember** showcase | Backlog | showcase | 1 new | Only if Ethereal Silk quality high |
| Create `prompt-showcase-batch-1.md` | To Do | docs | — | Referenced but missing — write before showcase |
| Create `showcase-checklist-v1.md` | To Do | docs | — | 12s rotation readiness criteria |
| Review showcase audio param mapping | Backlog | showcase | — | zoom_params 1–4 semantics |

**Invocation:** `kimi-cli --no-stream` · max 2 shaders per call · gold reference: `gen-protocell-division.wgsl`

---

### Claude
**Role:** Multi-pass architecture + performance polish + second-pass transcendence  
**Instructions:** [`agents/swarm-tasks/claude_6_6_26.md`](swarm-tasks/claude_6_6_26.md)

| Task | Status | Batch | Shaders | Notes |
|------|--------|-------|---------|-------|
| **3D multi-pass** | ✅ Done | 3D | 5 | Notes in `claude-notes/` |
| **3E polish E1–E3** | Blocked | 3E | 3 | Unblock when Kimiclaw 3A lands |
| **3B Priority B continuation** | To Do | 3B+ | next 10 | After Kimiclaw 3B queue — pick from remaining 112 dataA gaps |
| Performance audit (frequent shaders) | Backlog | P3 | TBD | LOD, early-exit, branchless paths |
| Duplicate function cleanup | Backlog | P3 | Batch 3 touched | `aces_tonemap` vs `acesToneMap` pattern |

**Do not touch** Kimiclaw in-progress shaders until `.notes.kimiclaw.md` exists.

---

### Codex
**Role:** Validation gate + edge-case repair + batch reports  
**Instructions:** [`agents/swarm-tasks/codex_6626.md`](swarm-tasks/codex_6626.md)

| Task | Status | Details | Notes |
|------|--------|---------|-------|
| Validate **Batch 3A** (4 shaders) | To Do | naga + feature flags + JSON sync | Gate before 3B starts |
| Validate **Batch 3B** (10 shaders) | To Do | dataA writeback + temporal consistency | |
| Validate **Batch 3C** (10 shaders) | To Do | chromatic + no duplicate ACES | |
| Write `batch-3-validation.md` | To Do | Mirror Batch 2 report format | After 3A–3C complete |
| Metadata drift re-sweep | To Do | Confirm drift = 0 post-Batch 3 | Run audit script |
| Edge-case fixes | Ongoing | Complex `vec4<f32>()` ACES wrap, `let` reassignment | `.codex-fix.md` per fix |
| Logical structure cleanup | Backlog | Dead code, duplicate fns in Batch 3 shaders | After validation pass |
| Performance pattern audit | Backlog | Flag shaders with >8 texture loads/pixel | Feed to Claude |

**Edge cases to watch** (learned from Batch 2):
- Duplicate ACES (`acesToneMap` stacked on `aces_tonemap`)
- `dataTextureC` read without `dataTextureA` write
- Header `Features:` ≠ JSON `features`

---

### Shared / Coordination

| Task | Status | Owner | Details |
|------|--------|-------|---------|
| `swarm_6626.md` (this file) | ✅ Done | — | Living coordination board |
| `batch-3-queue.json` | ✅ Done | — | Machine-readable launch queue |
| Agent instruction docs (4 files) | ✅ Done | — | See Reference Documents |
| GitHub #801 Batch 3 | ✅ Filed | — | [Issue #801](https://github.com/ford442/image_video_effects/issues/801) |
| GitHub #800 Shader gallery | Deferred | — | [Issue #800](https://github.com/ford442/image_video_effects/issues/800) — post Batch 3 |
| GitHub #799 WASM context | Deferred | — | [Issue #799](https://github.com/ford442/image_video_effects/issues/799) — post Batch 3 |
| Define showcase readiness criteria | To Do | All | 12s rotation: idle beauty, mouse claim, audio response, alpha compositing |
| Update `WGSL_BUILTINS_GENERATIVE.md` | Backlog | Codex | Add Batch 2/3 chunks if new patterns emerge |

---

## Launch Sequence

```
Batch 2 ✅ (117 shaders)
    ↓
Kimiclaw 3A (4) ──→ Codex validate ──→ unblocks Claude 3E
    ↓
Kimiclaw 3B (10) ──→ Codex validate
    ↓
Kimiclaw 3C (10) ──→ Codex validate ──→ batch-3-validation.md
    ↓
Claude 3E polish (3) + 3B continuation (next 10 dataA)
    ↓
Kimiclaw showcase: Ethereal Silk (parallel if capacity)
```

**Parallel OK:** Claude 3E after 3A validates · Kimiclaw showcase after 3A starts · Codex drift sweep anytime

---

## Reference Documents

| Doc | Purpose |
|-----|---------|
| [`kimi_6_6_26.md`](swarm-tasks/kimi_6_6_26.md) | Master plan + reusable WGSL chunks |
| [`kimiclaw_6626.md`](swarm-tasks/kimiclaw_6626.md) | Kimi Claw implementation lane |
| [`codex_6626.md`](swarm-tasks/codex_6626.md) | Validation + edge-case repair |
| [`claude_6_6_26.md`](swarm-tasks/claude_6_6_26.md) | Multi-pass + polish lane |
| [`batch-3-queue.json`](swarm-tasks/batch-3-queue.json) | Machine-readable shader assignments |
| [`WGSL_BUILTINS_GENERATIVE.md`](WGSL_BUILTINS_GENERATIVE.md) | Core standards + canonical chunks |
| `agents/prompt-showcase-batch-1.md` | **To create** — showcase generation prompt |
| `agents/showcase-checklist-v1.md` | **To create** — 12s rotation quality gate |
| [`batch-2-validation.md`](swarm-outputs/batch-2-validation.md) | Latest completed batch report |
| [GitHub #801](https://github.com/ford442/image_video_effects/issues/801) | Batch 3 tracking issue |

**Gold reference shader:** `public/shaders/gen-protocell-division.wgsl` (Batch 2 upgraded-rgba stack)

---

## Validation Commands (orchestrator)

```bash
# Per shader
naga public/shaders/{shader-id}.wgsl

# After each sub-batch
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js

# Drift check
node -e "
const fs=require('fs'),path=require('path');
let d=0;
for(const dir of fs.readdirSync('shader_definitions')){
  const p=path.join('shader_definitions',dir);
  if(!fs.statSync(p).isDirectory()) continue;
  for(const f of fs.readdirSync(p).filter(x=>x.endsWith('.json'))){
    const j=JSON.parse(fs.readFileSync(path.join(p,f)));
    if(!(j.features||[]).includes('upgraded-rgba')) continue;
    const w=fs.readFileSync(path.join('public',j.url),'utf8');
    if(!/fn acesToneMap|aces_tonemap/i.test(w)) d++;
  }
}
console.log('drift:',d);
"
```

---

## Notes / Decisions

- Upgrade > create: 117 shaders upgraded today; Batch 3 adds 24 more before new showcase work.
- Batch 3C repurposed from empty ACES-gap list — drift is 0 after metadata sweep.
- `electric-eel-storm` removed from 3A (chromatic done in Batch 2); stays in Claude 3E for LOD polish.
- `gen-belousov-zhabotinsky` appears in both 3C (Kimiclaw chromatic) and 3D (Claude multi-pass) — Claude done; Kimiclaw adds chromatic only if missing after audit.
- Showcase files (`prompt-showcase-batch-1.md`, `showcase-checklist-v1.md`) referenced but not yet created — added as explicit tasks.
- Performance and logical cleanliness are now explicit upgrade criteria alongside feature completeness.

---

## Next Sync

After **Batch 3A validates** (unblocks Claude 3E) or **Ethereal Silk** first draft lands.

**Immediate action:** Kimiclaw launch 3A (4 shaders) → Codex gate.