// ═══════════════════════════════════════════════════════════════════
//  Cyber Ripples
//  Category: interactive-mouse
//  Features: mouse-driven, wave, neon, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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

const QUANT_STEP: f32 = 24.0;
const ATTEN_SCALE: f32 = 5.0;
const DISP_AMP: f32 = 0.01;
const EPS: f32 = 0.001;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) {
    return;
  }

  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Audio reactivity: bass drives ripple intensity, mids add warmth, treble sharpens edges
  let audioBoost = 1.0 + bass * 0.5 + mids * 0.2;
  let sparkle = treble * 0.15;

  // Param unpack
  let speed = u.zoom_params.x * 5.0 + 1.0;
  let blockSize = u.zoom_params.y * 0.1;
  let aberration = u.zoom_params.z * 0.05;
  let frequency = u.zoom_params.w * 50.0 + 10.0;

  // Mouse-driven ripple origin
  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  // Radial distance and normalized direction
  let delta = uvCorrected - mouseCorrected;
  let dist = length(delta);
  let dir = delta / max(dist, 1e-6);

  // Quantized digital wave — adaptive step reduces moiré shimmer
  let quant = floor(dist * QUANT_STEP) / QUANT_STEP;
  let wave = sin(quant * frequency - time * speed);

  // Attenuate and displace radially from cursor
  let strength = 1.0 / (dist * ATTEN_SCALE + 0.5);
  let displacement = dir * wave * strength * DISP_AMP * audioBoost;
  var displacedUV = uv + displacement;

  // Branchless pixelation: mix() + step() replaces per-pixel if
  let activePixel = step(EPS, blockSize);
  let blocks = 1.0 / max(blockSize, EPS);
  let pixelated = floor(displacedUV * blocks) / blocks;
  displacedUV = mix(displacedUV, pixelated, activePixel);

  // Clamp displaced UVs before sampling
  displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));

  // Anti-moiré LOD bias: higher lod when displacement magnitude is large
  let lod = clamp(length(displacement) * resolution.x * 0.25, 0.0, 2.0);

  // 2-sample chromatic aberration
  let offset = vec2<f32>(aberration, 0.0);
  let sR = textureSampleLevel(readTexture, u_sampler, displacedUV + offset, lod);
  let sB = textureSampleLevel(readTexture, u_sampler, displacedUV - offset, lod);

  // Reconstruct green from both taps for a balanced chromatic split
  let r = sR.r;
  let g = mix(sR.g, sB.g, 0.5);
  let b = sB.b;

  var color = vec3<f32>(r, g, b);

  // Treble sparkle on highlights
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = color + vec3<f32>(sparkle * luma);

  // Semantic alpha: effect strength fades with distance and displacement magnitude
  let effectStrength = clamp(strength * 2.0 + length(displacement) * 50.0 + luma * 0.3, 0.0, 1.0);
  let alpha = clamp(mix(0.5, 1.0, effectStrength), 0.0, 1.0);

  let finalColor = vec4<f32>(color, alpha);

  // Pass-through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
