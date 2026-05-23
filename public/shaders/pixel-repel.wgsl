// ═══════════════════════════════════════════════════════════════════
//  Pixel Repeller
//  Category: interactive-mouse
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
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let mousePos = u.zoom_config.yz;

    let radius = max(u.zoom_params.x, 0.05);
    let strength = u.zoom_params.y;
    let aberration = u.zoom_params.z;
    let smoothing = u.zoom_params.w;

    let aspect = u.config.z / u.config.w;
    let dVec = uv - mousePos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
    let t = smoothstep(radius, radius * (1.0 - smoothing * 0.5), dist);
    let dVecLen = length(dVec);
    let dir = select(vec2<f32>(0.0), dVec / max(dVecLen, 0.0001), dVecLen > 0.0001);
    let displacement = dir * t * strength * 0.3 * (1.0 + bass * 0.5);
    let hasMouse = mousePos.x >= 0.0 && mousePos.y >= 0.0;
    let finalDisplacement = select(vec2<f32>(0.0), displacement, hasMouse);

    let rUV = clamp(uv - finalDisplacement * (1.0 + aberration), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv - finalDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - finalDisplacement * (1.0 - aberration), vec2<f32>(0.0), vec2<f32>(1.0));

    let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let cR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
    let cG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let cB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);

    let w = aberration * c0.a;
    let aberratedRGB = vec3<f32>(
        mix(c0.r, cR.r, w),
        mix(c0.g, cG.g, w),
        mix(c0.b, cB.b, w)
    );
    let effectStrength = clamp(length(finalDisplacement) * 10.0 + aberration * c0.a, 0.0, 1.0);
    let audioBoost = mids * 0.1;
    let finalAlpha = clamp(c0.a + effectStrength * 0.2 + audioBoost, 0.0, 1.0);
    let finalColor = vec4<f32>(aberratedRGB, finalAlpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
