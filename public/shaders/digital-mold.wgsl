// ═══════════════════════════════════════════════════════════════════
//  Digital Mold
//  Category: image
//  Features: animated, reaction-diffusion, spore-noise, depth-humidity, upgraded-rgba
//  Complexity: High
//  Chunks From: digital-mold, reaction-diffusion, fbm, bass_env
//  Created: 2024-01-01
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
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

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.3 + mids * 0.1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let feedRate = mix(0.01, 0.09, u.zoom_params.x) * bass_env(bass, mids);
    let killRate = mix(0.01, 0.07, u.zoom_params.y);
    let diffusionA = mix(0.5, 1.5, u.zoom_params.z);
    let diffusionB = u.zoom_params.w;

    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var a = prev.r;
    var b = prev.g;

    let e = 1.0 / resolution.x;
    let right = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv + vec2<f32>(e, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let left = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv - vec2<f32>(e, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let top = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, e), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let bottom = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv - vec2<f32>(0.0, e), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lapA = right.r + left.r + top.r + bottom.r - 4.0 * a;
    let lapB = right.g + left.g + top.g + bottom.g - 4.0 * b;

    let reaction = a * b * b;
    a = a + diffusionA * lapA - reaction + feedRate * (1.0 - a);
    b = b + diffusionB * lapB + reaction - (killRate + feedRate) * b;
    a = clamp(a, 0.0, 1.0);
    b = clamp(b, 0.0, 1.0);

    // Depth humidity: foreground grows faster
    let humidity = mix(0.7, 1.3, depth);
    b = b * humidity;

    // Mouse spore injection
    let mouseDist = distance(uv, mouse);
    let spore = smoothstep(0.05, 0.0, mouseDist) * bass_env(bass, mids);
    b = b + spore * 0.1;
    b = clamp(b, 0.0, 1.0);

    let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mold palette: deep green to blue-black with spore highlights
    let moldColor = mix(vec3<f32>(0.05, 0.15, 0.05), vec3<f32>(0.0, 0.4, 0.2), a);
    let sporeColor = vec3<f32>(0.6, 0.9, 0.3) * b * (1.0 + treble * 0.5);
    let combined = moldColor + sporeColor;

    let finalRGB = mix(source.rgb, combined, b * 0.7);
    let alpha = clamp(source.a * 0.5 + b * 0.4 + a * 0.2, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(a, b, 0.0, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
