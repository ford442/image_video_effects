// ═══════════════════════════════════════════════════════════════════
//  Sand Dunes
//  Category: generative
//  Features: generative, audio-reactive, bagnold-physics, anisotropic-fbm,
//            wind-erosion, separation-bubble, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
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
  let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = mix(
    mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
    mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
    u.y
  );
  return n;
}

fn fBm(p: vec2<f32>, octaves: i32) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    val = val + amp * noise2(p * freq);
    amp = amp * 0.5;
    freq = freq * 2.03;
  }
  return val;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let duneScale = u.zoom_params.x * 4.0 + 2.0;
  let windBase = u.zoom_params.y * 0.5;
  let erosion = u.zoom_params.z;
  let shadowDepth = u.zoom_params.w;

  // Wind direction from mouse + mids
  let windAngle = (mouse.x - 0.5) * 1.5 + (mids - 0.5) * 0.8;
  let windDir = vec2<f32>(cos(windAngle), sin(windAngle));
  let windSpeed = windBase + bass * 0.3;
  let t = time * windSpeed;

  // Anisotropic fBm stretched along wind direction
  let p = uv * duneScale;
  let aniso = vec2<f32>(dot(p, windDir), dot(p, vec2<f32>(-windDir.y, windDir.x))) * vec2<f32>(2.5, 1.0);
  let height = fBm(aniso + vec2<f32>(t * 0.3, 0.0), 5) * 0.5 + 0.5;

  // Separation bubble at crests (lee side)
  let slope = (fBm(aniso + vec2<f32>(0.01, 0.0) + vec2<f32>(t * 0.3, 0.0), 5)
             - fBm(aniso - vec2<f32>(0.01, 0.0) + vec2<f32>(t * 0.3, 0.0), 5)) * 25.0;
  let crest = smoothstep(0.3, 0.7, height) * smoothstep(0.0, -0.4, slope);
  let bubble = crest * 0.25 * (1.0 + bass * 0.5);

  // Ripple superposition on dune flanks
  let rippleCoord = p * 8.0 + windDir * t * 2.0;
  let ripple1 = sin(rippleCoord.x * 3.0 + rippleCoord.y * 1.5) * 0.5 + 0.5;
  let ripple2 = sin(rippleCoord.x * 5.0 - rippleCoord.y * 2.0 + t * 1.5) * 0.5 + 0.5;
  let rippleMask = smoothstep(0.6, 0.9, ripple1 * ripple2) * erosion * (0.5 + abs(slope) * 2.0);

  // Desert palette: ochre -> sienna -> umber
  let lit = vec3<f32>(0.92, 0.72, 0.42);
  let mid = vec3<f32>(0.72, 0.45, 0.22);
  let shadow = vec3<f32>(0.42, 0.28, 0.14);
  let umber = vec3<f32>(0.28, 0.18, 0.10);

  // Shadow based on slope and wind direction
  let shadowMask = smoothstep(0.2, -0.6, slope) * shadowDepth;
  let duneColor = mix(lit, mix(mid, shadow, shadowMask * 0.7), shadowMask);

  // Subsurface scattering on slip faces
  let sss = smoothstep(-0.8, -0.2, slope) * crest * vec3<f32>(0.55, 0.30, 0.12) * 0.4;

  // Saltation sparkles from treble
  let sparkleCoord = uv * 120.0 + windDir * t * 10.0;
  let sparkle = step(0.997 - treble * 0.003, fract(sin(dot(sparkleCoord, vec2<f32>(12.9898, 78.233))) * 43758.5453));
  let sparkleColor = vec3<f32>(1.0, 0.95, 0.85) * sparkle * treble * (0.5 + smoothstep(0.0, -0.3, slope));

  // Wind shadows behind mouse
  let mouseDist = length(uv - mouse);
  let windShadow = smoothstep(0.15, 0.0, mouseDist) * smoothstep(0.0, 0.5, dot(normalize(uv - mouse), windDir));

  // Atmospheric haze by depth
  let haze = depth * 0.35 * (1.0 + bass * 0.2);
  let skyColor = vec3<f32>(0.82, 0.72, 0.58);

  var finalColor = mix(duneColor, umber, rippleMask) + sss + sparkleColor;
  finalColor = finalColor * (1.0 - windShadow * 0.4);
  finalColor = mix(finalColor, skyColor, haze);

  // HDR specular on saltating grains
  let spec = sparkle * treble * 2.0;
  finalColor = finalColor + vec3<f32>(0.95, 0.88, 0.72) * spec;

  // ACES tone mapping
  finalColor = acesToneMap(finalColor * 1.2);

  // Alpha: sand density * wind exposure * (1.0 - haze)
  let sandDensity = 0.75 + height * 0.2 + rippleMask * 0.1;
  let windExposure = 0.6 + windSpeed * 0.4;
  let alpha = clamp(sandDensity * windExposure * (1.0 - haze * 0.5), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(height * 0.5 + bubble, 0.0, 0.0, 0.0));
}
