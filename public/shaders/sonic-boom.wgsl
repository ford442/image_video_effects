// ═══════════════════════════════════════════════════════════════════
//  Sonic Boom
//  Category: distortion
//  Features: multi-shock, persistent-tail, gaussian-ring, audio-reactive, branchless, hex-bokeh, early-exit
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

const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>( 0.0,  0.0),
    vec2<f32>( 1.0,  0.0), vec2<f32>( 0.5,  0.866),
    vec2<f32>(-0.5,  0.866), vec2<f32>(-1.0,  0.0),
    vec2<f32>(-0.5, -0.866), vec2<f32>( 0.5, -0.866),
);

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dim = textureDimensions(readTexture);
    let coord = vec2<i32>(gid.xy);
    if (coord.x >= i32(dim.x) || coord.y >= i32(dim.y)) { return; }

    let uv = vec2<f32>(coord) / vec2<f32>(f32(dim.x), f32(dim.y));
    let aspect = vec2<f32>(f32(dim.x) / f32(dim.y), 1.0);
    let bass = plasmaBuffer[0].x;

    let radius   = u.zoom_params.x;
    let width    = u.zoom_params.y;
    let strength = u.zoom_params.z * (1.0 + bass * 0.5);
    let split    = u.zoom_params.w;

    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let to_pixel = (uv - mouse_pos) * aspect;
    let dist = length(to_pixel);
    let dir = to_pixel / max(dist, 1e-4);

    // Coarse tail sample for cheap early-exit test
    let prevTail = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Three golden-ratio-spaced gaussian shock rings
    let widthHalf = max(width * 0.5, 1e-4);
    let invWH = 1.0 / widthHalf;
    let d0 = (dist - radius) * invWH;
    let d1 = (dist - radius / PHI) * invWH;
    let d2 = (dist - radius / (PHI * PHI)) * invWH;
    let ring0 = exp(-d0 * d0 * 4.0);
    let ring1 = exp(-d1 * d1 * 6.0) * 0.55;
    let ring2 = exp(-d2 * d2 * 8.0) * 0.30;
    let ringSum = ring0 + ring1 + ring2;
    let ringFinal = max(ringSum, prevTail * 0.85);

    // Early exit: skip expensive samples where effect is negligible
    if (ringFinal < 1e-3 && strength < 1e-3) {
        let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        textureStore(writeTexture, coord, src);
        textureStore(dataTextureA, coord, vec4<f32>(0.0, 0.0, dist, 1.0));
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }

    // Hex-bokeh refined tail for active pixels (perceptually smoother echo)
    let texel = 1.0 / vec2<f32>(dim);
    var hTail: f32 = 0.0;
    for (var i: i32 = 0; i < 7; i = i + 1) {
        hTail = hTail + textureSampleLevel(dataTextureC, non_filtering_sampler, uv + HEX_TAPS[i] * texel * 2.0, 0.0).r;
    }
    let ringBlur = max(ringSum, (hTail / 7.0) * 0.85);

    // Doppler-style spectral shift: outer redshift, inner blueshift
    let distortion = dir * ringBlur * strength * 0.1;
    let doppler = (ring0 - ring2) * split * 8.0;
    let uv_r = uv - distortion * (1.0 + split * 10.0 + doppler);
    let uv_g = uv - distortion;
    let uv_b = uv - distortion * (1.0 - split * 10.0 - doppler);

    // Minimize samples: center tap provides green; displaced taps provide R/B
    let c = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    // Semantic alpha = effect intensity / bloom weight
    let alpha = clamp(ringBlur * 0.7 + abs(doppler) * 0.5, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(r, c.g, b, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(ringBlur, ringSum, dist, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
