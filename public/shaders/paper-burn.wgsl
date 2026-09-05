// Paper Burn — fibrous thermal diffusion, char curl, and drifting ember fronts.
// A/C packing remains [burn state, 0, 0, 1]. B and extraBuffer are unused.
// Premium mixed-eight upgrade: 2026-08-27.

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn burnAt(coord: vec2<i32>, dims: vec2<i32>) -> f32 {
  return clamp(textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0).r, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let dims = vec2<i32>(resolution);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let burnSpeed = mix(0.0015, 0.035, u.zoom_params.x) * (1.0 + bass * 0.55);
  let spread = mix(0.025, 0.34, u.zoom_params.y) * (1.0 + mids * 0.18);
  let charWidth = mix(0.025, 0.28, u.zoom_params.z);
  let reset = u.zoom_params.w > 0.5;

  let center = burnAt(coord, dims);
  let left = burnAt(coord + vec2<i32>(-1, 0), dims);
  let right = burnAt(coord + vec2<i32>(1, 0), dims);
  let top = burnAt(coord + vec2<i32>(0, -1), dims);
  let bottom = burnAt(coord + vec2<i32>(0, 1), dims);
  let diag0 = burnAt(coord + vec2<i32>(-1, -1), dims);
  let diag1 = burnAt(coord + vec2<i32>(1, -1), dims);
  let diag2 = burnAt(coord + vec2<i32>(-1, 1), dims);
  let diag3 = burnAt(coord + vec2<i32>(1, 1), dims);
  let axial = (left + right + top + bottom) * 0.25;
  let diagonal = (diag0 + diag1 + diag2 + diag3) * 0.25;

  let fiberCell = floor(uv * vec2<f32>(resolution.x * 0.22, resolution.y * 0.055));
  let fiberNoise = hash12(fiberCell);
  let grain = 0.5 + 0.5 * sin(uv.x * resolution.x * 0.31 + uv.y * 47.0 + fiberNoise * 9.0);
  let fiberBias = mix(0.72, 1.28, grain) * (0.9 + treble * 0.08);
  let neighbor = mix(axial, diagonal, 0.22 + grain * 0.2);
  let diffusion = center + (neighbor - center) * spread * fiberBias;
  let liveEdge = smoothstep(0.03, 0.62, neighbor) * (1.0 - smoothstep(0.72, 0.98, center));

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let pointerFiber = pow(max(0.0, 0.5 + 0.5 * sin(atan2(pointerDelta.y, pointerDelta.x) * 11.0 + pointerDist * 130.0)), 6.0);
  let pointerMask = smoothstep(0.095, 0.008, pointerDist) * mix(0.1, 1.0, select(0.0, 1.0, held));
  let pointerIgnition = pointerMask * mix(0.55, 1.0, pointerFiber);

  var clickIgnition = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.0) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.15 + bass * 0.07);
      let emberFront = exp(-abs(rd - front) * 54.0) * exp(-age * 0.82);
      clickIgnition += emberFront * (0.68 + 0.32 * hash12(floor(uv * 160.0) + f32(i)));
    }
  }

  var burn = clamp(diffusion + liveEdge * burnSpeed * fiberBias + max(pointerIgnition, clickIgnition) * burnSpeed * 5.0, 0.0, 1.0);
  if (reset) { burn = 0.0; }

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let frontCenter = 0.48 + grain * 0.07;
  let emberBand = smoothstep(frontCenter - charWidth, frontCenter, burn) * (1.0 - smoothstep(frontCenter, frontCenter + charWidth * 0.55, burn));
  let charBand = smoothstep(0.08, max(0.1, frontCenter - charWidth * 0.35), burn) * (1.0 - smoothstep(frontCenter + charWidth * 0.25, 0.96, burn));
  let hole = smoothstep(frontCenter + charWidth * 0.35, min(0.99, frontCenter + charWidth + 0.14), burn);
  let ashFiber = pow(grain, 5.0) * charBand;
  let emberColor = vec3<f32>(2.8 + bass, 0.38 + mids * 0.22, 0.018 + treble * 0.035);
  let charColor = mix(vec3<f32>(0.055, 0.018, 0.006), vec3<f32>(0.24, 0.075, 0.012), ashFiber);
  var hdr = mix(source.rgb, charColor, clamp(charBand + hole * 0.88, 0.0, 1.0));
  hdr += emberColor * emberBand * (0.62 + mids * 0.65 + clickIgnition * 0.4);
  hdr += vec3<f32>(0.32, 0.12, 0.025) * ashFiber * treble;
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let alpha = clamp(source.a * (1.0 - hole), 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(burn, 0.0, 0.0, 1.0));
  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
