# Shader Upgrade Task: `gen-quasicrystal`

## Metadata
- **Shader ID**: gen-quasicrystal
- **Agent Role**: Audio-Reactivity
- **Current Size**: 1199 bytes
- **Target Line Count**: ~200 lines
- **Status**: pending

## Immutable Rules
The following MUST NOT be changed:
1. The 13-binding contract header (copy exactly).
2. The `Uniforms` struct definition.
3. `@workgroup_size` unless the shader already uses shared memory or explicit local_invocation_id math.
4. Do NOT install new npm packages.
5. Do NOT modify Renderer.ts, types.ts, or bind groups.

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

---

## Current WGSL Source
```wgsl
// ═══ gen-quasicrystal — Algorithmist Upgrade ═══════════════════════════
//  Category: generative
//  Features: quasicrystal, n-fold symmetry, projection-method,
//            domain-warped FBM, Voronoi texture, audio-reactive,
//            temporal-feedback, Fresnel gem surfaces, anti-moire,
//            neon-glow, chromatic-aberration, aces-tone-map, semantic-alpha
//  Upgraded: 2026-06-28 by The Algorithmist
// ═══════════════════════════════════════════════════════════════════
//  Penrose tiling-inspired aperiodic patterns with enhanced mathematical
//  depth: domain-warped FBM, Voronoi/Worley noise, Fresnel gem surfaces,
//  and physical light transport for crystalline appearance.

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.618033988749894;

// ── Core helpers ──────────────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn neonGlow(color: vec3<f32>, intensity: f32) -> vec3<f32> {
    let safeColor = max(color, vec3<f32>(0.0));
    let lum = luma(safeColor);
    let glowMask = smoothstep(0.22, 1.0, lum);
    let chroma = normalize(safeColor + vec3<f32>(0.001)) * max(lum, 0.18);
    let bloom = (safeColor * safeColor + chroma) * glowMask * max(intensity, 0.0);
    return safeColor + bloom;
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

// ── Hash / Noise ──
fn h2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn h3(p: vec3<f32>) -> f32 {
    var q = fract(p * vec3<f32>(127.1, 311.7, 74.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y * q.z);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(h2(i), h2(i+vec2<f32>(1,0)), u.x),
               mix(h2(i+vec2<f32>(0,1)), h2(i+vec2<f32>(1,1)), u.x), u.y);
}

fn fbm_dw(p: vec2<f32>, t: f32) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * vnoise2(pp);
        let warp = v * 0.3;
        pp = pp * 2.1 + vec2<f32>(1.7 + warp, 9.2 - warp) + vec2<f32>(t * 0.01, -t * 0.007);
        a *= 0.5;
    }
    return v;
}

// ── Voronoi / Worley Noise ──
fn voronoi(p: vec2<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 999.0;
    var secondDist = 999.0;
    var cellId = vec2<f32>(0.0);
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = neighbor + vec2<f32>(h2(i + neighbor), h2(i + neighbor + 7.31));
            let diff = neighbor + point - f;
            let d = dot(diff, diff);
            if (d < minDist) {
                secondDist = minDist;
                minDist = d;
                cellId = i + neighbor;
            } else if (d < secondDist) {
                secondDist = d;
            }
        }
    }
    return vec2<f32>(sqrt(minDist), sqrt(secondDist));
}

fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 999.0;
    var secondDist = 999.0;
    for (var z: i32 = -1; z <= 1; z++) {
        for (var y: i32 = -1; y <= 1; y++) {
            for (var x: i32 = -1; x <= 1; x++) {
                let neighbor = vec3<f32>(f32(x), f32(y), f32(z));
                let point = neighbor + vec3<f32>(h3(i + neighbor), h3(i + neighbor + 7.31), h3(i + neighbor + 13.17));
                let diff = neighbor + point - f;
                let d = dot(diff, diff);
                if (d < minDist) {
                    secondDist = minDist;
                    minDist = d;
                } else if (d < secondDist) {
                    secondDist = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(minDist), sqrt(secondDist));
}

// ── Fresnel-Schlick for gem surfaces ──
fn fresnelSchlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
    return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cosTheta, 5.0);
}

// ── Enhanced Quasicrystal with n-fold symmetry ──
fn quasicrystal(uv: vec2<f32>, n: i32, t: f32, angle: f32, warp: f32) -> f32 {
    var value = 0.0;
    let invN = 1.0 / f32(n);
    for (var i: i32 = 0; i < n; i = i + 1) {
        let theta = angle + TAU * f32(i) * invN;
        let freq = 10.0 + warp * sin(t * 0.1 + f32(i) * 0.5);
        value += cos(dot(uv, vec2<f32>(cos(theta), sin(theta))) * freq + t * (1.0 + f32(i) * 0.1));
    }
    return value * invN;
}

// ── Enhanced quasicrystal with second-order harmonics ──
fn quasicrystal2(uv: vec2<f32>, n: i32, t: f32, angle: f32) -> f32 {
    let q1 = quasicrystal(uv, n, t, angle, 1.0);
    let q2 = quasicrystal(uv * 1.618, n, t * 0.7, angle + PI * 0.1, 0.5);
    let q3 = quasicrystal(uv * 0.618, n, t * 1.3, angle - PI * 0.05, 0.3);
    return q1 * 0.6 + q2 * 0.3 + q3 * 0.1;
}

// Branchless tri-color metallic cycle with audio reactivity
fn metallicColor(pattern: f32, t: f32, bass: f32) -> vec3<f32> {
    let gold   = vec3<f32>(1.0, 0.84, 0.0);
    let silver = vec3<f32>(0.75, 0.75, 0.75);
    let bronze = vec3<f32>(0.8, 0.5, 0.2);
    let m = fract(pattern + t * 0.05 + bass * 0.2) * 3.0;
    let s1 = step(1.0, m);
    let s2 = step(2.0, m);
    let c0 = mix(gold, silver, m);
    let c1 = mix(silver, bronze, m - 1.0);
    let c2 = mix(bronze, gold, m - 2.0);
    return mix(mix(c0, c1, s1), c2, s2);
}

// Gem-like Fresnel surface color
fn gemColor(normal: vec3<f32>, viewDir: vec3<f32>, baseColor: vec3<f32>, t: f32) -> vec3<f32> {
    let cosTheta = max(dot(normal, viewDir), 0.0);
    let f0 = vec3<f32>(0.17, 0.35, 0.45); // Gem-like F0
    let fresnel = fresnelSchlick(cosTheta, f0);
    let dispersion = vec3<f32>(
        1.0 + 0.1 * sin(t * 0.3),
        1.0 + 0.05 * sin(t * 0.3 + 1.0),
        1.0 + 0.15 * sin(t * 0.3 + 2.0)
    );
    return baseColor * (1.0 - fresnel) + fresnel * dispersion;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01  = vec2<f32>(pixel) / res;
    let uv    = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time  = u.config.x;
    let bass  = plasmaBuffer[0].x;
    let mids  = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depthIn = textureLoad(readDepthTexture, pixel, 0).r;
    let prev  = textureLoad(dataTextureC, pixel, 0);

    // Mouse Y-flip: screen-top = +Y/up
    let mouseY = 1.0 - u.zoom_config.z;
    let mousePos = vec2<f32>(u.zoom_config.y, mouseY);

    let symmetry   = i32(mix(5.0, 13.0, u.zoom_params.x));
    let density    = mix(3.0, 15.0, u.zoom_params.y);
    let colorCycle = u.zoom_params.z;
    let projAngle  = mix(0.0, TAU, u.zoom_params.w);

    // Anti-moiré: scale pattern coordinate at extreme densities
    let densityScale = mix(1.0, 0.65, smoothstep(8.0, 14.0, density));
    let shimmerFreq  = mix(10.0, 6.0, smoothstep(8.0, 14.0, density));

    var p = uv * density * densityScale;
    // Mouse warps the crystal field
    let mouseWarp = (mousePos - 0.5) * 2.0;
    p = rot2(time * 0.05 + projAngle + bass * 0.1) * p;
    p += mouseWarp * 0.1 * sin(time * 0.3);

    // Domain-warped background
    let bgWarp = fbm_dw(p * 2.0 + time * 0.02, time);
    p += bgWarp * 0.05;

    // Primary + secondary quasicrystal layers with enhanced harmonics
    let qc = quasicrystal2(p, symmetry, time * 0.2, projAngle);
    let pattern = smoothstep(-0.2, 0.2, qc);

    let qc2 = quasicrystal2(p * 1.5 + 0.5, symmetry, time * 0.15, projAngle + 0.1);
    let pattern2 = smoothstep(-0.1, 0.1, qc2);

    // Metallic base with audio reactivity and gem-like Fresnel
    let metallicBase = metallicColor(qc + qc2, time * colorCycle, bass);
    let viewDir = normalize(vec3<f32>(uv, 1.0));
    let crystalNormal = normalize(vec3<f32>(qc, qc2, 1.0));
    var col = gemColor(crystalNormal, viewDir, metallicBase, time) * (1.0 + bass * 0.3 + treble * 0.1);

    // Gem accents with Voronoi texture
    let gemVoro = voronoi(p * 8.0 + time * 0.05);
    let gemLocations = fract(qc * 5.0 + qc2 * 3.0 + gemVoro.x);
    let gemMask = smoothstep(0.48, 0.5, gemLocations) * smoothstep(0.52, 0.5, gemLocations);
    let gemIdx = i32(fract(qc * 10.0 + gemVoro.x) * 5.0);
    let gemPal = array<vec3<f32>, 5>(
        vec3<f32>(0.9, 0.1, 0.2), vec3<f32>(0.1, 0.6, 0.9),
        vec3<f32>(0.1, 0.8, 0.3), vec3<f32>(0.9, 0.5, 0.1),
        vec3<f32>(0.7, 0.2, 0.8)
    );
    let gemFresnel = fresnelSchlick(max(dot(crystalNormal, viewDir), 0.0), vec3<f32>(0.1, 0.2, 0.3));
    col = mix(col, gemPal[gemIdx] * (1.0 + gemFresnel), gemMask * 0.6);

    // Edge highlights with Voronoi crackle
    let edgeMask = smoothstep(0.05, 0.0, abs(qc));
    let crackle = smoothstep(0.02, 0.0, gemVoro.y - gemVoro.x);
    col += vec3<f32>(1.0, 0.95, 0.8) * edgeMask * 0.4 * (1.0 + crackle);

    // Subtle shimmer with domain-warped FBM
    let shimmer = sin(p.x * shimmerFreq * 2.0 + time) * sin(p.y * shimmerFreq * 2.0 + time * 1.3);
    let shimmerDetail = fbm_dw(p * 4.0 + time * 0.1, time);
    col += vec3<f32>(0.02, 0.015, 0.025) * shimmer * (1.0 + shimmerDetail);

    // Voronoi-based surface texture
    let voroSurface = voronoi(p * 3.0 + time * 0.02);
    let surfaceBump = smoothstep(0.05, 0.0, voroSurface.x) * 0.1;
    col += surfaceBump * vec3<f32>(0.9, 0.85, 0.7);

    // Vignette
    col *= 1.0 - length(uv01 - 0.5) * 0.5;

    // Post-process: neon glow, generative chromatic aberration, ACES
    col = neonGlow(col, 0.35 + mids * 0.25);
    let caStr = 0.003 * (1.0 + bass) + depthIn * 0.001;
    col = genChromaticShift(col, uv01, caStr);
    col = acesToneMap(col * (0.9 + mids * 0.2));

    // Temporal feedback via dataTextureC
    let decay = 0.96;
    let trail = mix(prev.rgb * decay, col, 0.25 + bass * 0.1);

    // Depth-aware semantic alpha
    let depth = pattern * 0.5 + pattern2 * 0.3 + gemMask * 0.2;
    let bloom = smoothstep(0.5, 1.2, luma(col));
    let alpha = clamp(luma(trail) * 1.2 + depth * 0.2, 0.25, 0.95);

    textureStore(writeTexture, pixel, vec4<f32>(trail, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, alpha));
    textureStore(dataTextureB, pixel, vec4<f32>(col, bloom));
}

```

## Current JSON Definition
```json
{
  "id": "gen-quasicrystal",
  "name": "Quasicrystal",
  "category": "generative",
  "tags": [
    "generative",
    "quasicrystal",
    "symmetry",
    "mathematical",
    "procedural",
    "audio",
    "music",
    "reactive",
    "domain-warping",
    "voronoi",
    "fresnel",
    "gem"
  ],
  "description": "Penrose tiling-inspired quasicrystal patterns with n-fold symmetry using the projection method from higher-dimensional lattices. Upgraded with domain-warped FBM, Voronoi/Worley noise, Fresnel-Schlick gem surfaces, enhanced harmonics, and deep audio reactivity.",
  "workgroup_size": [
    16,
    16,
    1
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Symmetry Order",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Pattern Density",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Color Cycling",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Projection Angle",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "supportsDepth": true,
  "supportsDof": false,
  "updated": true,
  "url": "shaders/gen-quasicrystal.wgsl",
  "features": []
}
```

---

## Agent Specialization
# Agent Role: Audio Reactivity Specialist (Phase B)

## Identity
You are the **Audio Reactivity Specialist**. Your job is to make shaders respond musically to the audio stream already bound to `plasmaBuffer`.

## Audio Binding (canonical)
```wgsl
let bass   = plasmaBuffer[0].x;  // 20–200 Hz, ~0–2
let mids   = plasmaBuffer[0].y;  // 200–2000 Hz, ~0–2
let treble = plasmaBuffer[0].z;  // 2k–20k Hz, ~0–2
```

## Patterns
- **Bass pulse**: scale/brightness/intensity *= `1.0 + bass * 0.5`.
- **Mids morph**: rotation speed, pattern evolution, color cycling *= `1.0 + mids * 0.5`.
- **Treble sparkle**: add high-frequency detail or shimmer.
- **Envelope smoothing** (preferred over raw bass):
  ```wgsl
  fn bass_env(prev: f32, bass: f32) -> f32 {
      let k = select(0.15, 0.8, bass > prev);
      return mix(prev, bass, k);
  }
  ```
  Store `prev` in `dataTextureA.r` if the shader has free feedback.

## Output Rules
- Add at least one musically coherent audio-driven parameter.
- Update JSON `features` to include `audio-reactive`.
- Do NOT modify the 13-binding header or `Uniforms` struct.
- Workgroup size stays `@workgroup_size(16, 16, 1)`.
- Return exactly one ```` ```wgsl ```` block.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 200 lines (±20%).
5. Write a brief upgrade rationale (2-3 sentences).

## Output Format
Return exactly two code blocks:
1. ```wgsl
[upgraded shader source]
```
2. ```json
[updated shader definition]
```

If the JSON does not need changes, return the original JSON unchanged.
