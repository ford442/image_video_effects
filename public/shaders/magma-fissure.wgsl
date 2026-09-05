// Magma Fissure — branching thermal cracks, crust cooling, and refractive heat haze.
// A/C packing remains [heat, 0, 0, 1]. B and extraBuffer are unused.
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

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0)), w.x), w.y);
}

fn heatAt(coord: vec2<i32>, dims: vec2<i32>) -> f32 {
  return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
}

fn magmaPalette(t: f32, treble: f32) -> vec3<f32> {
  let cool = vec3<f32>(0.16, 0.012, 0.004);
  let ember = vec3<f32>(1.35, 0.09 + treble * 0.05, 0.01);
  let molten = vec3<f32>(2.8, 0.72, 0.08);
  let whiteHot = vec3<f32>(3.4, 2.25, 0.9);
  let low = mix(cool, ember, smoothstep(0.02, 0.45, t));
  let high = mix(molten, whiteHot, smoothstep(0.72, 1.0, t));
  return mix(low, high, smoothstep(0.42, 0.84, t));
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

  let cooling = clamp(u.zoom_params.x, 0.9, 0.9995);
  let fissureWidth = mix(0.025, 0.24, u.zoom_params.y);
  let haze = mix(0.0, 0.035, u.zoom_params.z) * (1.0 + treble * 0.5);
  let brushRadius = mix(0.025, 0.22, u.zoom_params.w);

  let centerHeat = heatAt(coord, dims);
  let heatL = heatAt(coord + vec2<i32>(-1, 0), dims);
  let heatR = heatAt(coord + vec2<i32>(1, 0), dims);
  let heatT = heatAt(coord + vec2<i32>(0, -1), dims);
  let heatB = heatAt(coord + vec2<i32>(0, 1), dims);
  let neighborMean = (heatL + heatR + heatT + heatB) * 0.25;
  let heatGradient = vec2<f32>(heatR - heatL, heatB - heatT);

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let brush = smoothstep(brushRadius, brushRadius * 0.12, pointerDist);
  let hoverBranch = pow(max(0.0, 0.5 + 0.5 * sin(atan2(pointerDelta.y, pointerDelta.x) * (5.0 + u.zoom_params.y * 7.0)
                         + pointerDist * 92.0 - noise(floor(uv * 48.0)) * 8.0)), 7.0) * brush;
  let heldHeat = select(brush * 0.08, max(brush * 0.78, hoverBranch), held);

  var clickHeat = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.6) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.22 + bass * 0.12);
      let shell = exp(-abs(rd - front) * (38.0 + u.zoom_params.y * 30.0));
      let angular = 0.55 + 0.45 * noise((uv - ripple.xy) * 75.0 + vec2<f32>(age * 4.0, -age * 2.0));
      clickHeat += shell * angular * exp(-age * 1.1);
    }
  }

  let branchNoise = noise(uv * vec2<f32>(58.0, 31.0) + vec2<f32>(time * 0.18, -time * 0.34));
  let branching = smoothstep(0.78 - fissureWidth * 0.42, 0.91, branchNoise + neighborMean * 0.24 + bass * 0.025);
  let diffusion = mix(centerHeat, neighborMean, 0.045 + fissureWidth * 0.18 + mids * 0.025);
  let retained = diffusion * cooling;
  let injected = max(heldHeat * (0.72 + bass * 0.25), clickHeat * (0.82 + bass * 0.3));
  let newHeat = clamp(max(retained, max(injected, branching * neighborMean * 0.985)), 0.0, 1.0);

  let flow = normalize(heatGradient + vec2<f32>(0.0001, 0.0));
  let shimmer = vec2<f32>(-flow.y, flow.x) * sin(time * (4.0 + treble * 3.0) + branchNoise * 9.0);
  let distortedUV = clamp(uv + (flow * (newHeat - neighborMean) + shimmer * newHeat) * haze, vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);
  let crack = smoothstep(max(0.05, 0.64 - fissureWidth), 0.9, newHeat);
  let crust = smoothstep(0.08, 0.42 + fissureWidth * 0.2, newHeat) * (1.0 - crack);
  let magma = magmaPalette(newHeat, treble) * (0.72 + bass * 0.5 + mids * newHeat * 0.25);
  var hdr = source.rgb * (1.0 - crust * 0.72);
  hdr = mix(hdr, magma, clamp(crust * 0.55 + crack * 0.92, 0.0, 1.0));
  hdr += magma * crack * (0.35 + mids * 0.45);
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let alpha = clamp(source.a + (1.0 - source.a) * smoothstep(0.05, 0.65, newHeat), 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(newHeat, 0.0, 0.0, 1.0));
  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
