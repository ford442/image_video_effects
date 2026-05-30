// ═══════════════════════════════════════════════════════════════════
//  Spectral Brush
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal, depth-aware, blackbody, upgraded-rgba
//  Complexity: High
//  Chunks From: spectral-brush, hue_preserve_clamp, ACES, bass_env, IGN-dither
//  Created: 2026-05-10
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

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

// ═══ CHUNK: blackbody_radiation ═══
fn blackbody(t: f32) -> vec3<f32> {
  // t in 0..1 maps to ~1000K..12000K
  let kelvin = mix(1000.0, 12000.0, t);
  let k = kelvin / 1000.0;
  var r = 1.0;
  var g = 1.0;
  var b = 1.0;
  if (k <= 6.6) {
    r = 1.0;
    g = clamp(0.39 * log(k) + 0.5, 0.0, 1.0);
  } else {
    r = clamp(1.29 * pow(k - 6.6, -0.133), 0.0, 1.0);
    g = clamp(1.14 * pow(k - 6.6, -0.075), 0.0, 1.0);
  }
  if (k >= 6.6) {
    b = 1.0;
  } else if (k <= 2.0) {
    b = 0.0;
  } else {
    b = clamp(0.54 * log(k - 2.0) + 0.5, 0.0, 1.0);
  }
  return vec3<f32>(r, g, b);
}

// ═══ CHUNK: hue_preserve_clamp ═══
fn huePreserveClamp(col: vec3<f32>, maxRGB: f32) -> vec3<f32> {
  let mx = max(max(col.r, col.g), col.b);
  if (mx > maxRGB) {
    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    return mix(col * (maxRGB / mx), vec3<f32>(lum), 0.15);
  }
  return col;
}

// ═══ CHUNK: ACES_tone_map ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign_noise(p: vec2<i32>) -> f32 {
  let f = vec2<f32>(p);
  return fract(52.9829189 * fract(dot(f, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / resolution;
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let brushSize = u.zoom_params.x * 0.2 * (1.0 + bass * 0.2);
  let temperature = u.zoom_params.y;
  let decay = 0.005 + (1.0 - u.zoom_params.z) * 0.1;
  let edgeHardness = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let dist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthDiffusion = mix(0.3, 1.0, depth);

  let prevMask = textureLoad(dataTextureC, coord, 0).r;
  let cooledMask = max(0.0, prevMask - decay * (1.0 + treble * 0.1));

  let untouched = select(0.0, 1.0, cooledMask <= 0.0 && dist > brushSize);

  let innerRadius = brushSize * (1.0 - edgeHardness * 0.9) * depthDiffusion;
  let brushVal = 1.0 - smoothstep(innerRadius, brushSize, dist);
  let finalMask = max(cooledMask, brushVal);
  let effectiveMask = mix(finalMask, 0.0, untouched);

  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Blackbody color based on temperature + time cooling
  let coolTime = time * 0.05;
  let bbTemp = clamp(temperature + bass * 0.2 - coolTime * (1.0 - effectiveMask), 0.0, 1.0);
  let bbColor = blackbody(bbTemp) * (1.0 + bass * 0.8);

  let brushRGB = mix(original.rgb, bbColor, effectiveMask);

  // Bass bloom around active strokes
  let bloomRadius = brushSize * 2.5 * bass_env(bass, mids);
  let bloomFalloff = smoothstep(bloomRadius, 0.0, dist);
  let bloom = bbColor * bloomFalloff * bass * 0.6;
  let brushRGBBloom = brushRGB + bloom * effectiveMask;

  // Hue-preserve clamp + ACES tone map
  let clamped = huePreserveClamp(brushRGBBloom, 2.0);
  let toneMapped = acesToneMap(clamped);

  let ign = ign_noise(coord);
  let dithered = toneMapped + (ign - 0.5) * 0.003;

  let luminance = dot(dithered, vec3<f32>(0.299, 0.587, 0.114));
  let brushAlpha = mix(original.a, clamp(luminance + 0.3 + bass * 0.15, 0.0, 1.0), effectiveMask);

  let finalColor = mix(vec4<f32>(dithered, brushAlpha), original, untouched);
  let dataA = mix(vec4<f32>(effectiveMask, 0.0, 0.0, effectiveMask), vec4<f32>(0.0), untouched);

  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, coord, dataA);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
