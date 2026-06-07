// ═══════════════════════════════════════════════════════════════════
//  Elastic Chromatic — May 2026 Batch D Upgrade
//  Category: distortion
//  Features: mouse-driven, depth-aware, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: elastic-chromatic (original)
//  Created: 2026-04-25
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const MAX_LAG: f32 = 0.995;

fn mouse_influence(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32, strength: f32) -> f32 {
    let d = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    return smoothstep(0.5, 0.0, d) * strength;
}

fn ema(current: f32, history: f32, lag: f32) -> f32 {
    return mix(current, history, lag);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Audio: bass drives elastic spring constant, mids drives Lissajous speed, treble adds sparkle
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters: x=Elasticity, y=Chromatic Scale, z=Lissajous Ratio, w=Damping
    let elasticity = mix(0.1, 1.0, u.zoom_params.x) * (1.0 + bass * 0.5);
    let chromaticScale = mix(0.0, 1.0, u.zoom_params.y);
    let lissajousRatio = mix(0.5, 2.0, u.zoom_params.z);
    let damping = mix(0.1, 0.9, u.zoom_params.w);

    // Lissajous-based secondary chromatic source oscillating around mouse
    // mids modulate oscillation frequency for richer audio coupling
    let lissFreqX = 1.0 + mids * 0.3;
    let lissFreqY = lissajousRatio + mids * 0.2;
    let lissAmp = chromaticScale * 0.08;
    let lissPos = mouse + vec2<f32>(
        lissAmp * sin(time * lissFreqX * 2.0 * (1.0 + elasticity)),
        lissAmp * sin(time * lissFreqY * 2.0 * (1.0 + elasticity))
    );

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let curr = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Mouse proximity influence
    let influence = mouse_influence(uv, mouse, aspect, elasticity);

    // Lissajous proximity influence
    let distLiss = distance(uv, lissPos);
    let lissInfluence = smoothstep(0.4, 0.0, distLiss) * chromaticScale;

    // Depth-aware modulation
    let depthMod = (1.0 - depth) * 0.35;

    // Effective lag per channel with damping
    let lagR = clamp(elasticity + influence + depthMod + lissInfluence, 0.0, MAX_LAG) * damping;
    let lagB = clamp(elasticity * 0.8 + influence * 0.5 + depthMod * 0.5 + lissInfluence * 0.7, 0.0, MAX_LAG) * damping;
    let lagG = clamp(elasticity * 0.6 + influence * 0.3, 0.0, MAX_LAG) * damping;

    // Chromatic exponential moving average
    let outR = ema(curr.r, history.r, lagR);
    let outG = ema(curr.g, history.g, lagG);
    let outB = ema(curr.b, history.b, lagB);

    // Effect-mask alpha: stronger aberration = higher alpha at edges; treble adds sparkle
    let aberration = abs(lagR - lagB) + lissInfluence;
    let edgeBoost = smoothstep(0.0, 0.3, aberration + treble * 0.1);
    let alpha = clamp(mix(curr.a * 0.75, curr.a, edgeBoost) + treble * 0.05, 0.0, 1.0);

    let finalColor = vec4<f32>(outR, outG, outB, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
