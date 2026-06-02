// ═══════════════════════════════════════════════════════════════════
//  Fractal Noise Dissolve
//  Category: visual-effects
//  Features: noise, dissolve, fractal, audio-eat, depth-layers, temporal-erosion, organic-breakup
//  Complexity: Medium
//  Updated: 2026-05-31
//  By: Grok (visual flourish — richer erosion, audio-driven breakup, atmospheric layers)
// ═══════════════════════════════════════════════════════════════════
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(dot(hash22(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
            dot(hash22(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u2.x),
        mix(dot(hash22(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
            dot(hash22(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * noise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFade = mix(0.7, 1.0, depth);

    let noiseScale = u.zoom_params.x * 20.0 + 5.0;
    let radius = u.zoom_params.y * 0.5 * bass_env(bass, mids);
    let edgeWidth = max(u.zoom_params.z * 0.2, 0.01);
    let burnColor = u.zoom_params.w * (1.0 + mids * 0.35);

    // Domain warped FBM
    let warp = vec2<f32>(
        fbm(uv * noiseScale * 0.5 + vec2<f32>(time * 0.1, 0.0), 3),
        fbm(uv * noiseScale * 0.5 + vec2<f32>(0.0, time * 0.1), 3)
    );
    var n = fbm((uv + warp * 0.1) * noiseScale * (1.0 + bass * 0.25) + vec2<f32>(time, time * 0.7), 4);
    n += fbm((uv + warp * 0.15) * noiseScale * 2.0 - vec2<f32>(time * (1.0 + treble * 0.2), time), 4) * 0.5;
    n = n * 0.5 + 0.5;

    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let contour = dist + (n * 0.2 - 0.1);
    let mask = smoothstep(radius, radius + edgeWidth, contour);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let edge = 1.0 - smoothstep(radius, radius + edgeWidth * 2.0, contour);
    let burn = vec3<f32>(1.0, 0.45 + treble * 0.2, 0.18 + mids * 0.2) * edge * burnColor * 4.0 * (1.0 - mask);

    // Edge glow from audio
    let edgeGlow = vec3<f32>(0.5 + bass * 0.3, 0.3, 0.8) * edge * bass * 0.5;
    var finalColor = baseColor.rgb * mask + burn + edgeGlow;
    finalColor = finalColor * depthFade;
    let alpha = clamp(baseColor.a * mask + edge * 0.42 + bass * 0.05, 0.04, 1.0);
    let depthOut = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + edge * 0.06, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
