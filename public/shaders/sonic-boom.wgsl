// ═══════════════════════════════════════════════════════════════════
//  Sonic Boom
//  Category: distortion
//  Features: multi-shock, persistent-tail, gaussian-ring, audio-reactive, branchless
//  Complexity: Medium
//  Phase B / Optimizer
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=Width, z=Strength, w=Split
  ripples: array<vec4<f32>, 50>,
};

const PHI: f32 = 1.61803398874989484820;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dim = textureDimensions(readTexture);
    let coord = vec2<i32>(gid.xy);
    if (coord.x >= i32(dim.x) || coord.y >= i32(dim.y)) { return; }

    let uv = vec2<f32>(coord) / vec2<f32>(f32(dim.x), f32(dim.y));
    let aspect = vec2<f32>(f32(dim.x) / f32(dim.y), 1.0);
    let bass = plasmaBuffer[0].x;
    let time = u.config.x;

    let radius   = u.zoom_params.x;
    let width    = u.zoom_params.y;
    let strength = u.zoom_params.z * (1.0 + bass * 0.5);
    let split    = u.zoom_params.w;

    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let to_pixel = (uv - mouse_pos) * aspect;
    let dist = length(to_pixel);
    // Branchless normalize via guarded reciprocal
    let dir = to_pixel / max(dist, 1e-4);

    // 3 concentric shock rings (front + 2 reflected) — golden-ratio spaced radii
    let widthHalf = max(width * 0.5, 1e-4);
    let r0 = radius;
    let r1 = radius / PHI;
    let r2 = radius / (PHI * PHI);
    let x0 = (dist - r0) / widthHalf;
    let x1 = (dist - r1) / widthHalf;
    let x2 = (dist - r2) / widthHalf;
    let ring0 = exp(-x0 * x0 * 4.0);
    let ring1 = exp(-x1 * x1 * 6.0) * 0.55;
    let ring2 = exp(-x2 * x2 * 8.0) * 0.30;
    let ringSum = ring0 + ring1 + ring2;

    // Persistent shock tail from last frame (decays branchlessly)
    let prevTail = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    let ringFinal = max(ringSum, prevTail * 0.85);

    let distortion = dir * ringFinal * strength * 0.1;
    // Doppler-style spectral shift: outer ring redshifts, inner blueshifts
    let doppler = (ring0 - ring2) * split * 8.0;
    let uv_r = uv - distortion * (1.0 + split * 10.0 + doppler);
    let uv_g = uv - distortion;
    let uv_b = uv - distortion * (1.0 - split * 10.0 - doppler);

    let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    let luminance = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luminance + 0.2 + ringFinal * 0.4 + abs(doppler) * 0.3, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(r, g, b, alpha));
    // Persist ring tail for next-frame echo
    textureStore(dataTextureA, coord, vec4<f32>(ringFinal, ringSum, dist, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
