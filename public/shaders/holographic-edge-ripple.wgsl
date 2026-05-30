// ═══════════════════════════════════════════════════════════════════
//  Holographic Edge Ripple v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: edge-detect, holographic-foil, damped-wave
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
  zoom_params: vec4<f32>,  // x=EdgeThreshold, y=RippleSpeed, z=RippleDamping, w=HolographicShift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

// ═══ CHUNK: aces_tonemap (standard) ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 2.51 + 0.03);
  let b = x * (x * 2.43 + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: hash21 ═══
fn hash21(p: vec2<f32>) -> f32 {
  let q = fract(p * vec2(123.34, 456.21));
  return fract(dot(q, vec2(12.9898, 78.233)));
}

// ═══ CHUNK: sampleLuma ═══
fn sampleLuma(uv: vec2<f32>) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  return dot(c, vec3(0.299, 0.587, 0.114));
}

// ═══ CHUNK: laplacian_edge_sdf ═══
fn laplacianEdge(uv: vec2<f32>, ps: vec2<f32>) -> f32 {
  let c = sampleLuma(uv);
  let l = sampleLuma(uv + vec2(-ps.x, 0.0));
  let r = sampleLuma(uv + vec2( ps.x, 0.0));
  let u = sampleLuma(uv + vec2(0.0, -ps.y));
  let d = sampleLuma(uv + vec2(0.0,  ps.y));
  let lap = abs(l + r + u + d - 4.0 * c);
  let dx = r - l;
  let dy = d - u;
  let gradMag = length(vec2(dx, dy));
  let zeroCross = smoothstep(0.02, 0.08, lap) * smoothstep(0.01, 0.06, gradMag);
  return zeroCross;
}

// ═══ CHUNK: sobel_gradient ═══
fn sobelGradient(uv: vec2<f32>, ps: vec2<f32>) -> vec2<f32> {
  let tl = sampleLuma(uv + vec2(-ps.x, -ps.y));
  let tc = sampleLuma(uv + vec2( 0.0, -ps.y));
  let tr = sampleLuma(uv + vec2( ps.x, -ps.y));
  let cl = sampleLuma(uv + vec2(-ps.x,  0.0));
  let cr = sampleLuma(uv + vec2( ps.x,  0.0));
  let bl = sampleLuma(uv + vec2(-ps.x,  ps.y));
  let bc = sampleLuma(uv + vec2( 0.0,  ps.y));
  let br = sampleLuma(uv + vec2( ps.x,  ps.y));
  let gx = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
  let gy = -tl - 2.0 * cl - bl + tr + 2.0 * cr + br;
  return vec2(gx, gy);
}

// ═══ CHUNK: holographic_diffraction ═══
fn diffractionHue(theta: f32, shift: f32) -> vec3<f32> {
  let p = theta * 3.0 + shift * TAU;
  return 0.5 + 0.5 * sin(vec3(p, p + 2.094, p + 4.188));
}

// ═══ CHUNK: fresnel_iridescence ═══
fn fresnelIridescence(cosTheta: f32, shift: f32) -> vec3<f32> {
  let f0 = 0.04;
  let fresnel = f0 + (1.0 - f0) * pow(1.0 - abs(cosTheta), 5.0);
  let hue = diffractionHue(acos(abs(cosTheta)) * 2.0, shift);
  return hue * fresnel * 2.0;
}

// ═══ CHUNK: damped_wave ═══
fn dampedWave(edgeConf: f32, time: f32, speed: f32, damp: f32, bass: f32, attract: f32) -> f32 {
  let freq = edgeConf * 40.0 + 10.0;
  let phase = time * speed * (1.0 + bass * 0.5);
  let envelope = exp(-damp * 3.0) * (1.0 + bass * 0.6) * attract;
  return sin(freq - phase) * envelope;
}

// ═══ CHUNK: depth_layer_separation ═══
fn depthLayerSeparation(depth: f32, baseSep: f32, shift: f32) -> vec3<f32> {
  let layer1 = diffractionHue(depth * 2.0 + shift, shift);
  let layer2 = diffractionHue(depth * 3.0 - shift * 0.5, shift + 0.3);
  let mixFactor = smoothstep(0.3, 0.7, depth);
  return mix(layer1, layer2, mixFactor);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let ps = 1.0 / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let edgeThreshold = u.zoom_params.x * 0.5 + 0.05;
  let rippleSpeed = u.zoom_params.y * 5.0;
  let rippleDamp = u.zoom_params.z * 0.8 + 0.1;
  let holoShift = u.zoom_params.w * 2.0;

  let edgeConf = laplacianEdge(uv, ps);
  let edgeMask = smoothstep(edgeThreshold * 0.3, edgeThreshold, edgeConf);

  let grad = sobelGradient(uv, ps);
  let edgeNormal = normalize(vec3(grad.x, grad.y, 0.05));

  let aspect = resolution.x / resolution.y;
  let mouseDist = length((uv - mouse) * vec2(aspect, 1.0));
  let mouseAttract = exp(-mouseDist * 4.0);

  let wave = dampedWave(edgeConf, time, rippleSpeed, rippleDamp, bass, mouseAttract);

  let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let bgLuma = dot(bg.rgb, vec3(0.299, 0.587, 0.114));

  let viewDir = normalize(vec3(uv - 0.5, 1.0));
  let cosTheta = dot(edgeNormal, viewDir);

  let holo = fresnelIridescence(cosTheta, holoShift + time * 0.1 + edgeConf * 2.0);
  let depthSep = depth * 0.3 + 0.1;
  let diffraction = holo * edgeMask * (1.0 + wave * 0.5) * depthSep;

  let displacedUV = uv + edgeNormal.xy * wave * 0.02 * edgeMask;
  let displaced = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  let secondaryRipple = sin(edgeConf * 80.0 + time * rippleSpeed * 1.3) * 0.3 * edgeMask * mouseAttract;
  let caustic = max(0.0, secondaryRipple) * diffractionHue(edgeConf * 6.0, holoShift) * 0.5;

  let layeredHolo = depthLayerSeparation(depth, depthSep, holoShift);
  let layerMix = layeredHolo * edgeMask * 0.3 * (1.0 + bass * 0.3);

  let grain = hash21(uv * 500.0 + time) * 0.03 * edgeMask;
  let emission = mix(bg.rgb, displaced, edgeMask * 0.35)
               + diffraction * (0.6 + bass * 0.4)
               + caustic
               + layerMix
               + grain;
  let tonemapped = aces_tonemap(emission);

  var alpha = edgeMask * length(diffraction) * 2.5;
  alpha = clamp(alpha + bg.a * (1.0 - edgeMask) * 0.25, 0.0, 1.0);

  let outCol = vec4(tonemapped, alpha);
  textureStore(writeTexture, vec2<i32>(global_id.xy), outCol);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), outCol);
}
