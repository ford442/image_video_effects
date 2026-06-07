// ═══════════════════════════════════════════════════════════════════
//  Luma Magnetism v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: field-sim, runge-kutta, iron-filings
//  Created: 2026-05-30
//  By: 4-Agent Upgrade Swarm
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
  zoom_params: vec4<f32>,  // x=FieldStrength, y=Radius, z=FilamentDensity, w=DepthLayer
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;

// ═══ CHUNK: aces_tonemap (standard) ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// ═══ CHUNK: sample_luma_polarity ═══
fn sampleLuma(uv: vec2<f32>) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  return dot(c, vec3(0.299, 0.587, 0.114));
}

// ═══ CHUNK: magnetic_field_rk2 ═══
fn magneticField(pos: vec2<f32>, mouse: vec2<f32>, strength: f32, bass: f32) -> vec2<f32> {
  let ps = vec2(0.003, 0.003);
  let l = sampleLuma(pos + vec2(-ps.x, 0.0));
  let r = sampleLuma(pos + vec2( ps.x, 0.0));
  let u = sampleLuma(pos + vec2(0.0, -ps.y));
  let d = sampleLuma(pos + vec2(0.0,  ps.y));
  let grad = vec2(r - l, d - u) * 10.0;

  let mouseDelta = pos - mouse;
  let mouseDist = length(mouseDelta);
  let mouseField = vec2(-mouseDelta.y, mouseDelta.x) * strength * (1.0 + bass)
                 / max(mouseDist * mouseDist, 0.0001);
  return grad + mouseField;
}

fn rk2Step(pos: vec2<f32>, mouse: vec2<f32>, strength: f32, bass: f32, dt: f32) -> vec2<f32> {
  let k1 = magneticField(pos, mouse, strength, bass);
  let k2 = magneticField(pos + k1 * dt * 0.5, mouse, strength, bass);
  return pos + k2 * dt;
}

// ═══ CHUNK: field_line_density ═══
fn fieldLineDensity(uv: vec2<f32>, mouse: vec2<f32>, strength: f32, bass: f32, steps: i32) -> f32 {
  var pos = uv;
  var density = 0.0;
  for (var i: i32 = 0; i < steps; i = i + 1) {
    let f = magneticField(pos, mouse, strength, bass);
    pos = pos + f * 0.003;
    let l = sampleLuma(pos);
    density = density + l * 0.1;
    if (length(pos - uv) > 0.3) { break; }
  }
  return density;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let fieldStrength = u.zoom_params.x * 2.0 * (1.0 + bass * 0.5);
  let radius = max(u.zoom_params.y, 0.01);
  let filamentDensity = u.zoom_params.z * 5.0 + 1.0;
  let depthLayer = u.zoom_params.w;

  let aspect = resolution.x / resolution.y;
  let diff = uv - mouse;
  let dist = length(vec2(diff.x * aspect, diff.y));

  let luma = sampleLuma(uv);
  let polarity = (luma - 0.5) * 2.0;

  let field = magneticField(uv, mouse, fieldStrength, bass);
  let fieldMag = length(field);

  let lineDensity = fieldLineDensity(uv, mouse, fieldStrength, bass, 8);
  let filament = smoothstep(0.5, 0.0, abs(sin(lineDensity * filamentDensity * PI + depth * 6.2831853)))
               * smoothstep(radius, 0.0, dist);

  let filingColor = vec3(0.15, 0.12, 0.10);
  let northColor = vec3(0.8, 0.2, 0.1);
  let southColor = vec3(0.1, 0.3, 0.8);
  let polarityColor = mix(southColor, northColor, polarity * 0.5 + 0.5);

  let bloom = fieldMag * 0.15 * smoothstep(radius, 0.0, dist);
  let hdrBloom = polarityColor * bloom * (1.0 + bass * 0.3);

  let filingGlow = filingColor * filament * 2.0;

  let displacedUV = uv + normalize(field) * fieldMag * 0.01 * smoothstep(radius, 0.0, dist);
  let displaced = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  let depthFade = mix(0.6, 1.0, depth * depthLayer);
  let emission_base = mix(displaced, polarityColor, filament * 0.4) + hdrBloom + filingGlow;
  var emission = emission_base * depthFade;
  let tonemapped = aces_tonemap(emission);

  let noise = hash21(uv * 400.0) * 0.03;
  let alpha = clamp(filament * depth * 2.0 + bloom * depth * 3.0 + noise, 0.0, 1.0);
  let outCol = vec4(tonemapped, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), outCol);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), outCol);
}
