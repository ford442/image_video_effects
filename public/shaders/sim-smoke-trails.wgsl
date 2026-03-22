// ═══════════════════════════════════════════════════════════════════
//  Sim: Smoke Trails
//  Category: simulation
//  Features: simulation, volumetric-smoke, vorticity, buoyancy
//  Complexity: High
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Volumetric smoke with vorticity confinement
//  Simplified fluid sim - smoke seeded at bottom/mouse, buoyancy drives up
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

// Curl noise for vorticity
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.01;
    let n1 = noise(p + vec2<f32>(eps, 0.0));
    let n2 = noise(p - vec2<f32>(eps, 0.0));
    let n3 = noise(p + vec2<f32>(0.0, eps));
    let n4 = noise(p - vec2<f32>(0.0, eps));
    return vec2<f32>((n4 - n3) / (2.0 * eps), (n1 - n2) / (2.0 * eps));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let pixel = 1.0 / resolution;
    let time = u.config.x;
    
    // Parameters
    let densityScale = mix(0.5, 2.0, u.zoom_params.x);   // x: Smoke density
    let turbulence = mix(0.0, 2.0, u.zoom_params.y);     // y: Turbulence strength
    let riseSpeed = mix(0.5, 3.0, u.zoom_params.z);      // z: Rise speed
    let dissipation = mix(0.95, 0.995, u.zoom_params.w); // w: Dissipation rate
    
    // Read previous smoke state
    let prevSmoke = textureLoad(dataTextureC, gid.xy, 0);
    var smokeDensity = prevSmoke.r;
    var smokeTemp = prevSmoke.g;
    var velX = prevSmoke.b;
    var velY = prevSmoke.a;
    
    // Buoyancy force (hot smoke rises)
    let buoyancy = smokeTemp * riseSpeed * 0.01;
    velY += buoyancy;
    
    // Add turbulence
    let curl = curlNoise(uv * 3.0 + time * 0.1);
    velX += curl.x * turbulence * 0.01;
    velY += curl.y * turbulence * 0.005;
    
    // Advect smoke
    let prevUV = uv - vec2<f32>(velX, velY) * pixel * 3.0;
    let advectedSmoke = textureSampleLevel(dataTextureC, u_sampler, clamp(prevUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    smokeDensity = advectedSmoke.r * dissipation;
    smokeTemp = advectedSmoke.g * dissipation;
    
    // Seed smoke at bottom
    let bottomSource = smoothstep(0.05, 0.0, uv.y) * hash12(vec2<f32>(uv.x * 10.0, time * 0.5)) * densityScale;
    smokeDensity += bottomSource * 0.05;
    smokeTemp += bottomSource * 0.1;
    
    // Mouse smoke source
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    let mouseSource = smoothstep(0.08, 0.0, mouseDist) * 0.2;
    smokeDensity += mouseSource;
    smokeTemp += mouseSource * 1.5;
    
    // Ripple smoke sources
    for (var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let rippleAge = time - ripple.z;
            if (rippleAge > 0.0 && rippleAge < 4.0) {
                let rippleDist = length(uv - ripple.xy);
                let rippleSource = smoothstep(0.06, 0.0, rippleDist) * (1.0 - rippleAge / 4.0);
                smokeDensity += rippleSource * 0.3;
                smokeTemp += rippleSource * 0.5;
            }
        }
    }
    
    smokeDensity = clamp(smokeDensity, 0.0, 1.0);
    smokeTemp = clamp(smokeTemp, 0.0, 1.0);
    
    // Store state
    textureStore(dataTextureA, gid.xy, vec4<f32>(smokeDensity, smokeTemp, velX * 0.99, velY * 0.99));
    
    // Render smoke
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Smoke color - gray with fire tint at high temperature
    let smokeGray = vec3<f32>(0.7, 0.7, 0.75);
    let fireColor = vec3<f32>(1.0, 0.4, 0.1);
    let smokeColor = mix(smokeGray, fireColor, smokeTemp * 0.7);
    
    // Volumetric-style blending
    let alpha = 1.0 - exp(-smokeDensity * 3.0);
    var color = mix(baseColor, smokeColor, alpha * 0.8);
    
    // Add glow at hot spots
    let glow = smokeTemp * smokeDensity * 0.3;
    color += vec3<f32>(glow * 1.2, glow * 0.5, glow * 0.2);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    textureStore(writeTexture, gid.xy, vec4<f32>(color, mix(0.85, 1.0, alpha)));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * (1.0 - smokeDensity * 0.3), 0.0, 0.0, 0.0));
}
