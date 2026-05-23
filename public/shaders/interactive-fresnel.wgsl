// ═══════════════════════════════════════════════════════════════════
//  Interactive Fresnel
//  Category: visual-effects
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
    let aspectVec = vec2<f32>(aspect, 1.0);

    let ringDensity = mix(1.0, 50.0, u.zoom_params.x);
    let magStrength = u.zoom_params.y * 2.0;
    let aberration = u.zoom_params.z * 0.05;
    let depthInfluence = u.zoom_params.w * 2.0;

    let audioPulse = 1.0 + bass * 0.5 + treble * 0.25;
    let mouse = u.zoom_config.yz;
    let center = mouse;
    let dist = distance((uv - center) * aspectVec, vec2<f32>(0.0));

    let ringPhase = fract(dist * ringDensity);
    let safeDist = max(dist, 0.0001);
    let dir = ((uv - center) * aspectVec) / safeDist;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let displaceAmount = ringPhase * magStrength * 0.05 * (1.0 + (1.0 - depth) * depthInfluence) * audioPulse;

    let baseUV = clamp(uv - (dir * displaceAmount) / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0));
    let rUV = clamp(baseUV - (dir * aberration) / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = baseUV;
    let bUV = clamp(baseUV + (dir * aberration) / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0));

    let cR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
    let cG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let cB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);

    let aberrationBlend = clamp(aberration * 20.0 * cG.a, 0.0, 1.0);
    let aberratedRGB = vec3<f32>(cR.r, cG.g, cB.b);
    let finalRGB = mix(cG.rgb, aberratedRGB, aberrationBlend);

    let edgeHighlight = smoothstep(0.0, 0.05, ringPhase) * smoothstep(0.15, 0.05, ringPhase);
    let finalAlpha = clamp(cG.a + edgeHighlight * 0.3 + aberrationBlend * 0.1 + mids * 0.1, 0.0, 1.0);
    let finalColor = vec4<f32>(finalRGB, finalAlpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
