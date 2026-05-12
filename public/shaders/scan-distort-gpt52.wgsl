// ═══════════════════════════════════════════════════════════════════
//  Scan Distort Matrix gpt52 (Batch D Upgrade)
//  Category: distortion
//  Features: glitch, animated, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgrades: 3-band frequency distortion, FBM scan lines,
//            effect-mask alpha, mids-driven band distortion
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

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(41.7, 289.3))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p * 0.1031;
  let d = fract(pp.x * pp.y * 23.4517 + pp.y * 37.2314);
  let s = vec2<f32>(d + 0.113, d + 0.257);
  return fract(s * s * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
    mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    v = v + a * noise2(pp);
    pp = pp * 2.03;
    a = a * 0.5;
  }
  return v;
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Params
  let scanIntensity = u.zoom_params.x;
  let bandSplit = u.zoom_params.y;
  let fbmScale = u.zoom_params.z;
  let chromaticMix = u.zoom_params.w;

  let lines = mix(200.0, 1400.0, scanIntensity);
  let bend = mix(0.0, 0.18, bandSplit);
  let glitch = scanIntensity * 0.08;
  let roll = time * mix(0.2, 2.5, chromaticMix);

  // FBM perturbation for scan line positions
  let fbmPerturb = fbm(vec2(uv.y * fbmScale * 5.0, time * 0.3)) * 0.02 * fbmScale;

  var warped = uv;
  let centered = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let radius = length(centered);
  warped += centered * (radius * radius) * bend;

  // Split into 3 frequency bands by Y position
  let bandY = uv.y;
  let band1 = smoothstep(0.0, 0.33, bandY) * (1.0 - smoothstep(0.33, 0.34, bandY));
  let band2 = smoothstep(0.33, 0.66, bandY) * (1.0 - smoothstep(0.66, 0.67, bandY));
  let band3 = smoothstep(0.66, 1.0, bandY);

  // Mids drive band distortion amount
  let mids = plasmaBuffer[0].y;
  let bandDistort = 1.0 + mids * 3.0;

  let linePhase = (warped.y + roll + fbmPerturb) * lines;
  let scan = sin(linePhase) * 0.5 + 0.5;
  let scanBoost = 0.65 + 0.75 * scan;

  // Different distortions per band
  let lineId = floor(warped.y * lines * 0.05);
  let jitter1 = (hash(vec2<f32>(lineId, floor(time * 24.0))) - 0.5) * glitch * bandDistort;
  let jitter2 = (hash(vec2<f32>(lineId + 100.0, floor(time * 18.0))) - 0.5) * glitch * bandDistort * 1.5;
  let jitter3 = (hash(vec2<f32>(lineId + 200.0, floor(time * 30.0))) - 0.5) * glitch * bandDistort * 0.7;

  let blockId = floor(warped.y * 30.0);
  let blockNoise = hash(vec2<f32>(blockId, floor(time * 12.0)));
  let blockJitter = (blockNoise - 0.5) * glitch * step(blockNoise, scanIntensity * 0.6);

  let offset1 = vec2<f32>((jitter1 + blockJitter) * band1, 0.0);
  let offset2 = vec2<f32>((jitter2 + blockJitter) * band2, 0.0);
  let offset3 = vec2<f32>((jitter3 + blockJitter) * band3, 0.0);
  let totalOffset = offset1 + offset2 + offset3;

  let aberr = scanIntensity * 0.01 + 0.002;
  let r = textureSampleLevel(readTexture, u_sampler, warped + totalOffset + vec2<f32>(aberr, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, warped + totalOffset, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, warped + totalOffset - vec2<f32>(aberr, 0.0), 0.0).b;

  // Linear HDR workflow
  var color = to_linear(vec3<f32>(r, g, b)) * scanBoost;

  // Cinematic film grain
  let grain = (hash(uv * resolution + time) - 0.5) * 0.03
            + (hash(uv * resolution * 1.3 - time * 0.7) - 0.5) * 0.015;
  color += vec3<f32>(grain) * scanIntensity;

  // Depth-based atmospheric haze
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let fogAmount = smoothstep(0.0, 1.0, depth * 0.5 + radius * 0.35) * 0.4;
  let fogColor = vec3<f32>(0.08, 0.06, 0.04);
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
  color += rimColor * rim * 0.6 * (1.0 - bandSplit * 0.3);

  // Vignette for cinematic focus
  let vignette = 1.0 - smoothstep(0.4, 1.2, radius);
  color = color * (0.55 + 0.45 * vignette);

  // ACES tone map + sRGB output
  color = aces_tm(color);

  // Effect-mask alpha based on distortion strength
  let effectStrength = scanIntensity + bandDistort * 0.3 + length(totalOffset) * 10.0;
  let alpha = clamp(effectStrength, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(to_srgb(color), alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
