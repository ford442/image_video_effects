# New Shader Plan: Abyssal Ferrofluid Singularity

## Overview
A hyper-dense, mathematically warped metallic liquid that constantly folds in on itself, evoking the feeling of gazing into a sentient, magnetic black hole. The aesthetic combines the slick, dark reflection of oily metal with pulsating, high-contrast energetic seams that leak glowing quantum radiation.

## Features
- Dynamic gyroid/SDF fusion creating a constantly shifting, spiky yet liquid surface.
- Subsurface scattering effect along thin edges to simulate dense magnetic fields glowing from within.
- Procedural iridescence on the peaks of the ferrofluid spikes based on view angle and normal curvature.
- Audio reactivity mapping bass to the overall density of spikes and treble to the brightness of the inner energy cracks.
- Orbiting camera logic that lets the viewer pan around the central magnetic anomaly.
- Fluid-like magnetic distortion when the mouse is dragged.

## Technical Implementation
- File: public/shaders/gen-abyssal-ferrofluid-singularity.wgsl
- Category: generative
- Tags: ["ferrofluid", "magnetic", "singularity", "metallic", "iridescent", "dark"]
- Algorithm: Raymarching against a complex SDF of a sphere displaced by a time-varying gyroid and multi-octave 3D noise, layered with gradient-based lighting and fake subsurface glowing effects.

### Core Algorithm
- Use raymarching to hit a base sphere centered at the origin.
- The base sphere is displaced heavily by a 3D noise function (e.g., fractional Brownian motion) combined with a gyroid function `sin(p.x)*cos(p.y) + sin(p.y)*cos(p.z) + sin(p.z)*cos(p.x)`.
- The displacement scale is modulated by a slow-moving time sine wave to simulate the rhythmic "breathing" or pulsation of the singularity.
- Smooth min/max operators are used to blend multiple overlapping ferrofluid spikes seamlessly.

### Mouse Interaction
- When `u.zoom_config.w > 0.5`, the mouse acts as a localized magnetic pole.
- The `u.zoom_config.yz` coordinates are mapped to world space and apply an attractive or repulsive inverse-square warp to the raymarching domain (`p`), bending the ferrofluid spikes toward the cursor.

### Color Mapping / Shading
- The base color is a very dark, glossy metallic gray/black, using Blinn-Phong or physically-based specular highlights for the slick look.
- Curvature (calculated from the normal differences) is used to map a bright iridescent palette (cyan/magenta/gold) to the sharpest peaks.
- Distance from the origin (density) is used to map an emissive glowing purple/blue gradient in the deep "cracks" between spikes.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Abyssal Ferrofluid Singularity
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
  config: vec4<f32>,              // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,         // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,         // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

// --- CONSTANTS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// --- MATH / NOISE HELPERS ---
fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn gyroid(p: vec3<f32>, scale: f32) -> f32 {
    let q = p * scale;
    return abs(dot(sin(q), cos(q.zxy)) / scale);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// --- SDF ---
fn getDist(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Magnetic Mouse Warp
    if (u.zoom_config.w > 0.5) {
        // Map mouse uv to -1 to 1 space
        let mouse_pos = (u.zoom_config.yz * 2.0) - 1.0;
        let p_warp = vec3<f32>(mouse_pos.x * 3.0, -mouse_pos.y * 3.0, 0.0);
        let dist_to_mouse = length(p - p_warp);
        if (dist_to_mouse < 2.0) {
            p = mix(p, p_warp, 1.0 - smoothstep(0.0, 2.0, dist_to_mouse));
        }
    }

    // Base Sphere
    let dSphere = length(p) - 1.5;

    // Audio Reactivity (bass drives displacement scale)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let dyn_scale = 3.0 + bass * 2.0;

    // Gyroid Displacement
    let dGyroid = gyroid(p + vec3<f32>(0.0, u.config.x * 0.2, 0.0), dyn_scale);

    // Breathing time displacement
    let breath = sin(u.config.x) * 0.1;

    // Combine
    return smin(dSphere, dGyroid - breath, 0.5) * 0.5; // Scale down for precision
}

// --- NORMALS ---
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = getDist(p);
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        getDist(p - e.xyy),
        getDist(p - e.yxy),
        getDist(p - e.yyx)
    );
    return normalize(n);
}

// --- MAIN COMPUTE ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let uv = vec2<f32>(id.xy) / vec2<f32>(dims);

    // Map to -1, 1 space correcting aspect ratio
    var p_uv = uv * 2.0 - 1.0;
    p_uv.x *= f32(dims.x) / f32(dims.y);

    // Camera setup
    let ro = vec3<f32>(sin(u.config.x * 0.2) * 4.0, sin(u.config.x * 0.1) * 2.0, cos(u.config.x * 0.2) * 4.0);
    let target = vec3<f32>(0.0);

    let cd = normalize(target - ro);
    let cr = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), cd));
    let cu = normalize(cross(cd, cr));

    let rd = normalize(cr * p_uv.x + cu * p_uv.y + cd * 1.5);

    // Raymarching
    var dO = 0.0;
    var dS = 0.0;
    var hit = false;
    for(var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        dS = getDist(p);
        dO += dS;
        if(dS < SURF_DIST) {
            hit = true;
            break;
        }
        if(dO > MAX_DIST) {
            break;
        }
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * dO;
        let n = getNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let reflectDir = reflect(-lightDir, n);
        let viewDir = normalize(ro - p);
        let spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0); // Simple specular

        // Fresnel / Iridescence
        let fresnel = 1.0 - max(dot(n, viewDir), 0.0);
        let iriCol = vec3<f32>(0.0, 1.0, 1.0) * pow(fresnel, 3.0) + vec3<f32>(1.0, 0.0, 1.0) * pow(fresnel, 5.0);

        // Core glow (inverse distance from center)
        let distCenter = length(p);
        let glow = smoothstep(1.5, 0.5, distCenter) * vec3<f32>(0.2, 0.0, 0.5) * clamp(plasmaBuffer[0].z, 0.0, 1.0); // Treble drives core glow

        col = vec3<f32>(diff * 0.1) + vec3<f32>(spec) + iriCol + glow;
    } else {
        // Background
        col = vec3<f32>(0.01, 0.01, 0.02) * (1.0 - length(p_uv));
    }

    let final_col = vec4<f32>(col, 1.0);

    // Write out all required textures to avoid pipeline regressions
    textureStore(writeTexture, id.xy, final_col);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(dO / MAX_DIST, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, final_col);
}
```

Parameters (for UI sliders)

Spike Density (5.0, 1.0, 10.0, 0.1)
Pulse Speed (1.0, 0.0, 5.0, 0.1)
Iridescence Mix (0.5, 0.0, 1.0, 0.05)
Glow Intensity (1.0, 0.0, 3.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
