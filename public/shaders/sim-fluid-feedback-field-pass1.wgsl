// ═══════════════════════════════════════════════════════════════════
//  Sim: Fluid Feedback Field (Pass 1 - Velocity Advection)
//  Category: simulation
//  Features: simulation, multi-pass-1, navier-stokes, velocity-advection
//  Complexity: Very High
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Pass 1: Advect velocity field through itself
//  Add curl noise for turbulence
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Viscosity, y=Turbulence, z=MouseForce, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ NOISE FUNCTIONS ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ═══ CURL NOISE ═══
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.01;
    let n1 = noise(p + vec2<f32>(eps, 0.0));
    let n2 = noise(p - vec2<f32>(eps, 0.0));
    let n3 = noise(p + vec2<f32>(0.0, eps));
    let n4 = noise(p - vec2<f32>(0.0, eps));
    return vec2<f32>((n4 - n3) / (2.0 * eps), (n1 - n2) / (2.0 * eps));
}

// ═══ MAIN: VELOCITY ADVECTION ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let pixel = 1.0 / resolution;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Parameters — bass amplifies turbulence
    let viscosity = mix(0.9, 0.999, u.zoom_params.x);
    let turbulence = u.zoom_params.y * 2.0 * (1.0 + bass * 0.5);
    let mouseForce = clamp(u.zoom_params.z, 0.0, 1.0);

    // Curl-noise seed (divergence-free) modulated by mouse stir
    let curl = curlNoise(uv * 5.0 + time * 0.1);
    var newVel = curl * turbulence * 0.1;

    // Mouse impulse — radial outward push (Gaussian)
    let toMouse = uv - mouse;
    let dM2 = dot(toMouse, toMouse);
    let mouseGate = exp(-dM2 * 60.0) * (mouseForce + mouseDown * 0.5);
    newVel = newVel + (toMouse / max(length(toMouse), 1e-4)) * 0.4 * mouseGate;

    // Apply viscosity (damping)
    newVel *= viscosity;
    
    // Store new velocity in dataTextureA
    textureStore(dataTextureA, gid.xy, vec4<f32>(newVel, 0.0, 1.0));
    
    // Pass-through input to maintain chain (Pass 2 will do final compositing)
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    textureStore(writeTexture, gid.xy, inputColor);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(1.0, 0.0, 0.0, 0.0));
}
