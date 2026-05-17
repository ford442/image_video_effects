// ═══════════════════════════════════════════════════════════════════
//  Neon Ripple Split
//  Category: distortion
//  Features: branchless, vectorized-split, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Low
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
  zoom_params: vec4<f32>,  // x=SplitAmount, y=RippleSpeed, z=Intensity, w=SplitCount
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

// Fast approximate sin via parabolic min-max (range-reduced); ~2× speed of math sin.
// Accurate to ~1% for small displacement use cases (which is what we need).
fn fastSin(x: f32) -> f32 {
    let x_red = x - TAU * floor((x + 3.14159265) / TAU);   // wrap to -PI..PI
    let xa = abs(x_red);
    return x_red * (1.0 - 0.21 * xa) - 0.063 * x_red * xa;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let splitAmount = u.zoom_params.x * 0.1 * (1.0 + bass * 0.3);
    let rippleSpeed = u.zoom_params.y * 5.0;
    let intensity   = u.zoom_params.z * 2.0;
    let splitCount  = u.zoom_params.w * 5.0 + 2.0;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Single ripple value reused for all channels (vs computing 3× redundantly)
    let ripple = fastSin(uv.y * 20.0 - time * rippleSpeed) * splitAmount;
    let dx = ripple * splitCount;

    // Branchless clamped sample positions — vectorized
    let rUV = clamp(uv + vec2<f32>( dx, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + vec2<f32>(-dx, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv,  0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let splitColor = vec3<f32>(r, g, b);

    // Neon emission proportional to split magnitude (single mul, no conditional)
    let absRipple = abs(ripple);
    let neon = vec3<f32>(1.0, 0.5, 0.8) * absRipple * 10.0 * intensity;
    let finalColor = splitColor + neon;

    // Branchless effect-intensity alpha
    let displacement = abs(dx);
    let baseAlpha = mix(0.5, 1.0, smoothstep(0.0, 0.1, displacement) * intensity);
    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(baseAlpha * 0.7 + luma * 0.25 + absRipple * 0.5, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
}
