// ═══════════════════════════════════════════════════════════════════
//  Refraction Tunnel
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
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let safeMin = vec2<f32>(0.001, 0.001);
    let safeMax = vec2<f32>(0.999, 0.999);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let tunnelDepth = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + bass * 0.35);
    let twistAmount = (u.zoom_params.y - 0.5) * (10.0 + mids * 3.0);
    let aberration = u.zoom_params.z * 0.1 * (1.0 + treble * 0.35);
    let travelSpeed = mix(-1.0, 1.0, u.zoom_params.w) * (1.0 + bass * 0.25);

    let dir = uv - mousePos;
    let dirCorrected = vec2<f32>(dir.x * aspect, dir.y);
    let dist = length(dirCorrected);
    let safeDist = max(dist, 0.001);
    let twistEnvelope = 1.0 - smoothstep(0.0, 1.0, safeDist);
    let angle = atan2(dirCorrected.y, dirCorrected.x);
    let distortPower = max(0.2, 1.0 - tunnelDepth * 0.85);
    let newDist = pow(safeDist, distortPower);
    let newAngle = angle + twistAmount * twistEnvelope + time * travelSpeed * 0.7 * twistEnvelope;
    let offsetDir = vec2<f32>(cos(newAngle), sin(newAngle));
    let relativePos = vec2<f32>(offsetDir.x * newDist / aspect, offsetDir.y * newDist);
    let centerBlend = 1.0 - smoothstep(0.0, 0.02, dist);

    let centerUVRaw = mousePos + relativePos;
    let centerUV = clamp(mix(centerUVRaw, mousePos, centerBlend), safeMin, safeMax);
    let aberrVec = clamp(relativePos * aberration, vec2<f32>(-0.08, -0.08), vec2<f32>(0.08, 0.08));
    let rUV = clamp(centerUV - aberrVec, safeMin, safeMax);
    let gUV = centerUV;
    let bUV = clamp(centerUV + aberrVec, safeMin, safeMax);

    let centerColor = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let finalColor = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        centerColor.g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    );

    let vignette = 1.0 - smoothstep(0.15, 1.4, safeDist * (1.0 + tunnelDepth));
    let tunnelGlow = vec3<f32>(0.12, 0.18 + treble * 0.12, 0.35 + mids * 0.15) * twistEnvelope * aberration * 6.0;
    let shadedColor = finalColor * vignette + tunnelGlow * twistEnvelope;
    let alpha = clamp(centerColor.a * 0.4 + vignette * 0.22 + twistEnvelope * 0.26 + bass * 0.06, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + twistEnvelope * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(shadedColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
