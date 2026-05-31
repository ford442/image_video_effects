// ═══════════════════════════════════════════════════════════════════
//  Encaustic Wax v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, painterly, thermal-flow
//  Complexity: High
//  Chunks From: encaustic-wax
//  Created: 2026-05-31
//  By: 4-Agent Swarm
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash13(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    v = v + a * noise2(pp);
    pp = pp * 2.1;
    a = a * 0.5;
  }
  return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  let c = x * 0.85 + 0.30;
  return clamp((a / b) * c, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Param mapping: x=BrushScale, y=MeltIntensity, z=PigmentDeposit, w=Relief
  let brushScale = mix(2.0, 24.0, u.zoom_params.x);
  let meltIntensity = mix(0.0, 0.14, u.zoom_params.y) * (1.0 + audio.x * 0.6);
  let pigmentDeposit = mix(0.1, 0.95, u.zoom_params.z);
  let relief = mix(0.04, 0.60, u.zoom_params.w);

  // Thermal field: bass heat gun + local mouse heat
  let heatGlobal = audio.x * 0.5;
  let mouseDist = length((mouse - uv) * vec2<f32>(aspect, 1.0));
  let heatMouse = 1.0 - smoothstep(0.0, 0.45, mouseDist);
  let heat = heatGlobal + heatMouse * (0.5 + audio.x * 0.5);
  let viscosity = 1.0 / (1.0 + heat * 3.0);

  // Depth-driven wax thickness: nearer = thicker pigment build-up
  let thickness = mix(0.6, 1.4, depth);

  // Layered wax strata with density-driven pigment separation
  var waxColor = vec3<f32>(0.0);
  var strataMask = 0.0;
  for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
    let lf = f32(layer);
    let freq = brushScale * (1.0 + lf * 0.7);
    let n = fbm(uv * freq * 0.4 + vec2<f32>(time * 0.08 * viscosity, -time * 0.06 * viscosity) + lf * 4.3);
    let density = smoothstep(0.25 + lf * 0.18, 0.65 + lf * 0.12, n);
    let layerThick = density * relief * thickness * (1.0 - lf * 0.28);
    let pigment = mix(vec3<f32>(0.92, 0.72, 0.32),
                      mix(vec3<f32>(0.95, 0.38, 0.18), vec3<f32>(0.75, 0.20, 0.10), lf / 2.0),
                      n * 0.6 + audio.y * 0.15);
    waxColor = mix(waxColor, pigment, layerThick * pigmentDeposit);
    strataMask = strataMask + layerThick;
  }

  // Viscous flow displacement
  let flow = vec2<f32>(
    noise2(uv * brushScale + vec2<f32>(time * 0.2, -time * 0.15)) - 0.5,
    noise2(uv * brushScale * 1.3 + vec2<f32>(-time * 0.1, time * 0.25)) - 0.5
  ) * meltIntensity * viscosity;
  let displacedUV = clamp(uv + flow / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let base = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

  // Impasto ridge from top strata
  let ridge = smoothstep(0.30, 0.80, strataMask) * relief;
  let normal = vec3<f32>(flow * 10.0, 1.0 - length(flow) * 5.0);
  let lightDir = normalize(vec3<f32>(0.3, 0.5, 1.0));
  let ndotl = max(dot(normalize(normal), lightDir), 0.0);

  // Subsurface scattering approximation
  let sss = smoothstep(0.15, 0.55, strataMask) * vec3<f32>(1.0, 0.45, 0.15) * 0.18 * depth;

  // Metallic pigment sparkle
  let sparkle = pow(max(hash13(vec3<f32>(uv * 90.0, time * 0.5)), 0.0), 20.0) * audio.z * relief * 2.5;

  // HDR specular on raised ridges
  let spec = pow(ndotl, 5.0) * ridge * ridge * (0.30 + audio.z * 0.6);

  // Canvas grain texture
  let canvasLarge = noise2(uv * 40.0) * 0.06;
  let canvasFine = noise2(uv * 200.0) * 0.03;
  let canvasMicro = noise2(uv * 500.0) * 0.015;
  let canvas = canvasLarge + canvasFine + canvasMicro;

  // Luminance-based bloom
  let lum = dot(base.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = smoothstep(0.55, 0.9, lum) * 0.12;

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.8, length((uv - 0.5) * vec2<f32>(aspect, 1.0))) * 0.2;

  var finalColor = base.rgb;
  finalColor = mix(finalColor, finalColor * 0.6 + waxColor * 0.65, pigmentDeposit * (0.35 + ridge));
  finalColor = finalColor + vec3<f32>(1.0, 0.96, 0.88) * spec + sss + sparkle;
  finalColor = finalColor * (1.0 + canvas) + vec3<f32>(bloom);
  finalColor = finalColor * vignette;
  finalColor = acesToneMap(finalColor);

  let waxOpacity = clamp(base.a * 0.7 + strataMask * 0.35, 0.1, 0.95);
  let finalAlpha = clamp(waxOpacity * pigmentDeposit * depth, 0.08, 0.98);
  let outDepth = clamp(mix(depth, 0.25 + ridge * 0.75, 0.25), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(ridge, pigmentDeposit, heatMouse, finalAlpha));
}
