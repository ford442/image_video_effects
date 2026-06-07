// ═══════════════════════════════════════════════════════════════════
//  Iso Hills v2
//  Category: artistic
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: iso-hills
//  Upgraded: 2026-05-30
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var x = p;
  for (var i: i32 = 0; i < 5; i = i + 1) {
    v = v + a * noise(x);
    x = x * 2.03;
    a = a * 0.5;
  }
  return v;
}

fn acesTone(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn lumaAt(uv: vec2<f32>) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let texel = 1.0 / resolution;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let contourSteps = max(4.0, floor(mix(4.0, 32.0, u.zoom_params.x)));
  let heightScale = u.zoom_params.y * 2.0;
  let smoothness = u.zoom_params.z;
  let hazeStrength = u.zoom_params.w;

  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let baseLuma = lumaAt(uv);

  // Multi-octave fBm terrain with temporal drift
  let terrainUV = uv * 3.0 + vec2<f32>(time * 0.02, time * 0.015);
  var height = fbm(terrainUV) * heightScale + baseLuma * 0.4;
  height = height + sin((uv.x + uv.y) * 8.0 + time * (1.0 + bass * 2.0)) * 0.03 * bass;

  // Simulated hydraulic erosion from bass-triggered rainfall
  let rain = bass * 0.5 + 0.1;
  let erosion = rain * 0.06 * sin(uv.x * 14.0 + time * 3.0) * cos(uv.y * 11.0 - time * 2.0);
  height = height - abs(erosion);

  // River channel approximation via low-frequency carve
  let river = sin(uv.x * 3.0 + fbm(uv * 1.5) * 2.0) * 0.04 * smoothstep(0.2, 0.6, height);
  height = height - river * (0.5 + bass * 0.5);

  // Mouse-driven water drops carve channels via ripple array
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let d = length(uv - r.xy);
    let t = time - r.z;
    let wave = sin(d * 40.0 - t * 6.0) * exp(-d * 6.0 - t * 1.5);
    height = height - wave * 0.06 * smoothness;
  }
  let mouseDist = length(uv - mousePos);
  let mouseCarve = smoothstep(0.2, 0.0, mouseDist) * 0.1 * mouseDown;
  height = height - mouseCarve;

  // Analytic derivative normals from luma offsets
  let hdx = (lumaAt(uv + vec2<f32>(texel.x, 0.0)) - lumaAt(uv - vec2<f32>(texel.x, 0.0))) * 0.5;
  let hdy = (lumaAt(uv + vec2<f32>(0.0, texel.y)) - lumaAt(uv - vec2<f32>(0.0, texel.y))) * 0.5;
  let normal = normalize(vec3<f32>(-hdx * heightScale * 6.0, 0.45, -hdy * heightScale * 6.0));
  let sunDir = normalize(vec3<f32>(0.5 + sin(time * 0.3) * 0.3, 0.75 + treble * 0.15, 0.4));
  let shade = max(dot(normal, sunDir), 0.0);

  // Marching Cubes-style contour extraction
  let stepped = floor(height * contourSteps) / contourSteps;
  let smoothHeight = mix(stepped, height, smoothness * 0.5);
  let contour = 1.0 - smoothstep(0.012, 0.045, abs(fract(smoothHeight * contourSteps) - 0.5));

  // Elevation-based color palette: valley -> meadow -> rock -> snow
  let valley = vec3<f32>(0.06, 0.22 + bass * 0.06, 0.08);
  let meadow = vec3<f32>(0.32, 0.50 + mids * 0.1, 0.16);
  let rock = vec3<f32>(0.52, 0.38, 0.26);
  let snow = vec3<f32>(0.92 + treble * 0.08, 0.95, 1.0);
  let slopeColor = mix(
    mix(mix(valley, meadow, smoothstep(0.15, 0.45, smoothHeight)),
        rock, smoothstep(0.55, 0.75, smoothHeight)),
    snow, smoothstep(0.78, 0.95, smoothHeight)
  );

  // Contour hachures for topographic map aesthetic
  let hachure = contour * (0.6 + 0.4 * sin(smoothHeight * contourSteps * 18.0 + uv.x * 30.0));
  let hachureColor = vec3<f32>(0.12, 0.10, 0.06) * hachure * 0.35;

  // HDR snow sparkle on summit normals
  let snowSparkle = smoothstep(0.9, 1.0, smoothHeight) * pow(max(shade, 0.0), 4.0) * (0.5 + treble * 0.5);
  let litColor = slopeColor * mix(0.3, 1.0, shade) + hachureColor + vec3<f32>(snowSparkle) + base.rgb * 0.08;

  // Depth-based atmospheric haze on distant hills
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let haze = mix(0.0, 0.45, hazeStrength) * (1.0 - depth);
  let hazeColor = vec3<f32>(0.72, 0.76, 0.88);
  let finalColor = mix(litColor, hazeColor, haze);

  // ACES tone mapping
  let acesColor = acesTone(finalColor * 1.15);

  // Alpha: contour line density × elevation_confidence × (1.0 - haze)
  let elevationConfidence = smoothstep(0.0, 0.2, smoothHeight) * smoothstep(1.0, 0.6, smoothHeight) + 0.25;
  let alpha = clamp(contour * elevationConfidence * (1.0 - haze) + smoothHeight * 0.12 + bass * 0.04, 0.1, 0.92);

  let outDepth = clamp(depth + smoothHeight * 0.03, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(acesColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(smoothHeight, contour, shade, alpha));
}
