// ═══════════════════════════════════════════════════════════════════
//  edge-glow-mouse-em
//  Category: advanced-hybrid
//  Features: edge-detection, electromagnetic-field, mouse-driven, chromatic
//  Complexity: High
//  Chunks From: edge-glow-mouse.wgsl, mouse-electromagnetic-aurora.wgsl
//  Created: 2026-04-18
//  By: Agent CB-19 — Lighting & Energy Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Edge glow enhanced with flowing electromagnetic field lines.
//  Image edges emit light that distorts along electric field vectors
//  while magnetic fields rotate hue, creating charged-particle visuals.
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

// ═══ CHUNK: hash12 (from mouse-electromagnetic-aurora.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: hueShift (from mouse-electromagnetic-aurora.wgsl) ═══
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn electricField(pos: vec2<f32>, chargePos: vec2<f32>, charge: f32) -> vec2<f32> {
    let r = pos - chargePos;
    let dist = max(length(r), 0.001);
    return charge * normalize(r) / (dist * dist);
}

fn magneticField(pos: vec2<f32>, chargePos: vec2<f32>, velocity: vec2<f32>, charge: f32) -> f32 {
    let r = pos - chargePos;
    let dist = max(length(r), 0.001);
    return charge * (velocity.x * r.y - velocity.y * r.x) / (dist * dist * dist);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;

    // Parameters
    let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
    let glowRadius = u.zoom_params.y * 0.3 + 0.05;
    let glowIntensity = u.zoom_params.z * 3.0;
    let colorCycle = u.zoom_params.w * 3.14159;
    let chargeStrength = u.zoom_params.x * 2.0;
    let fieldVis = u.zoom_params.y;
    let distortionStrength = u.zoom_params.z * 0.15;

    let mousePos = u.zoom_config.yz;
    let mouseDist = distance(uv, mousePos);

    // Sample for edge detection
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let cR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let cL = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let cU = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).rgb;
    let cD = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).rgb;
    let colorEdge = length(cR - cL) + length(cU - cD);

    // EM field calculations
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
    let mouseVel = (mousePos - prevMouse) * 60.0;

    if (gid.x == 0u && gid.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
    }

    let eField = electricField(uv, mousePos, chargeStrength);
    let bField = magneticField(uv, mousePos, mouseVel, chargeStrength);
    let fieldMag = length(eField);
    let fieldDir = select(vec2<f32>(0.0), normalize(eField), fieldMag > 0.0001);

    // Streamline texture
    let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
    let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
    let streamline = smoothstep(0.4, 0.6, streamNoise) * fieldVis * smoothstep(0.0, 0.5, fieldMag);

    // UV displacement along electric field
    let displacedUV = uv + fieldDir * distortionStrength * smoothstep(0.0, 2.0, fieldMag);
    let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Edge glow with EM influence
    let glowFalloff = 1.0 - smoothstep(0.0, glowRadius, mouseDist);
    let edgeGlowColor = vec3<f32>(
        0.5 + 0.5 * sin(time * 2.0 + colorCycle),
        0.5 + 0.5 * sin(time * 2.0 + 2.09 + colorCycle),
        0.5 + 0.5 * sin(time * 2.0 + 4.18 + colorCycle)
    ) * colorEdge * glowIntensity * glowFalloff;

    // Hue rotation from magnetic field
    let hueRot = bField * colorCycle * 0.5;
    let color = hueShift(baseColor, hueRot);

    // Field line overlay
    let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
    let finalColor = mix(color + edgeGlowColor, fieldColor, streamline * 0.4);

    // Core glow near mouse
    let aspect = res.x / res.y;
    let mouseDistAspect = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
    let coreGlow = exp(-mouseDistAspect * mouseDistAspect * 400.0) * chargeStrength;
    let outColor = finalColor + vec3<f32>(0.6, 0.9, 1.0) * coreGlow * fieldVis;

    let alpha = clamp(length(edgeGlowColor) * 0.5 + streamline * 0.3, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(outColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
