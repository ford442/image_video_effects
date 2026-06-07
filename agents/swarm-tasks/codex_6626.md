# Codex Agent Swarm — Validation & Precision Completion (2026-06-06)

**Date:** 2026-06-06  
**Master plan:** [`kimi_6_6_26.md`](./kimi_6_6_26.md)  
**GitHub issue:** [#801 Batch 3](https://github.com/ford442/image_video_effects/issues/801)

**Role:** Precision completion layer — validate Kimiclaw outputs, fix edge-case WGSL failures, reconcile JSON↔WGSL metadata drift, and produce the batch validation report. You are the quality gate, not the primary author.

---

## Coordination Matrix

| Agent | Lane | Order |
|-------|------|-------|
| **Kimiclaw** | Bulk WGSL implementation (3A/3B/3C) | 1st |
| **Codex (you)** | Review, fix, validate, report | 2nd (per shader or per sub-batch) |
| **Claude** | 3D multi-pass + polish (3E) | Parallel on 3D; after you on 3A |
| **Kimi** | Master chunks + orchestration | Reference |

**You do NOT:** invent new visual algorithms, rewrite shaders from scratch, or touch Batch 3D shaders (Claude owns those).

---

## Your Responsibilities

### 1. Per-shader validation gate

After each Kimiclaw sub-batch lands, run the audit on every touched shader before merging.

### 2. Edge-case repair

Fix patterns that break automated insertion scripts (learned from Batch 1 drift sweep):

| Pattern | Symptom | Fix |
|---------|---------|-----|
| Color inside `vec4<f32>(complexExpr, alpha)` | Script can't wrap ACES | Wrap inner expr only: `vec4<f32>(acesToneMap((expr)*1.1), alpha)` |
| `let finalColor` reassignment | naga error | Change to `var` or new `let` binding |
| Duplicate `acesToneMap` + `aces_tonemap` | Double tonemap | Remove duplicate, keep `acesToneMap` |
| `aces_tonemap` only | Naming inconsistency | Rename to `acesToneMap` |
| JSON `upgraded-rgba` but no ACES in WGSL | Metadata drift | Add ACES or remove JSON flag |
| `dataTextureC` read but no `dataTextureA` write | Broken temporal | Add writeback |
| Header features ≠ JSON features | Drift | Sync both |

### 3. Batch validation report

Write `agents/swarm-outputs/batch-3-validation.md` when 3A–3C complete.

### 4. Metadata drift re-sweep

Confirm zero drift after all fixes:

```bash
node -e "
const fs=require('fs'),path=require('path');
let drift=0;
for(const d of fs.readdirSync('shader_definitions')){
  const dir=path.join('shader_definitions',d);
  if(!fs.statSync(dir).isDirectory()) continue;
  for(const f of fs.readdirSync(dir).filter(x=>x.endsWith('.json'))){
    const j=JSON.parse(fs.readFileSync(path.join(dir,f),'utf8'));
    if(!(j.features||[]).includes('upgraded-rgba')) continue;
    const wpath=path.join('public',j.url||'');
    if(!fs.existsSync(wpath)) continue;
    const w=fs.readFileSync(wpath,'utf8');
    if(!/fn acesToneMap|aces_tonemap/i.test(w)) { console.log('DRIFT:',j.id); drift++; }
  }
}
console.log('Total drift:',drift);
"
```

---

## Validation Script (run per shader)

Save as one-liner or use directly:

```bash
SHADER_ID=gen-translucent-nebula node -e "
const fs=require('fs'),path=require('path');
const id=process.env.SHADER_ID;
const cat='generative';
const j=JSON.parse(fs.readFileSync('shader_definitions/'+cat+'/'+id+'.json'));
const w=fs.readFileSync(path.join('public',j.url),'utf8');
const jf=new Set(j.features||[]);
const checks={
  naga:null,
  aces:/fn acesToneMap|aces_tonemap/i.test(w),
  dataA:w.includes('textureStore(dataTextureA'),
  chromatic:/caStr|chromaticAberration|chromatic/i.test(w),
  temporal:w.includes('dataTextureC'),
  depth:w.includes('readDepthTexture'),
  audio:w.includes('plasmaBuffer[0]'),
  semanticAlpha:!/textureStore\(writeTexture[^)]*vec4<f32>\([^,]+,\s*1\.0\)/.test(w),
  headerUpgraded:w.includes('upgraded-rgba'),
  jsonAces:jf.has('aces-tone-map')||jf.has('upgraded-rgba'),
  jsonDataA:jf.has('temporal-feedback')?w.includes('textureStore(dataTextureA'):true,
};
const fails=Object.entries(checks).filter(([k,v])=>v===false).map(([k])=>k);
console.log(JSON.stringify({id,checks,fails,pass:fails.length===0},null,2));
"
```

Also run:

```bash
naga public/shaders/{shader-id}.wgsl
```

---

## Review Checklist (every Kimiclaw shader)

| # | Check | Pass criteria |
|---|-------|---------------|
| 1 | naga compile | Exit 0 |
| 2 | 13-binding header | Exact canonical names/order |
| 3 | `acesToneMap` | Present, applied once, before `textureStore(writeTexture` |
| 4 | `dataTextureA` write | Present if temporal feedback used |
| 5 | `dataTextureC` read | Present if temporal feedback claimed |
| 6 | Chromatic | Present if `chromatic-aberration` in header/JSON |
| 7 | Semantic alpha | Not hardcoded `1.0` without justification |
| 8 | Header ↔ JSON | Feature flags match |
| 9 | Algorithm preserved | Core functions intact (diff sanity) |
| 10 | No duplicate ACES | Single tonemap application |
| 11 | Notes file exists | `agents/swarm-outputs/kimi-notes/{id}.notes.kimiclaw.md` |

---

## Fix Protocol

When a shader fails validation:

1. Read Kimiclaw's WGSL + notes file.
2. Identify failure class from table above.
3. Apply **minimal diff** — smallest fix that passes all checks.
4. Write `agents/swarm-outputs/codex-notes/{id}.codex-fix.md`:

```markdown
# {shader-id} — Codex Fix (2026-06-06)

## Failure Class
- {edge-case type}

## Kimiclaw Issue
- {what was wrong}

## Fix Applied
- {minimal change description}

## Re-validation
- naga: ✅
- drift: ✅
- all checks: ✅
```

5. Do not re-style or optimize — that's Claude's lane.

---

## Sub-Batch Review Schedule

Review immediately after each Kimiclaw sub-batch:

| Sub-batch | Shaders | Your action |
|-----------|---------|-------------|
| **3A** | 5 chromatic-only | Validate all 5; fix edge cases; approve for Claude E1–E3 polish |
| **3B** | 10 dataA plumbers | Validate dataA writeback + temporal consistency |
| **3C** | 10 ACES gap fill | Run drift sweep; fix any remaining mismatches |

---

## Batch Report Template

Write to `agents/swarm-outputs/batch-3-validation.md`:

```markdown
# Batch 3 Validation Report — 2026-06-06

## Scope
{N} generative shaders — Kimiclaw implementation, Codex validation.

## Shaders Processed
| # | Shader | Kimiclaw | Codex fix? | Status |
|---|--------|:--------:|:----------:|:------:|

## Per-Shader Validation
| Shader | naga | dataA | chromatic | temporal | header | JSON sync |
|--------|:----:|:-----:|:---------:|:--------:|:------:|:---------:|

## Codex Edge-Case Fixes
| Shader | Failure class | Fix summary |

## Metadata Drift
- Before: {N}
- After: 0

## Project-Level Validation
| Check | Status |
|-------|:------:|
| generate_shader_lists.js | |
| check_duplicates.js | |
| metadata drift sweep | |
```

---

## Project-Level Validation (end of day)

```bash
cd /root/image_video_effects
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
npm test -- --watchAll=false
npm run build
```

---

## Files You Own

| Output | Path |
|--------|------|
| Fix notes | `agents/swarm-outputs/codex-notes/{id}.codex-fix.md` |
| Batch report | `agents/swarm-outputs/batch-3-validation.md` |
| Drift audit update | `agents/swarm-outputs/metadata_drift_audit.json` (if re-run) |

---

## Files You Must NOT Edit (unless fixing validation failure)

- `src/renderer/*`
- Batch 3D shaders (Claude lane): `gen_reaction_diffusion`, `gen-navier-stokes-ink`, `gen-belousov-zhabotinsky`, `gen-conway-game-of-life`
- Claude polish targets before Kimiclaw 3A notes exist

---

## Issue #801 Acceptance (Codex signs off)

- [ ] All 3A shaders pass validation table
- [ ] All 3B shaders have `dataTextureA` write when temporal active
- [ ] All 3C shaders have ACES when JSON says `upgraded-rgba`
- [ ] `batch-3-validation.md` complete
- [ ] Metadata drift = 0
- [ ] CI commands pass

---

## Session Summary

_(Codex fills this in at end of session)_

- Shaders reviewed:
- Edge-case fixes applied:
- Drift count before/after:
- Blockers for Claude/Kimiclaw: