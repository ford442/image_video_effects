// ═══════════════════════════════════════════════════════════════════
//  Digital Crease
//  Category: geometric
//  Features: mouse-driven, audio-reactive, temporal-paper-fold, depth-curve-distortion, chromatic-folding, upgraded-rgba
//  Complexity: High
//  Chunks From: digital-crease, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthCurve = mix(0.5, 1.5, depth);

    let foldCount = mix(2.0, 10.0, u.zoom_params.x);
    let foldDepth = u.zoom_params.y * depthCurve * bass_env(bass, mids);
    let foldSoftness = u.zoom_params.z;
    let chromaticOffset = u.zoom_params.w * 0.01;

    let center = vec2<f32>(0.5);
    let dToCenter = uv - center;
    let angle = atan2(dToCenter.y, dToCenter.x);
    let dist = length(dToCenter);

    // Fold based on angle, modulated by bass
    let foldAngle = angle * foldCount * (1.0 + bass * 0.1);
    let fold = sin(foldAngle);
    let signFold = select(-1.0, 1.0, fold > 0.0);
    let curveOffset = signFold * foldDepth * (1.0 - dist);
    let softness = foldSoftness * (1.0 - dist);
    let mask = smoothstep(-softness, 0.0, curveOffset) * smoothstep(softness, 0.0, curveOffset);

    // Temporal fold history for paper-persistence
    let prevFold = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    let persistentMask = mix(mask, prevFold * 0.9, 0.3);

    // Chromatic folding: R and B sample from different crease depths
    let rUV = clamp(uv + vec2<f32>(curveOffset * chromaticOffset * (1.0 + bass * 0.2), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - vec2<f32>(curveOffset * chromaticOffset * (1.0 + bass * 0.2), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + vec2<f32>(0.0, curveOffset * chromaticOffset * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Shadow / highlight on crease edge
    let edge = smoothstep(0.0, 0.1, abs(curveOffset));
    let shadow = mix(1.0, 0.6, edge * signFold * 0.5);
    let highlight = mix(1.0, 1.3, edge * -signFold * 0.5);

    let rgb = vec3<f32>(r, g, b) * shadow * highlight;
    let alpha = clamp(persistentMask + 0.3 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
