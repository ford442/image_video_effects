// ═══════════════════════════════════════════════════════════════════
//  Xerox Degrade
//  Category: retro-glitch
//  Features: glitch, branchless, sigmoid-contrast, ordered-dither, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-01-30
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

fn hash3_packed(p: vec2<f32>) -> vec3<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

fn bayer4x4(p: vec2<i32>) -> f32 {
    let x = u32(p.x) & 3u;
    let y = u32(p.y) & 3u;
    let M = array<u32, 16>(
        0u,  8u,  2u, 10u,
       12u,  4u, 14u,  6u,
        3u, 11u,  1u,  9u,
       15u,  7u, 13u,  5u
    );
    return f32(M[y * 4u + x]) * 0.0625;
}

fn sigmoidContrast(x: f32, k: f32) -> f32 {
    return 1.0 / (1.0 + exp(-k * (x - 0.5)));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let contrast  = u.zoom_params.x * 8.0 + 2.0 + mids * 2.0;
    let grain_amt = clamp(u.zoom_params.y + bass * 0.15, 0.0, 1.0);
    let smear_amt = u.zoom_params.z * (1.0 + bass * 0.5);
    let threshold = clamp(u.zoom_params.w + treble * 0.05, 0.0, 1.0);

    let h = hash3_packed(uv * resolution * 0.01 + time * 0.1);
    let smear_n = (h.x - 0.5) * smear_amt * 0.1;

    let smear_uv = vec2<f32>(uv.x + smear_n, uv.y);
    let oob = step(1.0, smear_uv.x) + step(smear_uv.x, 0.0);
    let sample = textureSampleLevel(readTexture, u_sampler, clamp(smear_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let paper = vec3<f32>(0.96, 0.96, 0.92);
    let color = mix(sample, paper, min(oob, 1.0));

    let luma_raw = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let luma_thresh = clamp(luma_raw - threshold + 0.5, 0.0, 1.0);
    let contrasted = sigmoidContrast(luma_thresh, contrast);

    let dither = bayer4x4(coord) - 0.5;
    let toned = clamp(contrasted + dither * 0.06, 0.0, 1.0);

    let scatter = select(0.0, -0.4, h.y < grain_amt * 0.18) +
                  select(0.0,  0.3, h.z > 1.0 - grain_amt * 0.18);
    let final_luma = clamp(toned + scatter * grain_amt, 0.0, 1.0);

    let toner_black = vec3<f32>(0.05, 0.05, 0.12);
    let final_color = mix(toner_black, paper, final_luma);

    let alpha = mix(0.85, 1.0, 1.0 - final_luma);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let finalColor = vec4<f32>(final_color, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
