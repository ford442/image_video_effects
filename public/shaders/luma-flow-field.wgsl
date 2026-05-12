// ═══════════════════════════════════════════════════════════════════
//  Luma Flow Field
//  Category: simulation
//  Features: gradient-flow, palette-mapped, sobel, bloom-alpha, audio-reactive
//  Complexity: Medium
//  Phase B / Visualist
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
  zoom_params: vec4<f32>,  // x=FlowStrength, y=Iridescence, z=Decay, w=PaletteShift
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

fn getLuma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(textureDimensions(readTexture));
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }

    var uv = vec2<f32>(coord) / resolution;
    let bass = plasmaBuffer[0].x;

    let flowStrength = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + bass * 0.4);
    let iridescence  = clamp(u.zoom_params.y, 0.0, 1.0);
    let decay        = clamp(0.95 + u.zoom_params.z * 0.04, 0.5, 1.0);
    let paletteShift = u.zoom_params.w;

    // Sobel gradient on luma — much better directional info than 2-tap forward diff
    let e = 1.0 / resolution;
    let l00 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-e.x, -e.y), 0.0).rgb);
    let l10 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0, -e.y), 0.0).rgb);
    let l20 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( e.x, -e.y), 0.0).rgb);
    let l01 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-e.x,  0.0), 0.0).rgb);
    let l11 = getLuma(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb);
    let l21 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( e.x,  0.0), 0.0).rgb);
    let l02 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-e.x,  e.y), 0.0).rgb);
    let l12 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,  e.y), 0.0).rgb);
    let l22 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( e.x,  e.y), 0.0).rgb);

    let gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    let gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    let grad = vec2<f32>(gx, gy);
    let gradMag = length(grad);

    // Curl-style perpendicular flow (divergence-free) — pixels swirl along iso-luma curves
    let perp = vec2<f32>(-gy, gx);
    let displacement = perp * flowStrength * 0.06;

    let new_uv = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, new_uv, 0.0).rgb;

    // Iridescent palette mapping by flow direction (compass colors)
    let angle = atan2(grad.y, grad.x);                     // -PI..PI
    let palIdx = u32(clamp((fract(angle / TAU + 0.5 + paletteShift)) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;
    color = mix(color, color * (0.6 + palette * 0.8), iridescence * smoothstep(0.0, 0.3, gradMag));

    // Decay & feedback blend with previous frame
    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    color = mix(color, history * decay, 0.55);
    color *= decay;

    // Bloom-style alpha — HDR shoulder above 0.7 + flow magnitude weighting
    let luma = getLuma(color);
    let bloom = max(0.0, luma - 0.7) * 3.0;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = clamp(luma * 0.4 + bloom * 0.5 + gradMag * 1.5 * flowStrength + depth * 0.1, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
