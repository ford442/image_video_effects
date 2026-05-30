// ═══════════════════════════════════════════════════════════════════
//  Pixel Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, chromatic-pixelation, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: pixel-reveal, bass_env, depth-aware-fog
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

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.3 + mids * 0.1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthBlock = mix(0.6, 1.4, depth);

    let pixelSizeParam = max(0.001, u.zoom_params.x * 0.1 * depthBlock * (1.0 - bass * 0.2));
    let radius = u.zoom_params.y * 0.5 * (1.0 + bass * 0.08);
    let softness = max(u.zoom_params.z * 0.2, 0.001);
    let invert = u.zoom_params.w > 0.5;

    let stepX = pixelSizeParam;
    let stepY = pixelSizeParam * (resolution.x / resolution.y);
    let jitter = vec2<f32>(
      (treble * 0.01) * sin(uv.y * 50.0 + u.config.x * 10.0),
      (treble * 0.01) * cos(uv.x * 50.0 + u.config.x * 10.0)
    );
    let pixelatedUV = clamp(vec2<f32>(
        floor(uv.x / stepX) * stepX + stepX * 0.5 + jitter.x,
        floor(uv.y / stepY) * stepY + stepY * 0.5 + jitter.y
    ), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let aspect = resolution.x / resolution.y;
    let dist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
    let revealMask = smoothstep(radius, radius + softness + 0.001, dist);
    let mask = select(revealMask, 1.0 - revealMask, invert);

    let clearColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let px = pixelatedUV;
    let chromaShift = 0.003 * (1.0 + mids * 0.5);
    let r = textureSampleLevel(readTexture, non_filtering_sampler, px + vec2<f32>(chromaShift, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, non_filtering_sampler, px, 0.0).g;
    let b = textureSampleLevel(readTexture, non_filtering_sampler, px - vec2<f32>(chromaShift, 0.0), 0.0).b;
    let pixelColor = vec4<f32>(r, g, b, clearColor.a);

    let finalColor = mix(clearColor.rgb, pixelColor.rgb, mask);
    let alpha = clamp(mix(clearColor.a, pixelColor.a, mask) * 0.55 + abs(mask - 0.5) * 0.25 + treble * 0.05 + bass * 0.08, 0.08, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
