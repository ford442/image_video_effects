// ═══════════════════════════════════════════════════════════════════
//  Magnetic Field
//  Category: interactive-mouse
//  Features: mouse-driven, field-lines, particle-trails, depth-aware
//  Complexity: High
//  Created: 2026-05-31
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

const PI: f32 = 3.141592653589793;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn fieldStrength(uv: vec2<f32>, pole: vec2<f32>, charge: f32) -> vec2<f32> {
    let delta = uv - pole;
    let distSq = dot(delta, delta);
    let dist = sqrt(distSq);
    if (dist < 0.001) { return vec2<f32>(0.0); }
    // Inverse square law with clamping
    let strength = charge / (distSq + 0.001);
    return vec2<f32>(-delta.y, delta.x) * strength / dist;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let lineDensity = u.zoom_params.x * 24.0 + 8.0;
    let fieldIntensity = u.zoom_params.y * 0.5 + 0.1;
    let glow = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    var mouse = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthInfluence = 1.0 - depth * 0.5;

    // Pole 1: Mouse (positive)
    let pole1 = mouse;
    // Pole 2: Opposite corner (negative)
    let pole2 = vec2<f32>(1.0 - mouse.x, 1.0 - mouse.y);
    // Pole 3: Orbiting
    let pole3 = vec2<f32>(0.5 + cos(time * 0.5) * 0.3, 0.5 + sin(time * 0.7) * 0.3);

    let charge1 = 1.0 * fieldIntensity;
    let charge2 = -0.7 * fieldIntensity;
    let charge3 = 0.5 * fieldIntensity;

    // Superpose field vectors
    var B = vec2<f32>(0.0);
    B += fieldStrength(uv, pole1, charge1);
    B += fieldStrength(uv, pole2, charge2);
    B += fieldStrength(uv, pole3, charge3);

    let fieldMag = length(B);
    let fieldDir = atan2(B.y, B.x);

    // Create field line pattern
    let uvAspect = uv * vec2<f32>(aspect, 1.0);
    let streamVal = sin(fieldDir * lineDensity + fieldMag * 20.0 + time * 0.5);
    let linePattern = smoothstep(0.85, 0.95, abs(streamVal));

    // Secondary finer lines
    let fineLines = sin(fieldDir * lineDensity * 2.5 + fieldMag * 40.0 - time * 0.3);
    let finePattern = smoothstep(0.9, 0.98, abs(fineLines)) * 0.4;

    // Particle dots flowing along field
    let flowPhase = fract(fieldMag * 5.0 + time * 0.4);
    let flowDots = smoothstep(0.02, 0.0, abs(flowPhase - 0.5)) * 0.6;

    let totalPattern = clamp(linePattern + finePattern + flowDots, 0.0, 1.0);

    // Color based on field direction
    let hue = fract((fieldDir / (2.0 * PI)) + colorShift + time * 0.02);
    let fieldColor = vec3<f32>(
        0.5 + 0.5 * cos(hue * 6.283 + 0.0),
        0.5 + 0.5 * cos(hue * 6.283 + 2.094),
        0.5 + 0.5 * cos(hue * 6.283 + 4.189)
    );

    // Sample background
    let bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Composite field lines over background
    let glowAmount = glow * 1.5;
    var finalColor = bgColor;
    finalColor = mix(finalColor, fieldColor * glowAmount, totalPattern * 0.7 * depthInfluence);

    // Add pole glows
    let pole1Dist = length((uv - pole1) * vec2<f32>(aspect, 1.0));
    let pole2Dist = length((uv - pole2) * vec2<f32>(aspect, 1.0));
    let poleGlow1 = exp(-pole1Dist * pole1Dist * 30.0) * glowAmount;
    let poleGlow2 = exp(-pole2Dist * pole2Dist * 30.0) * glowAmount * 0.5;

    finalColor += vec3<f32>(1.0, 0.8, 0.4) * poleGlow1;
    finalColor += vec3<f32>(0.4, 0.6, 1.0) * poleGlow2;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
