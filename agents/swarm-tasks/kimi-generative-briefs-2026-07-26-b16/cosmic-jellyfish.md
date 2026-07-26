# Swarm Brief: cosmic-jellyfish

**Role:** Visualist
**Name:** Cosmic Jellyfish
**Category:** generative
**Description:** A majestic, translucent jellyfish floating in a cosmic void, with bioluminescent glow and rhythmic pulsation.
**Current lines:** 195
**Target lines:** 245–285 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This raymarched jelly computes a temporal trail buffer and then THROWS IT AWAY - unlock the trails, then give it sound and honest depth:
- DISPLAY THE DEAD FEEDBACK (priority 1): the shader computes `temporal = mix(prev*0.96, col, 0.25)` into dataTextureA but displays raw `col` - the feedback loop is dead code. Display it: `col = mix(col, temporal, 0.6)` before output so the jelly leaves bioluminescent motion trails. Keep the 0.96 decay (< 1.0, stable) and clamp the accumulated trail pre-tint at ~1.2.
- Honest depth + tonemap: writeDepthTexture currently stores flat 0.0, clobbering scene depth for chained shaders - write the real raymarch hit distance (normalized). There is no tonemap and Glow Intensity goes to 5.0 - add hue-preserving clamp + ACES before output.
- Audio + palette: bass (`plasmaBuffer[0].x`) drives the bell pulse amplitude, treble (`plasmaBuffer[0].z`) drives tentacle wave frequency; replace the Rodrigues RGB hue rotation with an IQ cosine palette for the glow (cheaper, smoother).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the `map()` SDF structure (bell hollow + 8-tentacle capsule loop, smin k=0.2) VERBATIM - the creature silhouette is hand-tuned. Keep the u.zoom_params reads INSIDE map() (moving them changes the SDF's implicit contract). JSON param ranges exceed 0-1 (Pulse Speed 0-2, Glow 0-5) - keep defaults/ranges EXACTLY.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "cosmic-jellyfish",
  "name": "Cosmic Jellyfish",
  "url": "shaders/cosmic-jellyfish.wgsl",
  "description": "A majestic, translucent jellyfish floating in a cosmic void, with bioluminescent glow and rhythmic pulsation.",
  "tags": [
    "3d",
    "raymarching",
    "bioluminescent",
    "space",
    "organic",
    "calm",
    "procedural",
    "generative"
  ],
  "features": [
    "mouse-driven",
    "temporal"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Pulse Speed",
      "default": 0.5,
      "min": 0,
      "max": 2,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Tentacle Activity",
      "default": 0.5,
      "min": 0,
      "max": 2,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Hue Shift",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Glow Intensity",
      "default": 1,
      "min": 0,
      "max": 5,
      "step": 0.1,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Pulse Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 2.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Tentacle Activity",
      "default": 0.5,
      "min": 0.0,
      "max": 2.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Hue Shift",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Glow Intensity",
      "default": 1,
      "min": 0.0,
      "max": 5.0,
      "step": 0.1
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════
//  Cosmic Jellyfish - A majestic, translucent jellyfish in a cosmic void.
//  Category: generative
//  Features: 3d, raymarching, bioluminescent, space, organic, calm
// ═══════════════════════════════════════════════════════════════

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

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// SDF for the Jellyfish
fn map(p: vec3<f32>, time: f32) -> f32 {
    // Pulse animation
    let pulse_speed = u.zoom_params.x * 2.0;
    let pulse = sin(time * pulse_speed) * 0.1;

    // Tentacle Activity
    let tentacle_amp = u.zoom_params.y;

    // Bell (Ellipsoid-ish)
    var p_bell = p;
    p_bell.y -= 0.5;

    // Stretch
    let d_bell = length(p_bell / vec3<f32>(1.0 + pulse, 0.8 - pulse, 1.0 + pulse)) * 0.8 - 0.5;

    // Hollow out bottom
    let d_hollow = length(p_bell + vec3<f32>(0.0, 0.5, 0.0)) - 0.4;
    let bell_final = max(d_bell, -d_hollow);

    // Tentacles
    var d_tentacles = 100.0;
    let num_tentacles = 8.0;
    for (var i = 0.0; i < num_tentacles; i = i + 1.0) {
        var angle = (i / num_tentacles) * 6.28318;
        let radius = 0.3;
        let tentacle_pos = vec3<f32>(cos(angle) * radius, 0.0, sin(angle) * radius);
        var p_t = p - tentacle_pos;

        // Waving motion
        p_t.x += sin(p_t.y * 3.0 + time * 2.0 + i) * 0.1 * tentacle_amp;
        p_t.z += cos(p_t.y * 3.0 + time * 2.0 + i) * 0.1 * tentacle_amp;

        // Capsule shape for tentacle
        p_t.y += 1.0; // Shift down
        var h = 2.0; // Length
        p_t.y = clamp(p_t.y, 0.0, h);
        let d_t = length(p_t) - 0.05 * (1.0 - p_t.y / h); // Taper

        d_tentacles = min(d_tentacles, d_t);
    }

    // Smooth blend bell and tentacles
    return smin(bell_final, d_tentacles, 0.2);
}

// Simple hash for stars
fn hash(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn stars(dir: vec3<f32>) -> f32 {
    var p = dir * 100.0;
    let cell = floor(p);
    let local = fract(p);
    var n = cell.x + cell.y * 57.0 + cell.z * 113.0;
    var h = hash(n);
    if (h > 0.95) {
        let star_pos = vec3<f32>(hash(n + 1.0), hash(n + 2.0), hash(n + 3.0));
        var d = length(local - star_pos);
        return smoothstep(0.1, 0.0, d);
    }
    return 0.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let time = u.config.x;
    let texUV = vec2<f32>(global_id.xy) / resolution;
    let prev = textureSampleLevel(dataTextureC, u_sampler, texUV, 0.0);

    // Camera
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    var ro = vec3<f32>(0.0, 0.0, -4.0);
    // Rotate camera based on mouse
    var cam_rot = rot(mouse.x * 2.0);
    ro.x = cam_rot[0][0] * ro.x + cam_rot[0][1] * ro.z;
    ro.z = cam_rot[1][0] * ro.x + cam_rot[1][1] * ro.z;

    cam_rot = rot(mouse.y * 2.0);
    ro.y = cam_rot[0][0] * ro.y + cam_rot[0][1] * ro.z;
    ro.z = cam_rot[1][0] * ro.y + cam_rot[1][1] * ro.z;

    let target_pos = vec3<f32>(0.0, 0.0, 0.0);
    let f = normalize(target_pos - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let up = cross(f, r);
    let rd = normalize(f + r * uv.x + up * uv.y);

    // Raymarch loop
    var t = 0.0;
    var glow = 0.0;
    var hit = false;

    for(var i=0; i<64; i++) {
        var p = ro + rd * t;
        var d = map(p, time);

        // Accumulate glow near the surface
        glow += 1.0 / (1.0 + d * d * 20.0);

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 10.0) { break; }
        t += d;
    }

    // Coloring
    var col = vec3<f32>(0.0);

    // Starfield background
    col += vec3<f32>(stars(rd));

    if (hit) {
        var p = ro + rd * t;
        // Simple normal calculation
        let e = vec2<f32>(0.01, 0.0);
        var n = normalize(vec3<f32>(
            map(p + e.xyy, time) - map(p - e.xyy, time),
            map(p + e.yxy, time) - map(p - e.yxy, time),
            map(p + e.yyx, time) - map(p - e.yyx, time)
        ));

        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        let base_color = vec3<f32>(0.2, 0.5, 0.8);
        col = base_color * diff * 0.5 + base_color * fresnel * 0.8;
    }

    // Add accumulated glow (bioluminescence)
    let hue_shift = u.zoom_params.z;
    var glowColor = vec3<f32>(0.1, 0.4, 0.9); // Base Blue

    // Simple hue shift logic (rotate RGB)
    var angle = hue_shift * 6.28;
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cos_angle = cos(angle);
    glowColor = glowColor * cos_angle + cross(k, glowColor) * sin(angle) + k * dot(k, glowColor) * (1.0 - cos_angle);

    let glow_intensity = u.zoom_params.w;
    col += glow * glowColor * glow_intensity * 0.02;

    // Temporal feedback via dataTextureA
    let decay = 0.96;
    let temporal = mix(prev.rgb * decay, col, 0.25);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(temporal, 1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
```
