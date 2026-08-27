// Cyber Hex Armor — articulated plates, beveled seams, and audio-routed circuit traffic.
// A/C stores tone-mapped display RGBA. B and extraBuffer are unused.
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

fn hexCoords(p: vec2<f32>) -> vec4<f32> {
  let r = vec2<f32>(1.0, 1.7320508);
  let h = r * 0.5;
  let a = p - floor(p / r + 0.5) * r;
  let b = p - (floor((p - h) / r + 0.5) * r + h);
  let local = select(b, a, dot(a, a) < dot(b, b));
  return vec4<f32>(local, p - local);
}

fn hexDistance(p: vec2<f32>) -> f32 {
  let q = abs(p);
  return max(q.x * 0.8660254 + q.y * 0.5, q.y);
}

fn safeCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, safeCoord(uv, resolution), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let p = (uv - 0.5) * aspectVec;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let scale = mix(10.0, 58.0, u.zoom_params.x);
  let glowIntensity = mix(0.2, 2.8, u.zoom_params.y) * (1.0 + treble * 0.38);
  let revealRadius = mix(0.06, 0.58, u.zoom_params.z);
  let border = mix(0.018, 0.15, u.zoom_params.w);
  let mouseP = (mouse - 0.5) * aspectVec;

  var clickWave = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.8) {
      let rd = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.3 + bass * 0.1);
      clickWave += sin((rd - front) * 52.0) * exp(-abs(rd - front) * 28.0) * exp(-age * 1.05);
    }
  }

  let pointerDist = length(p - mouseP);
  let hover = smoothstep(revealRadius, 0.0, pointerDist);
  let heldRetract = hover * select(0.38, 1.0, held);
  let warpedP = p + normalize(p - mouseP + vec2<f32>(0.0001, 0.0)) * (heldRetract * 0.055 + clickWave * 0.018);
  let hc = hexCoords(warpedP * scale);
  let local = hc.xy;
  let id = hc.zw;
  let cellJitter = hash12(id);
  let platePhase = clamp(heldRetract + abs(clickWave) * 0.35 + bass * 0.04, 0.0, 1.0);
  let plateRadius = 0.49 * (1.0 - platePhase * (0.62 + cellJitter * 0.2));
  let distanceToEdge = hexDistance(local);
  let plate = 1.0 - smoothstep(plateRadius - 0.018, plateRadius + 0.018, distanceToEdge);
  let seam = exp(-abs(distanceToEdge - plateRadius) / max(border, 0.003)) * (1.0 - platePhase * 0.45);
  let bevel = smoothstep(plateRadius - border * 2.2, plateRadius - border * 0.3, distanceToEdge) * plate;

  let circuitA = 1.0 - smoothstep(0.025, 0.075, abs(local.x + local.y * 0.58));
  let circuitB = 1.0 - smoothstep(0.02, 0.06, abs(local.y - local.x * 0.58));
  let circuitMask = max(circuitA, circuitB) * plate * step(0.37, cellJitter);
  let trafficPhase = id.x * 0.83 + id.y * 1.17 - time * (3.0 + mids * 4.0) + local.x * 8.0;
  let traffic = pow(0.5 + 0.5 * sin(trafficPhase), 14.0) * circuitMask;
  let scan = pow(0.5 + 0.5 * cos(local.y * 22.0 - time * (2.0 + treble * 4.0) + pointerDist * 10.0), 12.0) * plate;

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let history = historyAt(uv - normalize(p - mouseP + vec2<f32>(0.0001, 0.0)) / aspectVec * clickWave * 0.003, resolution);
  let alloy = mix(vec3<f32>(0.025, 0.045, 0.07), vec3<f32>(0.13, 0.19, 0.25), bevel + cellJitter * 0.18);
  let trafficColor = mix(vec3<f32>(0.05, 1.25, 1.8), vec3<f32>(1.5, 0.15, 0.92), 0.5 + 0.5 * sin(cellJitter * 9.0 + time * 0.2));
  var hdr = mix(source.rgb, alloy, plate * (0.72 - heldRetract * 0.18));
  hdr += vec3<f32>(0.03, 0.78, 1.3) * seam * glowIntensity * (0.35 + bass * 0.28);
  hdr += trafficColor * traffic * glowIntensity * (0.45 + mids * 0.4);
  hdr += vec3<f32>(0.45, 0.78, 1.4) * scan * glowIntensity * (0.08 + treble * 0.18);
  hdr = mix(hdr, history.rgb, clamp(0.025 + seam * 0.07 + traffic * 0.05, 0.0, 0.12));
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let armorAlpha = clamp(plate * 0.68 + seam * 0.28 + traffic * 0.25, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * armorAlpha, 0.0, 1.0);
  let result = vec4<f32>(display, alpha);

  textureStore(dataTextureA, coord, result);
  textureStore(writeTexture, coord, result);
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
