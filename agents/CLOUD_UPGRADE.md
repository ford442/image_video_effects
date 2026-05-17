# Cloud Upgrade Guide — Pixelocity Shader Upgrades

> **For:** Copilot, Claude, Gemini, Kimi, and any other AI agent working on Pixelocity WGSL shaders.  
> **Scope:** Upgrading existing WGSL compute shaders to meet the `upgraded-rgba` standard.  
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};
```

**Never** add, remove, or rename bindings. Never change the `Uniforms` struct.

---

## 2. What "Upgraded" Means

A shader is `upgraded-rgba` when it satisfies **all** of the following criteria.

### 2.1 RGBA Awareness (25 pts)
- [ ] **No hardcoded alpha.** Never output `vec4(rgb, 1.0)`. Alpha must encode something useful: blend weight, edge strength, bloom intensity, depth influence, or the source texture's original alpha.
- [ ] **Full `vec4` sampling.** When reading `readTexture`, always sample the full `vec4<f32>` and preserve or modulate its `.a` channel. Do not do `.rgb` sampling unless you explicitly need the alpha for compositing later.
- [ ] **Meaningful alpha formula.** Alpha should vary across the image. Static `0.5` or `1.0` is not acceptable.

### 2.2 Hybrid Technique (15 pts)
- [ ] **At least 2 visual techniques** combined in the same shader (e.g., edge detection + chromatic aberration, noise displacement + color grading, ripple distortion + glow).
- [ ] **Temporal coherence.** The effect should animate smoothly with `u.config.x` (time), not flicker randomly.

### 2.3 Randomization & Safety (25 pts)
- [ ] **No divide-by-zero.** Guard all divisions with `max(denominator, 0.001)` or `+ 0.0001`.
- [ ] **Clamped UVs.** Any displaced UV must be `clamp(..., vec2<f32>(0.0), vec2<f32>(1.0))` before sampling.
- [ ] **Branchless preferred.** Replace `if` blocks with `select()`, `mix()`, `smoothstep()`, and boolean multiplication where possible. The only acceptable `if` is the boundary guard at the top of `main()`.

### 2.4 Compilation & Performance (20 pts)
- [ ] **`@workgroup_size(16, 16, 1)`** unless the shader explicitly requires a different size (e.g., 1D particle systems).
- [ ] **Writes `writeDepthTexture`.** Every shader must write depth: `textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));`
- [ ] **Writes `dataTextureA`.** Every shader must write its final RGBA to `dataTextureA` for temporal feedback: `textureStore(dataTextureA, coord, finalColor);`
- [ ] **Passes `naga` validation.** Run `naga filename.wgsl` and fix any errors.

### 2.5 Documentation & JSON (15 pts)
- [ ] **Standard header comment** at the top of the WGSL file:
  ```wgsl
  // ═══════════════════════════════════════════════════════════════════
  //  {Shader Name}
  //  Category: {category}
  //  Features: mouse-driven, audio-reactive, upgraded-rgba
  //  Complexity: {Low|Medium|High}
  //  Upgraded: {YYYY-MM-DD}
  // ═══════════════════════════════════════════════════════════════════
  ```
- [ ] **JSON features updated.** The shader's JSON definition must include `"upgraded-rgba"` and `"audio-reactive"` in its `features` array.

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

### Step 0: Assess the Target
```bash
# Check current state
cd /root/image_video_effects/public/shaders
naga target_shader.wgsl 2>&1
wc -l target_shader.wgsl
```

Look for:
- Hardcoded `vec4(..., 1.0)` → needs meaningful alpha
- `if` blocks inside `main()` → should be branchless
- No `plasmaBuffer` usage → needs audio reactivity
- No `writeDepthTexture` → needs depth write
- No `dataTextureA` → needs temporal feedback
- Missing or generic header → needs standard header

### Step 1: Add the Standard Header
Replace any generic/copy-paste header with the 7-line standard header (see §2.5).

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
textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
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
for feat in ['mouse-driven', 'audio-reactive', 'upgraded-rgba']:
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
Select 10 shaders with the highest `score` and smallest line count. Prefer shaders that have JSON definitions.

### 5.3 Upgrade Strategy Matrix
| Shader State | Recommended Action |
|---|---|
| No header + no audio + no depth + hardcoded alpha | **Full rewrite** (treat as raw) |
| Has header + audio + depth, but no `dataTextureA` | **Completion pass** (add dataA + upgraded tag) |
| Has audio + depth + dataA, but no upgraded tag | **Header fix only** |

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
6. Grade with the 100-point rubric (§2).

**Note:** For simple completion passes (adding dataA + header tag), skip the 4-agent model and batch-process directly.

---

## 8. Quality Gates

Before marking any shader as complete, verify:

```bash
# 1. Syntax
naga public/shaders/SHADER_ID.wgsl

# 2. No hardcoded alpha
grep -n 'vec4(.*, 1\.0)' public/shaders/SHADER_ID.wgsl || echo "OK: no hardcoded alpha"

# 3. Has dataTextureA
grep -c 'textureStore(dataTextureA' public/shaders/SHADER_ID.wgsl

# 4. Has writeDepthTexture
grep -c 'textureStore(writeDepthTexture' public/shaders/SHADER_ID.wgsl

# 5. Has audio
grep -c 'plasmaBuffer' public/shaders/SHADER_ID.wgsl

# 6. Has upgraded header
grep -c 'upgraded-rgba' public/shaders/SHADER_ID.wgsl

# 7. Project integrity
cd /root/image_video_effects
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```

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

## 10. Example: Before → After

### BEFORE (`electric-contours.wgsl`, raw)
```wgsl
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
// ... bindings ...
textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(result + glow, 1.0));
```

### AFTER (`electric-contours.wgsl`, upgraded)
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Electric Contours
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
// ... full 13-binding header ...

// bass and mids read from plasmaBuffer
let bass = plasmaBuffer[0].x;
let glow_multiplier = mix(0.0, 2.0, u.zoom_params.y) * (1.0 + bass * 0.3);

// ... logic ...

let alpha = clamp(final_edge * 0.8 + spark + mouse_influence * 0.2 + base_color.a * 0.3, 0.0, 1.0);
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

textureStore(writeTexture, coord, vec4<f32>(final_rgb, alpha));
textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
textureStore(dataTextureA, coord, vec4<f32>(final_rgb, alpha));
```

---

*Last updated: 2026-05-17*  
*Batch 4 completed: 55 shaders upgraded total*
