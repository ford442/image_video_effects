// ═══════════════════════════════════════════════════════════════════
//  Static Reveal
//  Category: artistic
//  Features: mouse-driven, audio-reactive, audio-driven, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-23
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let aspect = u.config.z / u.config.w;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let decaySpeed = u.zoom_params.x * 0.05 + 0.001;
    let brushRadius = u.zoom_params.y * 0.3 + 0.05;
    let noiseIntensity = u.zoom_params.z;
    let noiseScale = 50.0 + u.zoom_params.w * 200.0;

    let mouse = u.zoom_config.yz;
    let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

    let reactiveRadius = brushRadius * (1.0 + bass * 0.2);
    let prevMask = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    let brush = smoothstep(reactiveRadius, reactiveRadius * 0.5, dist);
    let mask = clamp(max(prevMask - decaySpeed, brush), 0.0, 1.0);

    let staticFlicker = 1.0 + mids * 0.5;
    let noiseVal = hash12(uv * noiseScale + vec2<f32>(u.config.x * 10.0)) * noiseIntensity * staticFlicker;
    let noiseAlpha = 1.0 - mask;
    let noiseColor = vec4<f32>(vec3<f32>(noiseVal), noiseAlpha);

    let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let finalColor = mix(noiseColor, videoColor, mask);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
