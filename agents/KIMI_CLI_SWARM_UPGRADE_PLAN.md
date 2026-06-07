# Kimi-CLI Swarm Upgrade Plan

> **Status**: planning (2026-05-17)
> **Scope**: tailor the existing shader upgrade swarm prompts to `kimi-cli`'s
> invocation model, response shape, and strengths so the auto-repair /
> auto-upgrade loop in `scripts/scan-shaders-naga.py` and the
> `scripts/run-upgrade-swarm.js` orchestrator produce higher-quality WGSL
> with fewer retries.

## How kimi-cli is invoked today

`scripts/scan-shaders-naga.py` calls:

```python
subprocess.run(["kimi-cli", "--no-stream"], input=prompt, timeout=120, ...)
```

- **stdin-only prompt** — no `--system` flag, so role guidance must live in
  the prompt body.
- **120 s wall-clock budget** — long chain-of-thought is expensive; concrete
  bullets beat open-ended reasoning.
- **`--no-stream`** — stdout is parsed as one blob. We rely on a *single*
  ```` ```wgsl ```` fence; extra prose or multiple fences break the
  downstream extractor.
- **No tool access** — kimi-cli cannot read sibling files, naga, or JSON
  defs, so anything the agent needs must be inlined.

## Kimi-cli strengths to lean on

1. Strong at pattern-completing **self-contained WGSL files**, especially
   when given the exact binding header and a target line budget.
2. Good at **localized repair** when handed the failing line + naga error
   message — keep the prompt focused on that line range.
3. Reliable at honoring **explicit output schemas** ("return exactly one
   fenced block, no commentary") when told up front and again at the end.

## Kimi-cli weaknesses to design around

1. Drifts toward generic "cool noise" output when given vague visual goals
   → always pin the *theme* of the shader (one sentence) before the task.
2. Hallucinates bindings (`outputTex`, `iTime`, `mouse`) → re-state the
   canonical 13-binding header verbatim in every prompt.
3. Occasionally emits prose *after* the code fence → instruct: "stop after
   the closing ``` ``` ``` ``` "; the extractor should also trim trailing
   text.
4. Can over-pad with comments and blow the line budget → state a hard
   `<= N lines` cap and tell it to prefer math density over commentary.

---

## WGSL graphical tactics & tips for kimi-cli prompts

Drop these snippets/tips into prompt templates so kimi-cli reaches for them
instead of inventing weaker variants. All assume the canonical 13-binding
header (sampler, readTexture, writeTexture, Uniforms, depth, etc.) and
`@workgroup_size(16, 16, 1)`.

### 1. Hue-preserving HDR clamp (avoid color hue-shift on bright pixels)

```wgsl
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
```

Use after additive accumulation, before tonemap. Beats `min(c, 1.0)` which
desaturates highlights to white.

### 2. ACES filmic tonemap (drop-in, no LUT)

```wgsl
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
```

Apply after `hue_preserve_clamp` for cinematic rolloff. Pair with sRGB
gamma `pow(c, vec3<f32>(1.0/2.2))` on write if the target view is sRGB.

### 3. Interleaved-gradient blue-noise dither (kills 8-bit banding)

```wgsl
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
// before writing color:
let dither = (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;
let outRGB = aces(hdr) + vec3<f32>(dither);
```

Cheaper than a blue-noise texture sample and visually identical at 8-bit.

### 4. Anti-aliased SDF / line via `fwidth` (no MSAA needed in compute)

```wgsl
fn aa_step(edge: f32, x: f32) -> f32 {
    let w = max(fwidth(x), 1e-4);
    return smoothstep(edge - w, edge + w, x);
}
```

Use everywhere a hard `step()` would otherwise produce shimmering edges,
especially in kaleidoscope/SDF/grid shaders.

### 5. Smooth-min for SDF unions (round seams between primitives)

```wgsl
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0 - h);
}
```

`k ≈ 0.1–0.3` of the smaller primitive radius is a good default.

### 6. Domain-warped FBM (organic flow, two-octave warp)

```wgsl
fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5; var s = 0.0; var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * valueNoise(q);
        q = q * 2.02; a = a * 0.5;
    }
    return s;
}
fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)),
                      fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0*q + vec2<f32>(1.7, 9.2)),
                      fbm(p + 4.0*q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0*r);
}
```

Strictly better than single-octave noise for "alive" generative shaders;
kimi-cli reliably reuses this when the snippet is in scope.

### 7. Polar kaleidoscope fold (matches the platform's kaleidoscope family)

```wgsl
fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
    let r = length(uv);
    var a = atan2(uv.y, uv.x);
    let seg = 6.2831853 / max(segs, 1.0);
    a = abs(((a % seg) + seg) % seg - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}
```

Cheap, branch-light, and folds into FBM/SDF sampling for instant symmetry.

### 8. Hex bokeh sampling (better than circular for the same tap count)

```wgsl
const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>( 0.0,  0.0),
    vec2<f32>( 1.0,  0.0), vec2<f32>( 0.5,  0.866),
    vec2<f32>(-0.5,  0.866), vec2<f32>(-1.0,  0.0),
    vec2<f32>(-0.5, -0.866), vec2<f32>( 0.5, -0.866),
);
```

Use for `radial-blur`, DOF, and glow shaders. 7 taps reads like 19 circular
taps perceptually.

### 9. Audio-reactive envelope (decay rather than raw bass)

```wgsl
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}
```

Store previous in `dataTextureA.r` if a buffer slot is free. Eliminates the
"strobe at every frame" look that raw `plasmaBuffer[0].x` produces.

### 10. Depth-aware compositing for the 3-slot chain

```wgsl
let z = textureLoad(readDepthTexture, gid.xy, 0).r;
let fog = 1.0 - exp(-z * u.zoom_params.z);   // exponential depth fog
let outA = mix(srcA, fxA, fog);              // effect strengthens with depth
```

When a shader is meant to live in slot 2/3, this keeps foreground subjects
crisp while letting the effect "breathe" in the background.

### 11. Anti-moiré LOD bias for procedural noise

For procedural patterns sampled per-pixel, drop the lattice cell size when
`fwidth(uv) > cell_size` — i.e., trade detail for stability:

```wgsl
let lod = clamp(log2(max(fwidth(uv).x, fwidth(uv).y) * cell_freq), 0.0, 4.0);
let p = uv * (cell_freq * exp2(-lod));
```

Kills the shimmer that otherwise plagues `kimi_fractal_dreams`-style
shaders when zoomed out.

### 12. Premultiplied-alpha writeback (correct compositing in slot chain)

```wgsl
let a = clamp(alpha, 0.0, 1.0);
textureStore(writeTexture, gid.xy, vec4<f32>(rgb * a, a));
```

The renderer assumes premultiplied output downstream of slot 1. Straight
alpha here causes dark fringes after the next slot's blur/blend.

---

## Concrete changes to the swarm prompts (next PRs)

1. **`agents/prompt-templates/visualist.md`** — add §"Tonemap & dither
   stack" pointing at tactics 1–3 and tactic 12 (premultiplied writeback).
2. **`agents/prompt-templates/interactivist.md`** — replace raw
   `plasmaBuffer[0].x` examples with the attack/release envelope (tactic 9)
   and add the depth-aware composite (tactic 10).
3. **`agents/prompt-templates/algorithmist.md`** — inline the warped-FBM,
   kaleido fold, smooth-min, and `fwidth` AA snippets (tactics 4–7).
4. **`agents/prompt-templates/optimizer.md`** — add hex bokeh taps (tactic
   8) and the anti-moiré LOD bias (tactic 11).
5. **`scripts/scan-shaders-naga.py::ask_kimi`** — extend the prompt with:
   - the canonical 13-binding header (verbatim),
   - the 1-sentence shader theme (extracted from the JSON def's `name` /
     `description`),
   - an explicit "**Return exactly one ```wgsl fenced block, no prose
     before or after**" footer,
   - a `<= N` line cap where `N = current_lines + 40`.
6. **`scripts/run-upgrade-swarm.js`** — when `--dispatch` targets kimi-cli,
   stitch the role template + the 12 tactics above into the prompt body,
   and add a kimi-specific output parser that trims trailing prose after
   the first complete ```` ```wgsl ```` block.

## Out of scope (for now)

- Multi-file refactors (kimi-cli has no FS access in our wrapper).
- JSON-def edits — keep `selectShadersFromLLM`/Gemma in charge of params.
- Replacing the existing role split — these tactics augment, not replace,
  Algorithmist / Visualist / Interactivist / Optimizer.
