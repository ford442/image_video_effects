// ═══════════════════════════════════════════════════════════════════
//  Hex Pulse v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Strategy: Honeycomb SDF + damped wave equation + bioluminescent glow
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: aces_tone_map ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hex SDF: distance from point to regular hexagon edge
fn hex_sdf(p: vec2<f32>, r: f32) -> f32 {
  let k = vec3<f32>(-0.8660254, 0.5, 0.5773503);
  let ap = abs(p);
  let d = dot(ap.xy, k.xy) * 2.0;
  return max(d, ap.x) - r;
}

// Hex lattice coordinates: returns cell center and local UV
fn hex_cell(uv: vec2<f32>, scale: f32) -> vec4<f32> {
  let s = vec2<f32>(1.0, 1.7320508);
  let h = s * 0.5;
  let a = fract(uv * scale / s) * s - h;
  let b = fract((uv * scale - h) / s) * s - h;
  let local = select(a, b, dot(a, a) > dot(b, b));
  let cell = uv * scale - local;
  return vec4<f32>(local, cell);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let baseSize = max(u.zoom_params.x, 0.01);
  let pulseStrength = u.zoom_params.y;
  let waveDecay = u.zoom_params.z;
  let speed = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let attenuation = mix(1.0, 0.3, depth * waveDecay);

  let aspect = resolution.x / resolution.y;
  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouseAspect = vec2<f32>(mouse.x * aspect, mouse.y);

  // Hex lattice
  let scale = baseSize * 18.0;
  let hexInfo = hex_cell(uvAspect, scale);
  let local = hexInfo.xy;
  let cellCenter = hexInfo.zw;

  // Distance from mouse to cell center (for local excitation)
  let distMouse = length(cellCenter - mouseAspect);
  let mouseExcite = exp(-distMouse * 6.0) * (1.0 + select(0.0, 2.0, u.zoom_config.w > 0.5));

  // Damped wave equation on hex lattice
  // Wave propagates from mouse outward with interference between cells
  let cellDist = length(cellCenter - mouseAspect);
  let wavePhase = time * speed * 6.28318 * (1.0 + bass * 0.4) - cellDist * scale * 2.5;
  let damping = exp(-cellDist * (1.5 + waveDecay * 3.0) * attenuation);
  let wave = sin(wavePhase) * damping * (1.0 + mouseExcite + bass * 1.5);

  // Interference from neighboring cells (approximate with second harmonic)
  let interference = sin(wavePhase * 2.0 + 1.0472) * damping * 0.35 * pulseStrength;
  let excitation = wave + interference;

  // Hex edge SDF for cell glow
  let edgeDist = hex_sdf(local, 0.45);
  let edge = 1.0 - smoothstep(0.0, 0.08, edgeDist);
  let edgeChroma = smoothstep(0.0, 0.12, edgeDist) * smoothstep(0.2, 0.0, edgeDist);

  // Chromatic dispersion at cell edges
  let rOffset = uv + vec2<f32>(edgeChroma * 0.008 / aspect, 0.0) * excitation;
  let bOffset = uv - vec2<f32>(edgeChroma * 0.008 / aspect, 0.0) * excitation;
  let colR = textureSampleLevel(readTexture, u_sampler, clamp(rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let colG = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let colB = textureSampleLevel(readTexture, u_sampler, clamp(bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  var baseColor = vec3<f32>(colR.r, colG.g, colB.b);

  // Bioluminescent cell glow
  let bioColor = vec3<f32>(0.1 + treble * 0.2, 0.55 + mids * 0.25, 0.9 + bass * 0.15);
  let cellGlow = bioColor * edge * (0.25 + abs(excitation) * 0.35);

  // HDR bloom on constructive interference nodes
  let nodeBloom = vec3<f32>(0.9, 0.85, 0.7) * max(excitation, 0.0) * max(excitation, 0.0) * 0.3 * pulseStrength;

  let combined = baseColor + cellGlow + nodeBloom;
  let finalRGB = aces_tonemap(combined * (1.0 + bass * 0.15));

  // Alpha = cell excitation × interference_amplitude × depth
  let alpha = clamp(abs(excitation) * pulseStrength * depth + edge * 0.15, 0.0, 1.0);

  let finalDepth = clamp(depth + edge * 0.04 * abs(excitation), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(excitation, edge, wave, alpha));
}
