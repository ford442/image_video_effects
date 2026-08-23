// ═══════════════════════════════════════════════════════════════════
//  Neon Flashlight
//  Category: lighting-effects
//  Features: mouse-driven, neon, edge-light, audio-pulse, depth-fog, edge-reveal
//  Complexity: Medium
//  Updated: 2026-05-31 — Grok (audio-reactive pulse + depth fog)
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

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 2: Edge-Preserve Alpha
fn edgePreserveAlpha(uv: vec2<f32>, pixelSize: vec2<f32>, edgeThreshold: f32) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthEdge);
    return mix(0.2, 1.0, edgeMask);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    // ═══ AUDIO REACTIVITY ═══
    let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
    let beamRadius = u.zoom_params.y * 0.3;
    let intensity = u.zoom_params.z * 3.0;
    let colorShift = u.zoom_params.w;
    
    let mousePos = u.zoom_config.yz;
    let mouseDist = distance(uv, mousePos);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Flashlight beam falloff
    let beamFalloff = 1.0 - smoothstep(beamRadius * (0.75 - held * 0.2), beamRadius, mouseDist);
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length(uv - event.xy) - age * 0.4) * 65.0);
    }
    
    // Edge detection
    let l = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let edge = length(r - l);
    
    // Neon color
    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(colorShift * 6.28 + time),
        0.5 + 0.5 * sin(colorShift * 6.28 + time + 2.09),
        0.5 + 0.5 * sin(colorShift * 6.28 + time + 4.18)
    );
    
    // Grok audio upgrade: Bass pulses the light, treble shifts the neon hue
    let pulse = 1.0 + bass * 0.8 + treble * 0.4;
    let hueShift = treble * 1.5;
    let audioNeon = vec3<f32>(
        0.5 + 0.5 * sin(colorShift * 6.28 + time + hueShift),
        0.5 + 0.5 * sin(colorShift * 6.28 + time + 2.09 + hueShift),
        0.5 + 0.5 * sin(colorShift * 6.28 + time + 4.18)
    );
    
    let coneRibs = pow(0.5 + 0.5 * sin(atan2(uv.y - mousePos.y, uv.x - mousePos.x) * 18.0 + time * 2.0), 5.0) * beamFalloff;
    let sweep = exp(-abs(fract(mouseDist * 3.0 - time * (0.12 + mids * 0.2)) - 0.5) * 16.0);
    let emission = audioNeon * (edge * beamFalloff * intensity * pulse + coneRibs * 0.22 + sweep * 0.12 + clickFront * 0.35);
    let alpha = edgePreserveAlpha(uv, pixelSize, edgeThreshold) * beamFalloff * (0.8 + bass * 0.4);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(emission, alpha));
}
