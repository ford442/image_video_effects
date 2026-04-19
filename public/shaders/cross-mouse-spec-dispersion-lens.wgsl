// ═══════════════════════════════════════════════════════════════════
//  Crossover: Mouse + Spectral — Prismatic Lens
//  Category: interactive-mouse
//  Features: crossover, mouse-driven, spectral-rendering
//  Crosses: mouse-wormhole-lens (2C) + spec-prismatic-dispersion (3C)
//  Complexity: High
//  Created: 2026-04-19
//  By: Agent 5C — Phase C Crossover Integration
// ═══════════════════════════════════════════════════════════════════
//
//  The mouse cursor becomes a prismatic lens that spectrally disperses
//  the input image. Moving the mouse changes the lens focal point;
//  clicking increases the dispersion intensity. The lens uses physical
//  refraction with Cauchy's equation for wavelength-dependent IOR.
//
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

fn cauchyIOR(lambda: f32, n0: f32, B: f32) -> f32 {
    return n0 + B / (lambda * lambda);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let time = u.config.x;
    
    let lensRadius = mix(0.05, 0.3, u.zoom_params.x);
    let dispersionScale = mix(0.0, 0.03, u.zoom_params.y);
    let lensStrength = mix(0.5, 2.0, u.zoom_params.z);
    let rotationSpeed = mix(-1.0, 1.0, u.zoom_params.w);
    
    let clickBoost = select(1.0, 2.0, mouseDown);
    let localDispersion = dispersionScale * clickBoost;
    
    let toMouse = uv - mousePos;
    let mouseDist = length(toMouse);
    
    // Lens profile: parabolic thickness
    let lensProfile = max(0.0, 1.0 - (mouseDist * mouseDist) / (lensRadius * lensRadius));
    let lensFactor = lensProfile * lensStrength;
    
    // Rotation over time
    let angle = time * rotationSpeed * 0.2 + lensProfile * 3.14159;
    let ca = cos(angle);
    let sa = sin(angle);
    let rotDir = vec2<f32>(toMouse.x * ca - toMouse.y * sa, toMouse.x * sa + toMouse.y * ca);
    
    // Wavelengths for RGB
    let lambdaR = 650.0;
    let lambdaG = 530.0;
    let lambdaB = 460.0;
    let n0 = 1.4;
    let B = 3000.0;
    
    let iorR = cauchyIOR(lambdaR, n0, B);
    let iorG = cauchyIOR(lambdaG, n0, B);
    let iorB = cauchyIOR(lambdaB, n0, B);
    
    // Refraction displacement
    let normal = normalize(rotDir + vec2<f32>(0.0001));
    let dispR = normal * (iorR - iorG) * localDispersion * lensFactor;
    let dispB = normal * (iorB - iorG) * localDispersion * lensFactor;
    
    let sampleR = textureSampleLevel(readTexture, u_sampler, uv - dispR, 0.0).r;
    let sampleG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let sampleB = textureSampleLevel(readTexture, u_sampler, uv - dispB, 0.0).b;
    
    var finalColor = vec3<f32>(sampleR, sampleG, sampleB);
    
    // Add chromatic aberration glow inside lens
    let glow = lensProfile * 0.15 * clickBoost;
    finalColor = finalColor + vec3<f32>(glow * 0.8, glow * 0.5, glow * 1.0);
    
    // Alpha represents lens intensity
    let alpha = mix(1.0, 0.9, lensProfile * 0.3);
    
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, alpha));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
