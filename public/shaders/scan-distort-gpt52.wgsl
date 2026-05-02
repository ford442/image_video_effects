// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(41.7, 289.3))) * 43758.5453);
}

fn to_linear(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(2.2));
}

fn to_srgb(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(1.0 / 2.2));
}

fn aces_tm(c: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let cc = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((c * (a * c + b)) / (c * (cc * c + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Params
  let lineParam = u.zoom_params.x;
  let bendParam = u.zoom_params.y;
  let glitchParam = u.zoom_params.z;
  let rollParam = u.zoom_params.w;

  let lines = mix(200.0, 1400.0, lineParam);
  let bend = mix(0.0, 0.18, bendParam);
  let glitch = glitchParam * 0.08;
  let roll = time * mix(0.2, 2.5, rollParam);

  var warped = uv;
  let centered = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let radius = length(centered);
  warped += centered * (radius * radius) * bend;

  let linePhase = (warped.y + roll) * lines;
  let scan = sin(linePhase) * 0.5 + 0.5;
  // HDR scanline boost: peaks exceed 1.0 for tone mapping
  let scanBoost = 0.65 + 0.75 * scan;

  let lineId = floor(warped.y * lines * 0.05);
  let jitter = (hash(vec2<f32>(lineId, floor(time * 24.0))) - 0.5) * glitch;

  let blockId = floor(warped.y * 30.0);
  let blockNoise = hash(vec2<f32>(blockId, floor(time * 12.0)));
  let blockJitter = (blockNoise - 0.5) * glitch * step(blockNoise, glitchParam * 0.6);

  let offset = vec2<f32>(jitter + blockJitter, 0.0);

  let aberr = glitchParam * 0.01 + 0.002;
  let r = textureSampleLevel(readTexture, u_sampler, warped + offset + vec2<f32>(aberr, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, warped + offset, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, warped + offset - vec2<f32>(aberr, 0.0), 0.0).b;

  // Linear HDR workflow
  var color = to_linear(vec3<f32>(r, g, b)) * scanBoost;

  // Cinematic film grain
  let grain = (hash(uv * resolution + time) - 0.5) * 0.03
            + (hash(uv * resolution * 1.3 - time * 0.7) - 0.5) * 0.015;
  color += vec3<f32>(grain) * glitchParam;

  // Depth-based atmospheric haze
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let fogAmount = smoothstep(0.0, 1.0, depth * 0.5 + radius * 0.35) * 0.4;
  let fogColor = vec3<f32>(0.08, 0.06, 0.04); // warm amber atmospheric haze
  color = mix(color, fogColor * 1.5, fogAmount);

  // Split-tone: cool shadows / warm gold highlights
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let shadowTint = vec3<f32>(0.6, 0.75, 1.0);
  let highlightTint = vec3<f32>(1.15, 0.95, 0.7);
  let shadowMask = 1.0 - smoothstep(0.0, 0.25, lum);
  let highlightMask = smoothstep(0.5, 1.0, lum);
  color = color * mix(vec3<f32>(1.0), shadowTint, shadowMask * 0.3);
  color = color * mix(vec3<f32>(1.0), highlightTint, highlightMask * 0.25);

  // Fresnel rim glow on barrel distortion edges
  let rim = pow(radius * 1.6, 3.0);
  let rimColor = vec3<f32>(1.0, 0.85, 0.5);
  color += rimColor * rim * 0.6 * (1.0 - bendParam * 0.3);

  // Vignette for cinematic focus
  let vignette = 1.0 - smoothstep(0.4, 1.2, radius);
  color = color * (0.55 + 0.45 * vignette);

  // ACES tone map + sRGB output
  color = aces_tm(color);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(to_srgb(color), 1.0));

  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
