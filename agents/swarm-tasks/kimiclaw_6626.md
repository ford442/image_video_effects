# Kimi Claw Agent Swarm — Bulk Generative Upgrades (2026-06-06)

**Date:** 2026-06-06  
**Master plan:** [`kimi_6_6_26.md`](./kimi_6_6_26.md)  
**GitHub issue:** [#801 Batch 3](https://github.com/ford442/image_video_effects/issues/801)  
**Invocation:** `kimi-cli --no-stream` (stdin prompt, 120s timeout)

**Role:** High-volume first-pass implementation. Apply the standardized upgraded-rgba stack to Batch 3A/3B/3C generative shaders using exact code chunks. Codex validates after you; Claude polishes heavy shaders later.

---

## Coordination Matrix

| Agent | Your relationship |
|-------|-------------------|
| **Kimiclaw (you)** | Implement 3A → 3B → 3C (25 shaders max today) |
| **Codex** | Reviews every shader you finish — do not skip notes files |
| **Claude** | Takes 3D multi-pass + E1–E3 polish after your 3A lands |
| **Kimi doc** | Chunk library reference |

**Do NOT touch:** Batch 3D shaders (`gen_reaction_diffusion`, `gen-navier-stokes-ink`, `gen-belousov-zhabotinsky`, `gen-conway-game-of-life`) — Claude owns these.

---

## Immutable Rules

1. **DO NOT** modify `Renderer.ts`, `types.ts`, bind groups, or install npm packages.
2. **DO NOT** change `@workgroup_size` on shaders with `var<workgroup>` or workgroupBarrier.
3. **COPY EXACTLY** the 13-binding header below — no `outputTex`, `iTime`, `videoSampler`.
4. **PRESERVE** the shader's algorithmic core — additive upgrades only.
5. **Alpha must be semantic** — never `vec4(color, 1.0)` without reason.
6. Max **2 shaders per agent invocation** to keep diffs reviewable.
7. Hard line budget: **±20% of original line count** unless shader was under 100 lines.

---

## 13-Binding Contract (copy EXACTLY into every prompt)

```wgsl
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
```

---

## Kimi-CLI Output Contract (non-negotiable)

1. Response contains **exactly one** ` ```wgsl ` fenced block with the **complete** upgraded shader.
2. **Zero prose** after the closing ` ``` ` — extractor breaks on trailing text.
3. Optionally one ` ```json ` block if JSON features changed (second fence before any prose).
4. Write notes file separately to disk (not in kimi-cli stdout).

---

## Today's Assignments

### Batch 3A — Chromatic Only (5 shaders) — DO FIRST

| # | Shader ID | File |
|---|-----------|------|
| 1 | `gen-translucent-nebula` | `public/shaders/gen-translucent-nebula.wgsl` |
| 2 | `gen-alpha-aurora` | `public/shaders/gen-alpha-aurora.wgsl` |
| 3 | `gen-ghost-flame` | `public/shaders/gen-ghost-flame.wgsl` |
| 4 | `gen-prismatic-crystal-growth` | `public/shaders/gen-prismatic-crystal-growth.wgsl` |
| 5 | `electric-eel-storm` | `public/shaders/electric-eel-storm.wgsl` |

**Apply:** temporal feedback (if missing) + chromatic + verify ACES + dataA write.

### Batch 3B — dataTextureA Plumber (10 shaders) — DO SECOND

Enumerate targets:

```bash
node -e "
const fs=require('fs'),path=require('path');
const ids=[];
for(const f of fs.readdirSync('shader_definitions/generative').filter(x=>x.endsWith('.json'))){
  const j=JSON.parse(fs.readFileSync('shader_definitions/generative/'+f));
  const w=fs.readFileSync(path.join('public',j.url),'utf8');
  if(w.includes('dataTextureC') && !w.includes('textureStore(dataTextureA')) ids.push(j.id);
}
console.log(ids.slice(0,10).join('\n'));
"
```

Take the **first 10** from output. Do not overlap with 3A list.

### Batch 3C — ACES Gap Fill (10 shaders) — DO THIRD

```bash
node -e "
const fs=require('fs'),path=require('path');
const ids=[];
for(const f of fs.readdirSync('shader_definitions/generative').filter(x=>x.endsWith('.json'))){
  const j=JSON.parse(fs.readFileSync('shader_definitions/generative/'+f));
  if(!(j.features||[]).includes('upgraded-rgba')) continue;
  const w=fs.readFileSync(path.join('public',j.url),'utf8');
  if(!/fn acesToneMap|aces_tonemap/i.test(w)) ids.push(j.id);
}
console.log(ids.slice(0,10).join('\n'));
"
```

---

## Standard Upgrade Stack (insert in this order)

```wgsl
// 1. Audio (if not present)
let bass   = plasmaBuffer[0].x;
let mids   = plasmaBuffer[0].y;
let treble = plasmaBuffer[0].z;

// 2. Temporal (after color computed)
let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
col = mix(col, prev.rgb * 0.92, 0.05 + bass * 0.01);

// 3. Chromatic (use shader's glow/density/thickness as effectStrength)
let caStr = 0.003 * (1.0 + bass) + effectStrength * 0.001;
col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

// 4. ACES
col = acesToneMap(col * 1.1);

// 5. Output
textureStore(writeTexture, coord, vec4<f32>(col * alpha, alpha));
textureStore(writeDepthTexture, coord, vec4<f32>(effectStrength * 0.5, 0.0, 0.0, 0.0));
textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
```

### acesToneMap function (add once if missing)

```wgsl
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
```

**Gold reference:** `public/shaders/gen-protocell-division.wgsl`

---

## Prompt Template (copy per shader)

```markdown
# KIMI CLAW TASK — Batch 3{A|B|C} — {shader-id}

## Visual intent (one sentence)
{Describe what this shader renders — do not change this character.}

## Task
Upgrade this generative shader with the standardized post stack from gen-protocell-division.wgsl:
- acesToneMap (add function if missing; rename aces_tonemap → acesToneMap)
- temporal feedback via dataTextureC read
- chromatic aberration scaled by bass + effect strength
- textureStore(dataTextureA, ...) writeback
- semantic alpha

## Immutable 13-binding contract
{paste contract from above}

## Current WGSL
```wgsl
{paste full current shader}
```

## Output contract
1. Return exactly ONE ```wgsl block with the complete upgraded file.
2. No text after the closing ```.
3. Preserve the algorithmic core. Additive changes only.
4. Target line count: {originalLines} ±20%.
5. Update header Features: add upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration as applicable.
6. Set Upgraded: 2026-06-06 in header.

## Chunks From
gen-protocell-division.wgsl (Batch 2 upgraded-rgba stack)
```

---

## Post-Processing (you or orchestrator, after kimi-cli returns)

1. Save WGSL to `public/shaders/{id}.wgsl`
2. Update `shader_definitions/generative/{id}.json` features if needed:

```json
"features": ["audio-reactive", "upgraded-rgba", "aces-tone-map", "temporal-feedback", "chromatic-aberration", "depth-aware"]
```

(Only include features actually present.)

3. Write notes file:

```markdown
# {shader-id} — Kimiclaw Batch 3 Notes

## Batch
3{A|B|C}

## Changes Made
- Added acesToneMap
- Added temporal feedback (blend 0.05 + bass * 0.01)
- Added chromatic aberration (caStr from {variable})
- Added dataTextureA writeback
- Updated header features

## Validation
- naga: {pending — Codex runs}
- line count: {before} → {after}
```

Save to: `agents/swarm-outputs/kimi-notes/{shader-id}.notes.kimiclaw.md`

4. Notify Codex for validation gate.

---

## Naming Pitfall

`gen-cyclic-automaton` in JSON may be `gen_cyclic_automaton.wgsl` on disk (underscores). Always read the JSON `url` field for the actual filename.

---

## Execution Checklist

- [ ] Read `kimi_6_6_26.md` chunk library
- [ ] Read gold reference `gen-protocell-division.wgsl`
- [ ] Complete 3A (5 shaders) — 2 per kimi-cli invocation
- [ ] Run enumeration scripts; complete 3B (10 shaders)
- [ ] Complete 3C (10 shaders)
- [ ] Write `.notes.kimiclaw.md` for every shader
- [ ] Hand off to Codex for validation

---

## Success Criteria

- [ ] 25 shaders upgraded (5 + 10 + 10)
- [ ] Every shader has notes file
- [ ] Zero binding drift (canonical 13-binding names)
- [ ] No `vec4(..., 1.0)` hardcoded alpha
- [ ] Codex validation pass rate ≥ 90% without major rewrites

---

## Do NOT

- Invent new visual algorithms (Claude/Grok lane)
- Do deep performance optimization (Claude lane)
- Fix other agents' validation failures (Codex lane)
- Touch multi-pass flagship shaders (Claude 3D lane)
- Emit prose after WGSL fence in kimi-cli output

---

## Session Summary

_(Kimiclaw orchestrator fills this in at end of session)_

- Shaders completed:
- kimi-cli retries needed:
- Handed to Codex: