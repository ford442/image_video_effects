// ═══════════════════════════════════════════════════════════════════
//  Xerox Degrade
//  Category: retro-glitch
//  Features: glitch, branchless, sigmoid-contrast, ordered-dither,
//            halftone-dither, paper-grain-fbm, edge-vignette,
//            photocopy, audio-reactive, upgraded-rgba
//  Complexity: Medium-High
//  Created: 2026-01-30
//  Upgraded: 2026-06-28
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

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum = sum + amp * valueNoise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
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

// ── Photocopy halftone dot mask ──────────────────────────────────
fn halftoneDot(luma: f32, uv: vec2<f32>, freq: f32) -> f32 {
    let grid = fract(uv * freq) - 0.5;
    let radius = luma * 0.707;
    return 1.0 - smoothstep(radius - 0.02, radius, length(grid));
}

// ── Edge-darkening vignette ──────────────────────────────────────
fn edgeVignette(uv: vec2<f32>, strength: f32) -> f32 {
    let d = length(uv - vec2<f32>(0.5));
    let v = smoothstep(0.7, 0.35, d);
    return mix(1.0, v, strength);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let nParams = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
    let contrast  = nParams.x * 8.0 + 2.0 + mids * 2.0;
    let grain_amt = clamp(nParams.y + bass * 0.15, 0.0, 1.0);
    let smear_amt = nParams.z * (1.0 + bass * 0.5);
    let threshold = clamp(nParams.w + treble * 0.05, 0.0, 1.0);

    let h = hash3_packed(uv * resolution * 0.01 + time * 0.1);
    let smear_n = (h.x - 0.5) * smear_amt * 0.1;

    let smear_uv = vec2<f32>(uv.x + smear_n, uv.y);
    let oob = step(1.0, smear_uv.x) + step(smear_uv.x, 0.0);
    let src = textureSampleLevel(readTexture, u_sampler, clamp(smear_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let paper = vec3<f32>(0.96, 0.96, 0.92);
    let color = mix(src.rgb, paper, min(oob, 1.0));

    let luma_raw = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let luma_thresh = clamp(luma_raw - threshold + 0.5, 0.0, 1.0);
    let contrasted = sigmoidContrast(luma_thresh, contrast);

    // FBM paper grain displaces the sampled luma
    let grain = fbm(uv * 40.0 + time * 0.5, 4) * 2.0 - 1.0;
    let grain_uv = uv + vec2<f32>(grain * grain_amt * 0.02);
    let grainSample = textureSampleLevel(readTexture, u_sampler,
                                         clamp(grain_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let grainLuma = dot(grainSample, vec3<f32>(0.299, 0.587, 0.114));

    let dither = bayer4x4(coord) - 0.5;
    let halftoneFreq = 24.0 + mids * 16.0;
    let dotted = halftoneDot(contrasted + dither * 0.05, uv, halftoneFreq);

    let blendLuma = mix(contrasted, dotted, 0.6);
    let vign = edgeVignette(uv, 0.5 + treble * 0.5);

    let scatter = select(0.0, -0.4, h.y < grain_amt * 0.18) +
                  select(0.0,  0.3, h.z > 1.0 - grain_amt * 0.18);
    let final_luma = clamp((blendLuma + scatter * grain_amt) * vign +
                           grain * grain_amt * 0.08 + grainLuma * grain_amt * 0.05, 0.0, 1.0);

    let toner_black = vec3<f32>(0.05, 0.05, 0.12);
    let final_color = mix(toner_black, paper, final_luma);

    // Preserve input alpha while letting toner darken transparent edges
    let finalAlpha = mix(clamp(src.a, 0.0, 1.0), 1.0, (1.0 - final_luma) * 0.5);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let finalColor = vec4<f32>(final_color, finalAlpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
