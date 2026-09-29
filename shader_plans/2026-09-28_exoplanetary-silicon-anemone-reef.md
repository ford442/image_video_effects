# New Shader Plan: Exoplanetary Silicon-Anemone Reef

## Overview
A hyper-dense, undulating field of bioluminescent synthetic anemones swaying in a cosmic ocean of quantum foam, bridging the gap between deep-sea biology and futuristic silicate-based life.

## Features
- Thousands of dynamic, semi-translucent tentacles reacting to phantom currents.
- Iridescent, color-shifting subsurface scattering simulating liquid light inside silicon structures.
- A "plankton" particle system generated from noise-driven SDF intersections.
- Audio-reactive tentacle contraction and bioluminescent pulse intensity.
- Interactive mouse gravity that parts the anemones or pulls them into a swirling vortex.
- Procedural alien seafloor with cymatic interference patterns.
- High-fidelity fake ambient occlusion and bloom for that deep-sea alien vibe.

## Technical Implementation
- File: public/shaders/gen-exoplanetary-silicon-anemone-reef.wgsl
- Category: generative
- Tags: ["organic", "bioluminescent", "alien", "underwater", "tentacles", "subsurface-scattering"]
- Algorithm: Raymarching an SDF field of domain-repeated, noise-perturbed cylindrical structures with complex domain warping for the swaying motion.

### Core Algorithm
The scene is built using a primary raymarcher over an infinite grid (domain repetition `p.xz = (fract(p.xz / spacing) - 0.5) * spacing`).
The core SDF is a tapered, rounded cylinder representing a tentacle. To achieve the organic swaying, the space is deformed *before* evaluating the SDF using low-frequency 3D noise and sine waves based on time and height (`p.y`). The base of the domain contains a displaced plane for the rocky cymatic seabed.

### Mouse Interaction
The mouse acts as a localized gravity well or repulsor depending on click state. When `u.zoom_config.w > 0.0`, `u.zoom_config.y` and `z` dictate a position in world space. Tentacles within a certain radius of this point are warped towards or away from it using a smoothstep-attenuated translation applied during the SDF evaluation.

### Color Mapping / Shading
Shading relies heavily on fake subsurface scattering (evaluating the SDF at several points along the normal towards the light) combined with an iridescent rim light based on the view vector and normal dot product. The tips of the anemones emit a bright, shifting neon color (cyan to magenta) driven by `u.zoom_params.y` and audio reactivity.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Exoplanetary Silicon-Anemone Reef
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=ColorShift, z=CurrentSpeed, w=GlowIntensity
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 120;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 40.0;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise for organic movement
fn hash(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>( dot(p,vec3<f32>(127.1,311.7, 74.7)),
                       dot(p,vec3<f32>(269.5,183.3,246.1)),
                       dot(p,vec3<f32>(113.5,271.9,124.6)));
    return fract(sin(q)*43758.5453123);
}

// Tentacle SDF with space warping
fn sdTentacle(p_in: vec3<f32>, id: vec2<f32>) -> f32 {
    var p = p_in;

    // Sway driven by time, height, and id
    let time = u.config.x * u.zoom_params.z;
    let sway_offset = sin(p.y * 2.0 + time + id.x * 12.3 + id.y * 45.6) * 0.2 * p.y;
    p.x += sway_offset;
    p.z += cos(p.y * 1.5 + time * 0.8 + id.x) * 0.2 * p.y;

    // Taper
    let radius = mix(0.15, 0.01, clamp(p.y / 3.0, 0.0, 1.0));

    // Base cylinder length
    let h = 3.0 + hash(vec3<f32>(id.x, 0.0, id.y)).x * 1.5;

    let d = length(p.xz) - radius;
    let d_y = max(p.y - h, -p.y); // Bottom at 0, top at h

    return length(max(vec2<f32>(d, d_y), vec2<f32>(0.0))) + min(max(d, d_y), 0.0) - 0.02; // rounded edge
}

// Global scene map
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Mouse Interaction
    if (u.zoom_config.w > 0.0) {
        // Normalize mouse to rough world space bounds
        let mx = (u.zoom_config.y / u.config.z) * 2.0 - 1.0;
        let my = (u.zoom_config.z / u.config.w) * 2.0 - 1.0;
        let m_pos = vec3<f32>(mx * 10.0, 2.0, my * 10.0);

        let dist_to_mouse = length(p - m_pos);
        let influence = smoothstep(4.0, 0.0, dist_to_mouse);

        // Push away
        let dir = normalize(p - m_pos);
        p += dir * influence * 1.5;
    }

    // Domain repetition for anemone field
    let spacing = 1.0 / max(0.1, u.zoom_params.x); // Density control
    let id = floor(p.xz / spacing);
    var q = p;
    q.x = (fract(p.x / spacing) - 0.5) * spacing;
    q.z = (fract(p.z / spacing) - 0.5) * spacing;

    let d_tentacle = sdTentacle(q, id);

    // Seafloor
    let d_floor = p.y + sin(p.x*3.0)*0.1 + cos(p.z*2.5)*0.1;

    if (d_floor < d_tentacle) {
        return vec2<f32>(d_floor, 1.0); // ID 1 for floor
    }
    return vec2<f32>(d_tentacle, 2.0); // ID 2 for tentacle
}

// Standard normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy).x +
        e.yyx * map(p + e.yyx).x +
        e.yxy * map(p + e.yxy).x +
        e.xxx * map(p + e.xxx).x
    );
}

// Main Compute
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= texSize.x || fragCoord.y >= texSize.y) { return; }

    let uv = (fragCoord * 2.0 - texSize) / min(texSize.x, texSize.y);

    // Camera setup
    let ro = vec3<f32>(0.0, 4.0, -8.0);
    let target = vec3<f32>(0.0, 1.0, 0.0);
    let cw = normalize(target - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var dO: f32 = 0.0;
    var hitID: f32 = 0.0;
    var steps: i32 = 0;
    var p: vec3<f32>;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let d = map(p);
        if (d.x < SURF_DIST) {
            hitID = d.y;
            break;
        }
        if (dO > MAX_DIST) { break; }
        dO += d.x * 0.8; // conservative stepping
        steps++;
    }

    // Shading
    var col = vec3<f32>(0.01, 0.02, 0.05); // deep water bg

    if (dO < MAX_DIST) {
        let n = calcNormal(p);
        let viewDir = -rd;

        let lightPos = vec3<f32>(0.0, 10.0, 0.0);
        let l = normalize(lightPos - p);
        let diff = max(dot(n, l), 0.0);

        // Base AO from steps
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);

        if (hitID == 1.0) {
            // Floor
            col = vec3<f32>(0.05, 0.1, 0.15) * diff * ao;
        } else if (hitID == 2.0) {
            // Tentacle
            // Subsurface / Rim
            let rim = 1.0 - max(dot(viewDir, n), 0.0);
            let rimIntensity = smoothstep(0.6, 1.0, rim);

            // Color shift based on height and params
            let baseColor = vec3<f32>(0.1, 0.8, 0.9);
            let shiftColor = vec3<f32>(0.9, 0.2, 0.8);
            let tentacleColor = mix(baseColor, shiftColor, u.zoom_params.y + p.y*0.2);

            // Emission at tips
            let emission = smoothstep(2.0, 4.0, p.y) * u.zoom_params.w;

            col = tentacleColor * (diff * 0.5 + 0.2) * ao;
            col += tentacleColor * rimIntensity * 2.0;
            col += tentacleColor * emission * 3.0;
        }
    }

    // Depth fog
    let fog = 1.0 - exp(-0.02 * dO);
    col = mix(col, vec3<f32>(0.01, 0.02, 0.05), fog);

    // Tonemapping (ACES approximation)
    col = (col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14);
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));

    // Mock writes to satisfy standard requirements
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(dO / MAX_DIST, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(p, hitID));
}
```

## Parameters (for UI sliders)
- **Density** (`zoom_params.x`): default=1.0, min=0.5, max=2.0, step=0.1
- **Color Shift** (`zoom_params.y`): default=0.5, min=0.0, max=1.0, step=0.01
- **Current Speed** (`zoom_params.z`): default=1.0, min=0.0, max=3.0, step=0.1
- **Glow Intensity** (`zoom_params.w`): default=1.5, min=0.0, max=5.0, step=0.1

## Integration Steps
1. Create shader file `public/shaders/gen-exoplanetary-silicon-anemone-reef.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-exoplanetary-silicon-anemone-reef.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via `python scripts/sync_shaders_to_storage.py` (if applicable in local pipeline)
