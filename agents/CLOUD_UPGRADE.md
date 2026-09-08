# Cloud Upgrade Guide — Pixelocity Shader Upgrades

> **For:** Copilot, Claude, Gemini, Kimi, Antigravity, Grok, and any other AI agent working on Pixelocity WGSL shaders.  
> **Scope:** Upgrading existing WGSL compute shaders.  
> **Live batch contract:** [`docs/SHADER_UPGRADE_BATCH.md`](../docs/SHADER_UPGRADE_BATCH.md) — incremental ideas, not rewrites, not hygiene-only. **Read that first.**  
> **Constraint:** You are a **Shader Author**, not an Engine Developer. Do NOT modify `Renderer.ts`, `types.ts`, or bind groups.

---

## 1. Project Context

**Pixelocity** is a React + WebGPU app that runs GPU shader effects. Each effect is a single WGSL compute shader dispatched at `@workgroup_size(16, 16, 1)` over a 2048×2048 canvas.

Shaders live in `public/shaders/*.wgsl`. Their metadata lives in `shader_definitions/{category}/{id}.json`. The JSON files are the **source of truth** for the shader library.

### The 13-Binding Header (Immutable)

Every compute shader MUST declare exactly these bindings:

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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};
```

**Never** add, remove, or rename bindings. Never change the `Uniforms` struct.

---

## 2. What "Upgraded" Means

### 2.0 First Principle — Add Ideas to *This* Effect

> **Upgrading means adding 2–4 named visual ideas to the existing effect.**
> Keep the algorithm, the look, and the saved params. Deepen what is already
> there. Do not reimagine the shader as a different effect. Do not treat
> formatting, binding alignment, ACES, or `updatedParams` as the upgrade.
>
> §2.1–2.5 (bindings, workgroup guard, branchless safety, depth/data writes,
> naga, JSON) are the **floor**. A shader that newly compiles, writes depth,
> and has meaningful alpha but renders the same picture is **not** upgraded.
> A shader whose filename still matches but whose picture is a new motif is
> also **not** upgraded — that is a new catalog entry, not an upgrade.
>
> Full contract, Idea Card template, anti-patterns, batch size vs model, and
> library timeframe: [`docs/SHADER_UPGRADE_BATCH.md`](../docs/SHADER_UPGRADE_BATCH.md).

**Before any WGSL edit**, write an Idea Card for the target (identity, keep-verbatim, 2–4 native additions, packing). Implement those additions in the existing main path. Then apply the floor.

A shader is `upgraded-rgba` when it has the Idea Card implemented **and** satisfies **all** of the following criteria. Point values in §2.1–2.5 grade the **floor only**. A perfect plumbing score with no native ideas is a fail.

### 2.1 RGBA Awareness (25 pts)
- [ ] **No hardcoded alpha.** Never output `vec4(rgb, 1.0)`. Alpha must encode something useful: blend weight, edge strength, bloom intensity, depth influence, or the source texture's original alpha.
- [ ] **Full `vec4` sampling.** When reading `readTexture`, always sample the full `vec4<f32>` and preserve or modulate its `.a` channel. Do not do `.rgb` sampling unless you explicitly need the alpha for compositing later.
- [ ] **Meaningful alpha formula.** Alpha should vary across the image. Static `0.5` or `1.0` is not acceptable.

### 2.2 Idea Card techniques (not a costume)
- [ ] **The 2–4 Idea Card additions are visible in the existing main path.** They belong on this effect (better kernel, extra force, extra optical beat). Do not add chromatic aberration + glow + ripples just to tick “two techniques.”
- [ ] **Temporal coherence.** Animate with `u.config.x` (time). No `floor(time)` hash strobing. No frame-hash motion.

### 2.3 Randomization & Safety (25 pts)
- [ ] **No divide-by-zero.** Guard all divisions with `max(denominator, 0.001)` or `+ 0.0001`.
- [ ] **Clamped UVs.** Any displaced UV must be `clamp(..., vec2<f32>(0.0), vec2<f32>(1.0))` before sampling.
- [ ] **Branchless preferred.** Replace `if` blocks with `select()`, `mix()`, `smoothstep()`, and boolean multiplication where possible. The only acceptable `if` is the boundary guard at the top of `main()`.

### 2.4 Compilation & Performance (20 pts)
- [ ] **`@workgroup_size(16, 16, 1)`** unless the shader explicitly requires a different size (e.g., 1D particle systems).
- [ ] **Writes `writeDepthTexture`.** Every shader must write depth: `textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));`
- [ ] **Writes `dataTextureA`.** Every shader must write A every frame. Packing must match how this shader reads `dataTextureC` next frame (display RGBA **or** raw sim fields). Do not ACES stored sim fields. Do not write “final display” into A if C is state.
- [ ] **Passes `naga` validation.** Run `naga filename.wgsl` and fix any errors.

### 2.5 Documentation & JSON (15 pts)
- [ ] **Standard header comment** at the top of the WGSL file — and it **names the ideas**:
  ```wgsl
  // ═══════════════════════════════════════════════════════════════════
  //  {Shader Name}
  //  Category: {category}
  //  Features: mouse-driven, audio-reactive, upgraded-rgba
  //  Complexity: {Low|Medium|High}
  //  Upgraded: {YYYY-MM-DD}
  //  Ideas: {idea 1}; {idea 2}
  //  A packing: display RGBA | raw sim …
  // ═══════════════════════════════════════════════════════════════════
  ```
- [ ] **JSON features updated only when true.** `"upgraded-rgba"` requires ACES **and** the Idea Card. `"audio-reactive"` requires `plasmaBuffer[0].xyz` used. Saved `params` stay byte-exact; `updatedParams` may be aligned additively.

---

## 3. Audio Reactivity Rules

The `plasmaBuffer` contains FFT audio data:

```wgsl
let bass = plasmaBuffer[0].x;   // Low frequencies  (kick, sub)
let mids = plasmaBuffer[0].y;   // Mid frequencies  (snare, synth)
let treble = plasmaBuffer[0].z; // High frequencies (hats, cymbals)
```

### Usage Patterns
| Audio Band | Typical Usage |
|---|---|
| **Bass** | Scales effect radius, boost strength, pulse intensity, rotation speed |
| **Mids** | Drives color cycling, chromatic aberration, shimmer, swirl amount |
| **Treble** | Adds sparkle, high-frequency jitter, scanline shimmer |

### Anti-patterns
- ❌ `let strength = bass * 100.0;` (unbounded explosion)
- ✅ `let strength = baseStrength * (1.0 + bass * 0.5);` (controlled modulation)
- ❌ Using `u.zoom_config.x` as a proxy for audio (that's just time)
- ✅ Always read from `plasmaBuffer[0].xyz`

---

## 4. Step-by-Step Upgrade Workflow

Creative law lives in [`docs/SHADER_UPGRADE_BATCH.md`](../docs/SHADER_UPGRADE_BATCH.md). This section is the **floor only**. If you finish Steps 1–8 and the picture is unchanged, you have not upgraded the shader.

### Step 0: Idea Card, then assess
Write the Idea Card (identity, keep-verbatim, 2–4 native additions, packing) **before** editing. Then:

```bash
cd /root/image_video_effects/public/shaders
naga target_shader.wgsl 2>&1
wc -l target_shader.wgsl
```

Floor gaps to note (these are not the ideas):
- Hardcoded `vec4(..., 1.0)` → needs meaningful alpha
- No `plasmaBuffer` usage → needs audio **if** the JSON claims it
- No `writeDepthTexture` / `dataTextureA` → needs those writes
- Filtering `textureSample` of `dataTextureC` → exact `textureLoad`
- Missing header → add it **with the Ideas: line**

### Step 1: Implement the Idea Card in the existing main path
Keep the kernel, modes, and param roles. Add the 2–4 native ideas. Then apply the header (see §2.5) **including `Ideas:` and `A packing:`**. Do not start by pasting a spring/ripple overlay.

### Step 2: Add Audio Reactivity
Insert bass/mids reads near the top of `main()`:
```wgsl
let bass = plasmaBuffer[0].x;
let mids = plasmaBuffer[0].y;
```

Then modulate key parameters:
```wgsl
let strength = u.zoom_params.x * (1.0 + bass * 0.5);
let twist = u.zoom_params.y * (1.0 + mids * 0.3);
```

### Step 3: Replace Hardcoded Alpha
Find every `vec4(rgb, 1.0)` and replace with a meaningful alpha calculation:

```wgsl
// BEFORE:
textureStore(writeTexture, coord, vec4<f32>(color, 1.0));

// AFTER:
let effectStrength = smoothstep(0.0, 0.5, length(displacement));
let alpha = clamp(baseColor.a * 0.5 + effectStrength * 0.5 + mouseInfluence * 0.2, 0.0, 1.0);
textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
```

### Step 4: Add Depth & Temporal Writes
At the very end of `main()`, after the `writeTexture` store:

```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
textureStore(dataTextureA, coord, packedA); // display RGBA or raw sim — match C reads
```

### Step 5: Branchless Conversion
Replace `if` blocks with `select()` / `mix()`:

```wgsl
// BEFORE:
if (mode > 0.5) {
    forceDir = dir;
}

// AFTER:
let isAttract = mode > 0.5;
let forceDir = select(-dir, dir, isAttract);
```

```wgsl
// BEFORE:
if (dist < radius) {
    color = color * (1.0 - rim);
}

// AFTER:
let isInside = dist < radius;
color = select(color, color * (1.0 - rim), isInside);
```

### Step 6: Validate
```bash
cd /root/image_video_effects/public/shaders
naga target_shader.wgsl
```

Fix any naga errors before proceeding. Common errors:
- `scalar vs vec4 mismatch` in `textureStore` → wrap scalar in `vec4<f32>(scalar, 0.0, 0.0, 0.0)`
- `type mismatch in select()` → both branches must be the same type
- `reserved keyword` → rename variables like `active`, `array`, `texture`
- `swizzle assignment` → WGSL does not support `color.rgb = ...`; reconstruct the full vec4

### Step 7: Update JSON
```bash
# Find the JSON file
find shader_definitions -name "target_shader.json"

# Add features
python3 -c "
import json
with open('shader_definitions/.../target_shader.json') as f:
    d = json.load(f)
# Only append a feature when WGSL actually does it. Never tag upgraded-rgba
# without ACES + Idea Card. Never rename/re-default params.
for feat in ['audio-reactive']:  # add others only if true
    if feat not in d.get('features', []):
        d.setdefault('features', []).append(feat)
with open('shader_definitions/.../target_shader.json', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
```

### Step 8: Project-Level Verification
```bash
cd /root/image_video_effects
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```

Both must pass cleanly.

---

## 5. Batch Workflow (Efficient Mode)

When upgrading multiple shaders, use this pipeline:

### 5.1 Discover Targets
This script scores **hygiene debt** (missing dataA / audio / depth / tag). A high score is not permission to rewrite and is not an Idea Card. Use it only to find files that still need the floor **after** you have cards. Prefer a family (PP, glitch, liquid), not “highest score.”

```bash
cd /root/image_video_effects/public/shaders
python3 << 'PYEOF'
import glob
for f in glob.glob("*.wgsl"):
    with open(f) as fh:
        src = fh.read()
    lines = src.count('\n')
    if lines > 160:
        continue
    has_upgraded = 'upgraded-rgba' in src
    has_data = 'textureStore(dataTextureA' in src
    has_audio = 'plasmaBuffer' in src
    has_depth = 'textureStore(writeDepthTexture' in src
    score = 0
    if not has_data: score += 10
    if not has_audio: score += 5
    if not has_depth: score += 3
    if not has_upgraded: score += 2
    if score >= 5:
        print(f"{lines:3d}L | {f.replace('.wgsl','')} | score={score}")
PYEOF
```

### 5.2 Pick the Next Batch
Select **6–10** shaders (Flash: 6–8; Opus/Grok: 8–10; never more than 12) that share a family or backlog rule. Prefer shaders that have JSON definitions. Write Idea Cards for the whole list before editing the first file. See [`docs/SHADER_UPGRADE_BATCH.md`](../docs/SHADER_UPGRADE_BATCH.md) §5.

### 5.3 Upgrade Strategy Matrix
| Shader State | Recommended Action |
|---|---|
| Missing floor (header / audio / depth / dataA / alpha) **and** thin visuals | **Idea Card + floor.** Keep the existing kernel. Add 2–4 native ideas while wiring the floor. **Not a rewrite.** |
| Floor present, picture still thin | **Idea Card only.** Do not restamp ACES/spring/ripples. Add native structure. |
| Floor present, already idea-rich | **Skip.** Do not bump the `Upgraded:` date for hygiene. |
| Header / tag / `updatedParams` missing, picture already good | **Metadata pass** — allowed, but **do not call it an upgrade** and do not mix it into an idea batch. |

### 5.4 Parallel Validation
After writing all shaders in a batch:
```bash
cd /root/image_video_effects/public/shaders
for f in shader1 shader2 shader3 ...; do
  echo -n "$f: "
  naga "$f.wgsl" 2>&1 && echo "OK" || echo "FAIL"
done
```

Fix all FAILs before moving on.

---

## 6. Common Upgrade Snippets

### 6.1 Safe Normalize
```wgsl
let safeLen = max(length(v), 0.0001);
let dir = v / safeLen;
```

### 6.2 Hash / Noise (for jitter)
```wgsl
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
```

### 6.3 Audio Pulse
```wgsl
let pulse = 1.0 + bass * 0.5;
let clickBurst = select(1.0, 2.5, u.zoom_config.w > 0.5);
```

### 6.4 Depth-Scaled Effect
```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
let depthBoost = 1.0 + (1.0 - depth) * 0.5; // Far objects get stronger effect
```

### 6.5 Premultiplied Writeback
```wgsl
let a = clamp(alpha, 0.0, 1.0);
textureStore(writeTexture, coord, vec4<f32>(rgb * a, a));
```

### 6.6 ACES Filmic Tonemap
```wgsl
fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
```

---

## 7. The 4-Agent Parallel Model (Advanced)

For complex shaders (> 80 lines or generative/raymarched), you may use the 4-agent parallel approach. Each agent specializes:

| Agent | Responsibility |
|---|---|
| **Algorithmist** | Math, noise, SDF, simulation logic, divergence-free fields |
| **Visualist** | Color grading, alpha semantics, HDR/bloom, tonemap, dither |
| **Interactivist** | Mouse mapping, click/ripple handling, audio reactivity, parameter wiring |
| **Optimizer** | Line budget, texture sample count, branch elimination, var→let conversion |

### Workflow
1. Read the original WGSL and JSON.
2. Spawn 4 agents in parallel with the shader source + their role prompt.
3. Each agent returns their specialized improvements.
4. Merge all 4 outputs into a single WGSL file.
5. Run naga. Fix any syntax conflicts.
6. Pass/fail the Idea Card (§2.0) **and** the floor. A 100-point plumbing score without ideas is a fail.

**Note:** Do not run “completion passes” that only add dataA + a header tag and call them upgrades. Metadata-only work is allowed; it is not an upgrade batch.

---

## 8. Quality Gates

Before marking any shader as complete, verify **ideas first**, then the floor:

```bash
# 0. Idea Card: header must name them
grep -n '^//  Ideas:' public/shaders/SHADER_ID.wgsl

# 1. Syntax
naga public/shaders/SHADER_ID.wgsl

# 2. No hardcoded alpha
grep -n 'vec4(.*, 1\.0)' public/shaders/SHADER_ID.wgsl || echo "OK: no hardcoded alpha"

# 3. Has dataTextureA
grep -c 'textureStore(dataTextureA' public/shaders/SHADER_ID.wgsl

# 4. Has writeDepthTexture
grep -c 'textureStore(writeDepthTexture' public/shaders/SHADER_ID.wgsl

# 5. Has audio (only required if JSON claims audio-reactive)
grep -c 'plasmaBuffer' public/shaders/SHADER_ID.wgsl

# 6. Has upgraded header (only if Idea Card + ACES are real)
grep -c 'upgraded-rgba' public/shaders/SHADER_ID.wgsl

# 7. Project integrity
cd /root/image_video_effects
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```

Gates 2–7 without `Ideas:` in the header = hygiene, not upgraded. Full coordinator checklist: `docs/SHADER_UPGRADE_BATCH.md` §9.

---

## 9. Quick Reference Card

| Task | Command |
|---|---|
| Validate WGSL | `naga shader.wgsl` |
| Generate shader lists | `node scripts/generate_shader_lists.js` |
| Check duplicates | `node scripts/check_duplicates.js` |
| Find small un-upgraded shaders | See §5.1 discovery script |
| Update JSON features | Python one-liner in §4 Step 7 |
| List all shader definitions | `find shader_definitions -name "*.json" \| wc -l` |

---

## 10. Example: Before → After (floor + named ideas)

Plumbing-only after (ACES + alpha + dataA, same picture) is **not** an upgrade. The after must include the Idea Card in the header and in the kernel.

### BEFORE (`electric-contours.wgsl`, raw)
```wgsl
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
// ... bindings ...
textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(result + glow, 1.0));
```

### AFTER (`electric-contours.wgsl`) — ideas named, kernel kept
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Electric Contours
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-06
//  Ideas: dual-scale Sobel ridges; contour runners along gradient
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
// ... full 13-binding header ...

// Idea 1 — dual-scale Sobel (same edge identity, extra octave)
// Idea 2 — runners along the gradient (not a spring overlay)

let bass = plasmaBuffer[0].x;
let glow_multiplier = mix(0.0, 2.0, u.zoom_params.y) * (1.0 + bass * 0.3);

let alpha = clamp(final_edge * 0.8 + spark + mouse_influence * 0.2 + base_color.a * 0.3, 0.0, 1.0);
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

textureStore(writeTexture, coord, vec4<f32>(final_rgb, alpha));
textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
textureStore(dataTextureA, coord, vec4<f32>(final_rgb, alpha));
```

Worked good/bad cards: `docs/SHADER_UPGRADE_BATCH.md` §7.
Shipped photo/print/grade examples (2026-09-06): `pp-bloom`, `pp-tone-map`, `analog-film-degrade`, `color-blindness`, `crumpled-paper`, `retro-gameboy`, `conv-bilateral-dream`, `tilt-shift` — briefs in `agents/swarm-outputs/grok-2026-09-06-photo-eight/`.

---

*Last updated: 2026-09-06*  
*Batch process SoT: `docs/SHADER_UPGRADE_BATCH.md` (incremental ideas, not rewrite / not hygiene-only)*
