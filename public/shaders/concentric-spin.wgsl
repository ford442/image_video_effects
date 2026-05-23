// ═══════════════════════════════════════════════════════════════════
//  Concentric Spin
//  Category: image
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let aspect = u.config.z / u.config.w;

    let ringDensity = mix(5.0, 50.0, u.zoom_params.x);
    let speedMult = mix(0.0, 5.0, u.zoom_params.y);
    let smoothness = u.zoom_params.z * 0.1;
    let gapOpacity = u.zoom_params.w;

    let audioPulse = 1.0 + bass * 0.3 + mids * 0.15;
    let center = u.zoom_config.yz * vec2<f32>(aspect, 1.0);
    let p = uv * vec2<f32>(aspect, 1.0) - center;
    let r = length(p);
    let a = atan2(p.y, p.x);

    let ringVal = r * ringDensity;
    let ringIdx = floor(ringVal);
    let direction = (ringIdx % 2.0) * 2.0 - 1.0;
    let rotation = u.config.x * speedMult * direction * audioPulse;

    let newA = a + rotation;
    let newP = vec2<f32>(cos(newA), sin(newA)) * r;
    let finalUV = clamp((newP + center) / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let ringPhase = fract(ringVal);
    let edgeDist = min(ringPhase, 1.0 - ringPhase);
    let gapMask = smoothstep(0.0, smoothness + 0.001, edgeDist);
    let alphaBoost = treble * 0.2 * gapMask;
    let finalAlpha = clamp(color.a * mix(1.0, gapMask, gapOpacity) + alphaBoost, 0.0, 1.0);
    let finalColor = vec4<f32>(color.rgb, finalAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
