// ═══════════════════════════════════════════════════════════════════
//  Hypnotic Spiral
//  Category: image
//  Features: interactive, spiral, visual, mouse-driven, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-17
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

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = fract(h + vec3<f32>(0.0, 0.66666667, 0.33333333)) * 6.0 - 3.0;
    return v * mix(vec3<f32>(1.0), clamp(abs(c) - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

fn hash12(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let minRes = min(resolution.x, resolution.y);
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / minRes;
    let time = u.config.x;
    let mousePos = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) - resolution * 0.5) / minRes;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let clickReverse = select(1.0, -1.0, u.zoom_config.w > 0.5);
    let breathe = sin(time * 0.5) * 0.3 + 1.0;
    let radius = length(uv) * breathe;
    let baseAngle = atan2(uv.y, uv.x);
    let arms = max(1.0, u.zoom_params.x);
    let rotSpeed = (u.zoom_params.y + bass * 0.5) * clickReverse;
    var twist = 1.0 / (length(uv - mousePos) * u.zoom_params.w + 0.1);
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rPos = (r.xy - resolution * 0.5) / minRes;
        let dist = length(uv - rPos);
        let age = time - r.z;
        twist += sin(dist * 20.0 - age * 8.0) * exp(-age * 2.0) * 0.5 / (dist + 0.1);
    }
    let twistedAngle = baseAngle + radius * rotSpeed * twist;
    let spiralPattern = sin(arms * twistedAngle - time * rotSpeed + radius * 10.0);
    let spiralMask = smoothstep(-0.2, 0.2, spiralPattern);
    let secAngle = baseAngle - radius * rotSpeed * 0.7;
    let secPattern = sin(arms * 0.5 * secAngle + time * rotSpeed * 0.5 + radius * 8.0);
    let secMask = smoothstep(-0.15, 0.15, secPattern) * 0.4;
    let sparkle = hash12(vec2<f32>(floor(twistedAngle * arms * 3.0), floor(radius * 20.0)) + time * 0.1) * spiralMask * 0.3;
    let hue = (twistedAngle + time * (u.zoom_params.z + mids * 0.5)) / (2.0 * 3.14159);
    let sat = 1.0 - radius * 0.5;
    let val = (spiralMask + secMask + sparkle) * (1.0 - radius * 0.3);
    var rgb = hsv2rgb(fract(hue), sat, val);
    let centerDist = length(uv);
    let glow = exp(-centerDist * 3.0) * sin(time * 5.0) * 0.5 + 0.5;
    rgb += vec3<f32>(1.0, 0.8, 0.5) * glow * (1.0 - radius);
    let distortedUV = clamp(vec2<f32>(spiralMask * cos(twistedAngle) * 0.5 + 0.5, spiralMask * sin(twistedAngle) * 0.5 + 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
    let texColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);
    let alpha = (spiralMask + secMask * 0.5) * (1.0 - radius * 0.3) + glow * 0.2;
    let bloomWeight = val * glow * 2.0;
    let finalAlpha = clamp(alpha + bloomWeight, 0.0, 1.0);
    let finalColor = mix(vec4<f32>(rgb, finalAlpha), texColor, 0.3);
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    let depth = 1.0 - clamp(radius, 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
}
