# KIMI SWARM TASK — UPGRADE — rain-ripples

## Role Assignment
**Primary Agent:** Algorithmist  
**Domain:** advanced math, simulation depth, SDF/fractal/noise upgrades

## Shader Identity
- **ID:** `rain-ripples`
- **Name:** Rain Ripples
- **Category:** liquid-effects
- **Current lines:** 109
- **Target lines:** 149 (max)
- **Current description:** Interactive water ripples and raindrops.

## Creative Brief
Upgrade `rain-ripples` while preserving its original visual soul. The algorithmist should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

## OUTPUT CONTRACT (non-negotiable)
1. Your entire response after the closing ``` of the WGSL block must be completely empty.
2. The shader must use the exact 13-binding header above (no `outputTex`, `videoSampler`, `iTime`, `mouse`).
3. Compute entry must be `@compute @workgroup_size(16, 16, 1)`.
4. Alpha must carry semantic meaning (density, energy, depth, or bloom weight). Never end with `vec4(..., 1.0)` unless opaque by design.
5. Use at least two techniques from the Kimi graphical tactics below.
6. Stay within the line budget.

## IMMUTABLE 13-BINDING CONTRACT (copy EXACTLY)
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4
  ripples: array<vec4<f32>, 50>,
};
```

## CURRENT SOURCE WGSL
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Rain Ripples
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
// ═══════════════════════════════════════════════════════════════════

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv    = vec2<f32>(global_id.xy) / resolution;
    let currentTime = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let aspect = resolution.x / max(resolution.y, 0.001);

    // Accumulate displacement from all active ripples
    var totalDisplacement = vec2<f32>(0.0);

    for (var i: u32 = 0u; i < 50u; i = i + 1u) {
        let ripple    = u.ripples[i];
        let ripplePos = ripple.xy;
        let startTime = ripple.z;

        // Loop guards are acceptable
        if (startTime <= 0.0) { continue; }

        let elapsed = currentTime - startTime;
        if (elapsed < 0.0 || elapsed > 2.0) { continue; }

        let uvCorrected  = vec2<f32>(uv.x * aspect, uv.y);
        let posCorrected = vec2<f32>(ripplePos.x * aspect, ripplePos.y);

        // Safe distance (avoid divide-by-zero in normalize below)
        let diffVec = uvCorrected - posCorrected;
        let distSafe = max(length(diffVec), 0.0001);

        let speed      = 0.5;
        let radius     = speed * elapsed;
        let distFromWave = distSafe - radius;
        let waveWidth  = 0.05;

        // Branchless wave mask using smoothstep instead of if(abs(distFromWave) < waveWidth)
        let waveMask = smoothstep(waveWidth, 0.0, abs(distFromWave));

        let profile   = cos(distFromWave / max(waveWidth, 0.001) * 3.14159 * 2.0);
        let decay     = max(0.0, 1.0 - elapsed / 2.0);
        let distDecay = max(0.0, 1.0 - distSafe * 2.0);

        // Bass scales ripple amplitude
        let amplitude = profile * decay * distDecay * 0.03 * (1.0 + bass * 0.4) * waveMask;

        let dir = diffVec / distSafe;
        totalDisplacement = totalDisplacement - dir * amplitude;
    }

    let displacedUV = uv + totalDisplacement;

    // Sample texture
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

    // Branchless specular highlight using smoothstep instead of if(length > 0.001)
    let dispMag     = length(totalDisplacement);
    let highlight   = smoothstep(0.0005, 0.002, dispMag);
    let highlightColor = vec3<f32>(0.1, 0.1, 0.15) * highlight;
    color = vec4<f32>(color.rgb + highlightColor, color.a);

    // Meaningful alpha: displacement magnitude + bass pulse
    let alpha = clamp(dispMag * 30.0 + bass * 0.25 + mids * 0.1, 0.0, 1.0);

    let finalColor = vec4<f32>(color.rgb, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);

    // Depth passthrough
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "rain-ripples",
  "name": "Rain Ripples",
  "url": "shaders/rain-ripples.wgsl",
  "description": "Interactive water ripples and raindrops.",
  "params": [
    {
      "id": "param1",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Detail",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "tags": [
    "filter",
    "image-processing"
  ]
}
```

### Kimi Graphical Tactics (apply where appropriate)
- **Hue-preserving HDR clamp**: `fn hue_preserve_clamp(c, max_lum)` before tone map.
- **ACES filmic tonemap**: `fn aces(x)` as final color transform.
- **IGN blue-noise dither**: `fn ign(p)` before `textureStore` to kill banding.
- **Anti-aliased SDF step**: `fn aa_step(edge, x)` using `fwidth`.
- **Smooth-min SDF union**: `fn smin(a, b, k)`.
- **Domain-warped FBM**: `fn warpedFBM(p, t)` for organic flow.
- **Polar kaleidoscope fold**: `fn kaleido(uv, segs)`.
- **Hex bokeh sampling**: `HEX_TAPS` array for blur/DOF.
- **Audio-reactive envelope**: `fn bass_env(prev, bass, attack, release)` with state in `dataTextureA`.
- **Depth-aware compositing**: sample `readDepthTexture`, use exponential fog/mix.
- **Anti-moiré LOD bias**: `lod = clamp(log2(fwidth(uv) * cell_freq), 0, 4)`.
- **Premultiplied-alpha writeback**: `textureStore(writeTexture, gid.xy, vec4(rgb*a, a))`.

## ROLE TOOLKIT — Algorithmist
See `agents/prompt-templates/algorithmist.md` for the full toolkit. Use the canonical snippets from `agents/WGSL_BUILTINS_GENERATIVE.md`.

## LINE BUDGET & FINAL REMINDER
Target: 149 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
