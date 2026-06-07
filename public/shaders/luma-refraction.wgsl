// ═══════════════════════════════════════════════════════════════════
//  Luma Refraction
//  Category: image
//  Features: wave-propagation, mouse-interactive, audio-reactive, upgraded-rgba,
//            chromatic-refraction, temporal-wave-memory, audio-wave-amplitude
//  Complexity: Medium
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    let waveSpeed = u.zoom_params.x;
    let mouseForce = u.zoom_params.y;
    let damping = u.zoom_params.z;
    let refractionAmt = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let state = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    var h = state.r;
    var v = state.g;

    let texel = 1.0 / resolution;
    let n = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let s = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let e = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let w_val = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;

    let laplacian = (n + s + e + w_val) / 4.0 - h;

    let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

    // Audio-driven wave amplitude
    let localSpeed = waveSpeed * (0.2 + 1.0 * luma) * (1.0 + bass * 0.3);

    v = v + laplacian * localSpeed;
    v = v * damping;

    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    if (mouseDown > 0.5 && dist < 0.05) {
        v = v + (1.0 - dist / 0.05) * mouseForce * 0.5;
    }

    h = h + v;
    h = clamp(h, -10.0, 10.0);

    textureStore(dataTextureA, global_id.xy, vec4<f32>(h, v, 0.0, 1.0));

    let gradX = (e - w_val) * 0.5;
    let gradY = (s - n) * 0.5;

    let normal = vec2<f32>(gradX, gradY);

    // Chromatic refraction: R/G/B see different index of refraction
    let rOffset = normal * refractionAmt * 0.5 * (1.0 + treble * 0.2);
    let gOffset = normal * refractionAmt * 0.5;
    let bOffset = normal * refractionAmt * 0.5 * (1.0 - bass * 0.2);

    let rUV = clamp(uv - rOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv - gOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - bOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    var finalColor = vec3<f32>(0.0);
    finalColor.r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    finalColor.g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    finalColor.b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Temporal wave memory: previous refraction tint bleeds in
    let prevRefraction = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    finalColor = mix(finalColor, prevRefraction * 0.9, 0.05 + mids * 0.02);

    let alpha = clamp(0.8 + abs(h) * 0.05, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
