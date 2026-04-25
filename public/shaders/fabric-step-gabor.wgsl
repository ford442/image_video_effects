// ═══════════════════════════════════════════════════════════════════
//  Fabric Step Gabor
//  Category: advanced-hybrid
//  Features: fabric-simulation, gabor-filter, texture-analysis, mouse-driven
//  Complexity: Very High
//  Chunks From: fabric-step.wgsl, conv-gabor-texture-analyzer.wgsl
//  Created: 2026-04-18
//  By: Agent CB-22 — Artistic & Texture Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Mass-spring cloth simulation deforms the image into flowing fabric
//  folds, then Gabor filter banks detect oriented texture patterns at
//  0, 45, 90, and 135 degrees across the deformed fabric. Strain
//  creates visual texture that the Gabor bank picks up as vivid
//  psychedelic orientation maps. Mouse pulls and tears the fabric.
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

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2D(p: vec2<f32>) -> f32 {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var freq = 1.0;
  var pos = p;
  for (var i = 0; i < 4; i = i + 1) {
    value = value + amplitude * noise2D(pos * freq + vec2<f32>(time * 0.1, time * 0.15));
    freq = freq * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

fn gaborResponse(uv: vec2<f32>, theta: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> f32 {
    var response = 0.0;
    let radius = i32(ceil(sigma * 3.0));
    let maxRadius = min(radius, 4);
    let cosTheta = cos(theta);
    let sinTheta = sin(theta);
    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let x = f32(dx);
            let y = f32(dy);
            let xTheta = x * cosTheta + y * sinTheta;
            let yTheta = -x * sinTheta + y * cosTheta;
            let gaussian = exp(-(xTheta*xTheta + yTheta*yTheta) / (2.0 * sigma * sigma + 0.001));
            let sinusoidal = cos(2.0 * 3.14159265 * freq * xTheta);
            let kernel = gaussian * sinusoidal;
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
            response += luma * kernel;
        }
    }
    return response;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
    let coord = gid.xy;
    if (coord.x >= size.x || coord.y >= size.y) { return; }

    var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
    let time = u.config.x;
    let dt = 0.016;

    let stiffness = mix(0.1, 0.99, u.zoom_params.x);
    let tearThreshold = mix(1.5, 4.0, u.zoom_params.y);
    let gravity = mix(0.0, 0.02, u.zoom_params.z);
    let damping = mix(0.95, 0.999, u.zoom_params.w);

    // Read previous cloth state
    let prevState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var pos = prevState.xy;
    var prevPos = prevState.zw;

    if (length(pos) < 0.001 && length(prevPos) < 0.001) {
        pos = uv;
        prevPos = uv;
    }

    var vel = (pos - prevPos) * damping;
    vel.y = vel.y + gravity * dt;

    // Mouse interaction
    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let toMouse = pos - mouse;
    let mouseDist = length(toMouse);
    let mouseInfluenceRadius = 0.15;
    if (mouseDist < mouseInfluenceRadius && mouseDist > 0.001) {
        var force = (1.0 - mouseDist / mouseInfluenceRadius) * 0.02;
        vel = vel + normalize(toMouse) * force;
    }

    // Wind force
    let windX = fbm(pos * 4.0 + vec2<f32>(time * 0.5, 0.0), time) - 0.5;
    let windY = fbm(pos * 4.0 + vec2<f32>(0.0, time * 0.5), time) - 0.5;
    vel = vel + vec2<f32>(windX, windY) * 0.001;

    let newPrevPos = pos;
    pos = pos + vel;

    // Simple constraint to keep fabric near original UV
    let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
    let restLen = texelSize.x;

    // Relaxed constraint - fabric drapes loosely
    let delta = pos - uv;
    let dist = length(delta);
    if (dist > restLen * 2.0 && dist < tearThreshold * restLen) {
        let correction = (dist - restLen * 2.0) / dist * 0.5 * stiffness;
        pos = pos - delta * correction;
    }

    // Pin top edge
    if (coord.y == 0u) {
        pos = uv;
    }
    pos = clamp(pos, vec2<f32>(0.0), vec2<f32>(1.0));

    // Store state
    textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(pos, newPrevPos));

    // Calculate strain
    let strain = clamp(length(pos - uv) * 50.0, 0.0, 1.0);
    textureStore(dataTextureB, vec2<i32>(coord), vec4<f32>(strain, vel, 1.0));

    // Sample source at deformed position
    let sourceColor = textureSampleLevel(readTexture, u_sampler, pos, 0.0);

    // ═══ GABOR TEXTURE ANALYSIS ON FABRIC ═══
    let pixelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
    let freq = mix(0.05, 0.25, 0.3 + strain * 0.4);
    let sigma = mix(1.5, 3.0, 0.4);
    let responseScale = mix(0.5, 2.0, 0.5 + strain);

    // Strain rotates the Gabor bank
    let strainAngle = atan2(vel.y, vel.x) * strain * 2.0;
    let rotationOffset = strainAngle + time * 0.05;

    let r0 = gaborResponse(pos, 0.0 + rotationOffset, freq, sigma, pixelSize) * responseScale;
    let r45 = gaborResponse(pos, 0.785398 + rotationOffset, freq, sigma, pixelSize) * responseScale;
    let r90 = gaborResponse(pos, 1.570796 + rotationOffset, freq, sigma, pixelSize) * responseScale;
    let r135 = gaborResponse(pos, 2.356194 + rotationOffset, freq, sigma, pixelSize) * responseScale;

    // Psychedelic palette mapping
    let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));
    let pal135 = palette(r135 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33));

    var gaborColor = vec3<f32>(0.0);
    gaborColor += pal0 * abs(r0);
    gaborColor += pal45 * abs(r45);
    gaborColor += pal90 * abs(r90);
    gaborColor += pal135 * abs(r135);
    let totalResponse = abs(r0) + abs(r45) + abs(r90) + abs(r135) + 0.001;
    gaborColor = gaborColor / totalResponse;
    gaborColor = gaborColor * 1.3;

    // Blend Gabor analysis with source color based on strain
    let fabricColor = mix(sourceColor.rgb, gaborColor, strain * 0.7);

    // Strain color visualization
    let strainColor = mix(
        vec3<f32>(0.2, 0.4, 0.8),
        vec3<f32>(1.0, 0.3, 0.1),
        strain
    );
    let finalColor = mix(fabricColor, strainColor, strain * 0.2);

    // Fabric alpha based on strain
    let fabricAlpha = mix(0.9, 0.7, strain * 0.5);

    textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, fabricAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, pos, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
