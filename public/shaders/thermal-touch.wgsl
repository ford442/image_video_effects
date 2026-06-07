// ═══════════════════════════════════════════════════════════════════
//  Thermal Touch v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Chunks From: heat-diffusion, blackbody-radiation, feedback-loop
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
  zoom_params: vec4<f32>,  // x=HeatIntensity, y=Radius, z=AmbientTemp, w=CoolingRate
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: aces_tonemap (standard) ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: blackbody_radiation ═══
fn blackbodyColor(t: f32) -> vec3<f32> {
  let v = clamp(t, 0.0, 1.0);
  let s1 = smoothstep(0.00, 0.15, v);
  let s2 = smoothstep(0.15, 0.30, v);
  let s3 = smoothstep(0.30, 0.50, v);
  let s4 = smoothstep(0.50, 0.70, v);
  let s5 = smoothstep(0.70, 0.85, v);
  let s6 = smoothstep(0.85, 1.00, v);
  var c = mix(vec3(0.0, 0.0, 0.0), vec3(0.1, 0.0, 0.15), s1);
  c = mix(c, vec3(0.4, 0.0, 0.0), s2);
  c = mix(c, vec3(0.8, 0.1, 0.0), s3);
  c = mix(c, vec3(1.0, 0.4, 0.0), s4);
  c = mix(c, vec3(1.0, 0.8, 0.1), s5);
  c = mix(c, vec3(1.0, 1.0, 0.9), s6);
  return c;
}

// ═══ CHUNK: local_glow ═══
fn localGlow(heat: f32) -> vec3<f32> {
  let h1 = blackbodyColor(clamp(heat + 0.05, 0.0, 1.0));
  let h2 = blackbodyColor(clamp(heat + 0.15, 0.0, 1.0));
  let h3 = blackbodyColor(clamp(heat + 0.25, 0.0, 1.0));
  return (h1 * 0.2 + h2 * 0.12 + h3 * 0.06) * heat * heat;
}

// ═══ CHUNK: gaussian_blur_approx ═══
fn sampleHeat(uv: vec2<f32>) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  return dot(c, vec3(0.299, 0.587, 0.114));
}

fn diffuseHeat(uv: vec2<f32>, ps: vec2<f32>) -> f32 {
  let c = sampleHeat(uv);
  let l = sampleHeat(uv + vec2(-ps.x, 0.0));
  let r = sampleHeat(uv + vec2( ps.x, 0.0));
  let u = sampleHeat(uv + vec2(0.0, -ps.y));
  let d = sampleHeat(uv + vec2(0.0,  ps.y));
  let diag = 0.25 * (
    sampleHeat(uv + vec2(-ps.x, -ps.y)) +
    sampleHeat(uv + vec2( ps.x, -ps.y)) +
    sampleHeat(uv + vec2(-ps.x,  ps.y)) +
    sampleHeat(uv + vec2( ps.x,  ps.y))
  );
  return c * 0.25 + (l + r + u + d) * 0.125 + diag;
}

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  let q = fract(p * vec2(123.34, 456.21));
  return fract(dot(q, vec2(12.9898, 78.233)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let time = u.config.x;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let ps = 1.0 / resolution;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let clickBoost = select(1.0, 1.8, mouseDown);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let heatIntensity = mix(0.1, 2.5, u.zoom_params.x) * (1.0 + bass * 0.4);
  let radius = mix(0.03, 0.5, u.zoom_params.y) * clickBoost;
  let ambientTemp = u.zoom_params.z;
  let coolingRate = u.zoom_params.w * 0.5 + 0.05;

  let aspect = resolution.x / resolution.y;
  let distVec = (uv - mouse) * vec2(aspect, 1.0);
  let dist = length(distVec);

  let pulse = sin(time * (2.0 + bass * 6.0)) * 0.5 + 0.5;
  let mouseHeat = (1.0 - smoothstep(0.0, radius, dist)) * heatIntensity * (0.8 + pulse * 0.2);

  let prevHeat = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;
  let diffused = diffuseHeat(uv, ps);
  let cooling = prevHeat * exp(-coolingRate * 0.1);
  let heatTransfer = mix(0.02, 0.08, depth);

  let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
  let baseHeat = luma * 0.3;

  let shimmer = hash21(uv * 200.0 + time * (2.0 + mids * 10.0)) * 0.04 * (1.0 + mids * 2.0);

  let trailHeat = textureSampleLevel(dataTextureC, u_sampler, uv + vec2(0.0, ps.y), 0.0).r * 0.5;
  let trailBlend = mix(baseHeat + mouseHeat + shimmer, trailHeat, 0.15 * (1.0 - mouseHeat));

  var heat = baseHeat + mouseHeat + shimmer + cooling * heatTransfer + diffused * 0.15;
  heat = mix(heat, trailBlend, select(0.0, 0.3, mouseDown));
  heat = mix(heat, ambientTemp, 0.3 * select(0.0, 1.0, ambientTemp > 0.0));

  let ambientHeating = bass * 0.05 * (1.0 - smoothstep(0.0, 0.5, dist));
  heat = heat + ambientHeating;
  heat = clamp(heat, 0.0, 1.0);

  let thermalColor = blackbodyColor(heat);
  let glow = localGlow(heat);

  let finalColor = thermalColor + glow;
  let tonemapped = aces_tonemap(finalColor);

  let alpha = clamp(heat * 1.2, 0.0, 1.0);
  let outCol = vec4(tonemapped, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), outCol);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), outCol);
}
