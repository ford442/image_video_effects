// ═══════════════════════════════════════════════════════════════════
//  Tilt Shift Miniature
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=FocusWidth, z=Saturation, w=Contrast
  ripples: array<vec4<f32>, 50>,
};

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    var K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    var p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    var K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    var p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;

    // Params — bass widens blur radius slightly
    let strength    = u.zoom_params.x * 20.0 * (1.0 + bass * 0.2);
    let focus_width = u.zoom_params.y * 0.3 + 0.05;
    let saturation  = u.zoom_params.z * 2.0 * (1.0 + mids * 0.1);
    let contrast    = u.zoom_params.w * 2.0;

    let focus_y    = u.zoom_config.z;
    let dist_focus = abs(uv.y - focus_y);
    let blur_factor = smoothstep(focus_width * 0.5, focus_width * 1.5, dist_focus);
    let radius      = strength * blur_factor;

    var color_sum    = vec3<f32>(0.0);
    var total_weight = 0.001; // Guard divide-by-zero

    let samples = 12.0;
    for (var i = 0.0; i < samples; i = i + 1.0) {
        let r     = sqrt(i + 0.5) / sqrt(samples) * radius;
        let theta = 2.3999632 * i;
        let offset = vec2<f32>(cos(theta), sin(theta)) * r / resolution;
        let sample_uv = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        color_sum    += textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;
        total_weight += 1.0;
    }

    var final_color = color_sum / total_weight;

    var hsv = rgb2hsv(final_color);
    hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
    final_color = hsv2rgb(hsv);
    final_color = clamp((final_color - 0.5) * contrast + 0.5, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: blur band presence (out of focus = higher alpha overlay) + bass
    let alpha = clamp(blur_factor * 0.5 + bass * 0.15 + 0.1, 0.0, 1.0);
    let fc = vec4<f32>(final_color, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
