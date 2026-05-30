// ═══════════════════════════════════════════════════════════════════
//  Porcelain Fracture Glow
//  Category: artistic
//  Features: porcelain, crack, kintsugi, light-vein, audio-pulse, mouse-crack, semantic-alpha
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21, valueNoise)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — fine porcelain that develops glowing luminous cracks following image structure, audio makes the light sing)
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
  zoom_params: vec4<f32>,  // x=Crack, y=Glow, z=Light, w=Age
  ripples: array<vec4<f32>, 50>,
};

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

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var v = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) { v += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let crackAmt = u.zoom_params.x * (0.7 + bass * 0.5);
    let glowAmt = u.zoom_params.y * (0.8 + treble * 0.6);
    let lightTemp = u.zoom_params.z;
    let age = u.zoom_params.w;

    let mouse = u.zoom_config.yz;
    let mousePress = u.zoom_config.w;

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Crack network — follows image edges + organic noise
    let edge = length(vec2<f32>(
        luma - dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0012, 0.0), 0.0).rgb, vec3<f32>(0.299,0.587,0.114)),
        luma - dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, 0.0012), 0.0).rgb, vec3<f32>(0.299,0.587,0.114))
    )) * 2.2;

    let crackNoise = fbm(uv * 18.0 + age * 1.5, 4) * 0.6 + fbm(uv * 41.0 - time * 0.03, 3) * 0.4;
    let crack = smoothstep(0.32, 0.78, edge + crackNoise * 0.55) * crackAmt;

    // Mouse can "draw" new cracks
    let mouseCrack = smoothstep(0.04, 0.0, length(uv - mouse)) * mousePress * 1.4;
    let totalCrack = clamp(crack + mouseCrack * 0.7, 0.0, 1.0);

    // Luminous kintsugi-style veins
    let vein = pow(totalCrack, 1.4) * glowAmt;
    let veinColor = mix(vec3<f32>(1.0, 0.65, 0.25), vec3<f32>(0.4, 0.85, 1.0), lightTemp);

    // Porcelain base (slightly cool, glossy)
    let porcelain = mix(input.rgb, vec3<f32>(0.92, 0.9, 0.88), 0.35);
    var col = mix(porcelain, input.rgb, 0.7 - totalCrack * 0.4);

    // Glowing light leaking from cracks
    let leak = vein * (0.6 + bass * 0.5 + sin(time * 3.0 + uv.x * 9.0) * treble * 0.3);
    col += veinColor * leak * 1.3;

    // Subtle rim light on cracks
    col += veinColor * pow(vein, 2.5) * 0.8;

    // Age patina
    let patina = fbm(uv * 3.0, 2) * age * 0.12;
    col = mix(col, col * vec3<f32>(0.75, 0.82, 0.78), patina);

    // Semantic alpha — cracks glow with light
    let semantic_alpha = clamp(0.62 + leak * 0.7 + vein * 0.35, 0.5, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    let d = clamp(0.22 + vein * 0.6, 0.0, 0.95);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    textureStore(dataTextureA, global_id.xy, vec4<f32>(totalCrack, leak, lightTemp, semantic_alpha));
}
