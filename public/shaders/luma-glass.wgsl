// ═══════════════════════════════════════════════════════════════════
//  Luma Glass
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-30
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let texel = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let refractDepth = u.zoom_params.x * (1.0 + bass * 0.2);
    let smoothness = u.zoom_params.y;
    let specularShine = u.zoom_params.z * (1.0 + treble * 0.25);
    let lightDistance = u.zoom_params.w;

    let uvT = clamp(uv + vec2<f32>(0.0, -texel.y), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let uvB = clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let uvL = clamp(uv + vec2<f32>(-texel.x, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let uvR = clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let sampleT = textureSampleLevel(readTexture, u_sampler, uvT, 0.0);
    let sampleB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
    let sampleL = textureSampleLevel(readTexture, u_sampler, uvL, 0.0);
    let sampleR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);

    let lum = vec3<f32>(0.299, 0.587, 0.114);
    let lumaT = dot(sampleT.rgb, lum);
    let lumaB = dot(sampleB.rgb, lum);
    let lumaL = dot(sampleL.rgb, lum);
    let lumaR = dot(sampleR.rgb, lum);

    let dX = lumaR - lumaL;
    let dY = lumaB - lumaT;
    let surfaceNormal = normalize(vec3<f32>(-dX * mix(50.0, 10.0, smoothness), -dY * mix(50.0, 10.0, smoothness), 1.0));
    let refractedUV = clamp(uv + surfaceNormal.xy * refractDepth * 0.08, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let baseColor = textureSampleLevel(readTexture, u_sampler, refractedUV, 0.0);

    let pixelPos = vec3<f32>(uv.x * aspect, uv.y, 0.0);
    let lightPos = vec3<f32>(mousePos.x * aspect, mousePos.y, 0.25 + lightDistance * 1.2);
    let lightDir = normalize(lightPos - pixelPos);
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let halfDir = normalize(lightDir + viewDir);
    let specular = pow(max(dot(surfaceNormal, halfDir), 0.0), mix(12.0, 96.0, specularShine));
    let fresnel = pow(1.0 - max(dot(surfaceNormal, viewDir), 0.0), 3.0);

    let lumaBase = dot(baseColor.rgb, lum);
    let tint = mix(
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(lumaBase, lumaBase * (0.82 + mids * 0.08), 1.0 - lumaBase * 0.3 + treble * 0.1),
        0.3 + specularShine * 0.5
    );
    let shimmer = vec3<f32>(0.2, 0.5 + treble * 0.1, 0.8) * specular * (0.5 + bass * 0.5);
    let finalColor = baseColor.rgb * tint + shimmer + fresnel * 0.15;
    let alpha = clamp(baseColor.a * 0.45 + fresnel * 0.2 + specular * 0.25 + bass * 0.04, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, refractedUV, 0.0).r + fresnel * 0.04, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
