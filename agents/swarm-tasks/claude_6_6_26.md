# Claude Agent Swarm — Optimization & Algorithmic Depth (2026-06-06)

**Date:** 2026-06-06  
**Master plan:** [`kimi_6_6_26.md`](./kimi_6_6_26.md)  
**GitHub issues:** [#801 Batch 3](https://github.com/ford442/image_video_effects/issues/801) · [#799 WASM](https://github.com/ford442/image_video_effects/issues/799) · [#800 Gallery](https://github.com/ford442/image_video_effects/issues/800)

**Role:** Second-pass specialist — deep optimization, multi-pass architecture, visual transcendence, and flagship algorithmic upgrades. You refine what Kimi Claw implements; you do not do bulk mechanical sweeps.

---

## Coordination Matrix (2026-06-06)

| Agent | Lane | Touch first |
|-------|------|-------------|
| **Kimiclaw** | Volume implementation (3A/3B/3C) | ✅ Yes |
| **Codex** | Validation, drift fixes, JSON sync | After Kimiclaw per shader |
| **Claude (you)** | 3D multi-pass + polish on heavy shaders | After Kimiclaw 3A, parallel on 3D |
| **Kimi** | Orchestrator doc + chunk library | Reference only |

**Strict constraint:** Do NOT edit shaders assigned to Kimiclaw until their `.notes.kimiclaw.md` lands in `agents/swarm-outputs/kimi-notes/`. Exception: Batch 3D shaders (you own these from the start).

---

## Your Batch — 7 Shaders (Disjoint from Kimiclaw 3B/3C)

### Batch 3D — Multi-Pass Flagships (you own these)

| # | Shader ID | Upgrade mission | Why Claude |
|---|-----------|-----------------|------------|
| D1 | `gen_reaction_diffusion` | RG simulation in `dataTextureA`, colorize pass reads `dataTextureC` | RD needs careful state packing + stability |
| D2 | `gen-murmuration-phantom` | Boid state in `extraBuffer`, trail accumulation via dataA | Already Batch 2 — push to true flock sim |
| D3 | `gen-navier-stokes-ink` | Velocity in dataB, advection via dataC, pressure stub | Fluid math + perf LOD |
| D4 | `gen-belousov-zhabotinsky` | Multi-scale RD: coarse state in dataA, detail in output | Oscillation stability tuning |
| D5 | `gen-conway-game-of-life` | CA state in dataA.r, generation in dataA.g, fade trails | Clean CA + temporal aesthetics |

### Batch 3E — Second-Pass Polish (after Kimiclaw finishes 3A)

| # | Shader ID | Polish mission |
|---|-----------|----------------|
| E1 | `gen-translucent-nebula` | Raymarch LOD, early exit on empty space, tune chromatic to nebula density |
| E2 | `gen-prismatic-crystal-growth` | Distance-based octave reduction, `fwidth` anti-aliasing on crystal edges |
| E3 | `electric-eel-storm` | Branchless lightning paths, bass-driven discharge timing, premultiplied alpha polish |

**Kimiclaw owns 3A first pass** on all five 3A shaders including `gen-alpha-aurora` and `gen-ghost-flame`. You polish E1–E3 only after Kimiclaw notes exist.

---

## Immutable Rules

1. **DO NOT** modify `Renderer.ts`, `types.ts`, bind groups, or install npm packages.
2. **DO NOT** change `@workgroup_size` on shaders with `var<workgroup>`, size-dependent `local_invocation_id` math, or `workgroupBarrier()`.
3. **PRESERVE** the shader's visual soul — optimize and elevate, don't replace with generic noise.
4. **COPY EXACTLY** the 13-binding header and `Uniforms` struct when adding code.
5. Add `CHUNK:` attributions for every borrowed pattern.
6. Update header `Upgraded:` date and JSON `features` when adding capabilities.

---

## Claude Optimization Toolkit

### 1. Distance-based LOD (raymarchers / FBM)

```wgsl
// ═══ CHUNK: distance-lod-octaves (from AGENTS.md) ═══
let dist = length(uv - 0.5);
let octaves = i32(mix(6.0, 2.0, dist * 1.5));
```

### 2. Early exit (low-contribution pixels)

```wgsl
if (effectStrength < 0.01) {
  textureStore(writeTexture, coord, vec4<f32>(0.0));
  textureStore(dataTextureA, coord, vec4<f32>(0.0));
  return;
}
```

### 3. Branchless select paths

```wgsl
let glow = select(0.0, exp(-d * 8.0), d < 0.1);
```

### 4. Hue-preserving HDR clamp (before ACES)

```wgsl
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return c * min(1.0, maxLum / max(l, 1e-4));
}
```

### 5. IGN dither (banding reduction after tonemap)

```wgsl
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
// Apply: col += (ign(uv * res) - 0.5) / 255.0;
```

### 6. Multi-pass state packing (3D shaders)

```wgsl
// Write simulation state (not color) to dataA:
textureStore(dataTextureA, coord, vec4<f32>(concentrationA, concentrationB, velocityAngle, 1.0));

// Read prior frame:
let state = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
let a = state.r;
let b = state.g;
```

### 7. extraBuffer boid layout (murmuration)

```wgsl
// Per-boid: 4 floats = x, y, vx, vy
let idx = boidId * 4u;
let bx = extraBuffer[idx];
let by = extraBuffer[idx + 1u];
// Write back after integration
```

### 8. Depth-responsive compositing (slot-chain polish)

```wgsl
let z = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
let fog = 1.0 - exp(-z * u.zoom_params.z);
col = mix(srcColor, fxColor, fog);
```

---

## Task Protocol (per shader)

### Phase 1 — Analysis (write in notes file first)

- Profile mentally for 2048×2048 @ 60 fps on integrated GPU.
- Identify top 3 bottlenecks (texture samples in loops, redundant trig, missing LOD, no early-out).
- Check: does it have the full upgraded-rgba stack from Kimiclaw? What's still weak?
- Compare against `gen-protocell-division.wgsl` (Batch 2 gold reference).

### Phase 2 — Apply (conservative)

You may:
- Add workgroup tiling where structurally obvious (multi-pass pass-1 shaders only)
- Introduce distance LOD, early exits, branchless refactors
- Tune multi-pass state packing and simulation stability
- Add hue_preserve_clamp + IGN dither if highlights band or clip
- Improve parameter semantics in JSON

You may NOT:
- Rewrite the entire shader from scratch
- Change the 13-binding contract
- Touch Kimiclaw's in-progress shaders (no notes file yet)

### Phase 3 — Deliverables

1. Upgraded `public/shaders/{id}.wgsl`
2. Updated `shader_definitions/generative/{id}.json` (if features/params changed)
3. `agents/swarm-outputs/claude-notes/{id}.claude-optimization.md`

---

## Notes File Template

```markdown
# {shader-id} — Claude Optimization (2026-06-06)

## Bottlenecks Identified
- Line ~{N}: {description}

## Optimizations Applied
- {change} → expected {impact}

## Visual / Transcendence Notes
- {what now feels different}

## Remaining Risks
- {watch at 4K / multi-slot / etc.}

## JSON Changes
- {features added/removed, or "none"}
```

---

## Multi-Pass: gen_reaction_diffusion Example

**Goal:** Gray-Scott-style RD with stable temporal state.

```wgsl
// Read previous concentrations
let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
var a = prev.r;
var b = prev.g;

// Simulate (simplified Gray-Scott)
let feed = 0.055;
let kill = 0.062;
let da = 1.0;
let db = 0.5;
// ... Laplacian via 4-neighbor sample ...
let reaction = a * b * b;
a = a + (da * lapA - reaction + feed * (1.0 - a)) * dt;
b = b + (db * lapB + reaction - (kill + feed) * b) * dt;

// Write state for next frame
textureStore(dataTextureA, coord, vec4<f32>(a, b, 0.0, 1.0));

// Colorize for display
let col = vec3<f32>(a, b * 0.5, 1.0 - a);
col = acesToneMap(huePreserveClamp(col * 1.2, 2.0));
textureStore(writeTexture, coord, vec4<f32>(col, clamp(a + b, 0.0, 1.0)));
```

---

## Validation (run after your batch)

```bash
naga public/shaders/{shader-id}.wgsl
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```

---

## Execution Checklist

- [ ] Read `kimi_6_6_26.md` + `agents/WGSL_BUILTINS_GENERATIVE.md`
- [ ] Complete D1–D5 (3D multi-pass) — write `.claude-optimization.md` per shader immediately
- [ ] Wait for Kimiclaw notes on 3A before starting E1–E3
- [ ] Polish E1–E3 with LOD/perf pass
- [ ] Append session summary to bottom of this file
- [ ] Flag any shader needing a third deep pass for next week

---

## Success Criteria

- Every touched shader shows documented perf or elegance improvement
- At least 3 of 7 gain LOD, early exit, or multi-pass state architecture
- All outputs have Standard Hybrid Header with `CHUNK:` attributions
- Zero regressions in visual character
- `.claude-optimization.md` files are PR-ready

---

## Session Summary

**Date completed:** 2026-06-07

- **Biggest win:** Conway Game of Life had a critical bug — `dataTextureA` was never written, so CA state was being carried (accidentally) through `writeDepthTexture`. Fixed: state now correctly ping-pongs via `dataTextureA.r=alive, .g=generation, .b=activity`. Also added a generation counter that visually ages cells from cyan → amber, making colony structure readable.

- **Patterns to codify:**
  - `huePreserveClamp(col, maxLum)` + `ign()` dither — applied to all 5 shaders as a standard finishing pass; should be part of AGENTS.md "must-have" checklist for every shader
  - Pressure stub pattern for Navier-Stokes: `pressureEst = -div * 0.25`, gradient written to `dataTextureB` — enables future multi-pass pressure solve without restructuring
  - Branchless color ramp: replace if/else chains with cascaded `smoothstep()` + `mix()` — same result, no warp divergence

- **Shaders flagged for third pass:**
  - `gen-navier-stokes-ink`: pressure stub should become a real Jacobi-iteration pressure solve (2-3 passes); velocity field currently slightly divergent at high injection
  - `gen-murmuration-phantom`: extraBuffer boid simulation (per-boid x,y,vx,vy integration) would push this to true flock sim as specified in D2 mission; skipped as full rewrite
  - `gen-conway-game-of-life`: `countNeighbors` (8 textureLoad/thread) is a bottleneck at 4K with small cellSize — could use shared memory tiling in workgroup

- **E1-E3 status:** Kimiclaw notes not yet present for translucent-nebula, prismatic-crystal-growth, or electric-eel-storm — held per coordination matrix rules.