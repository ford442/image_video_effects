// ═══════════════════════════════════════════════════════════════════
//  Gen Raptor Mini Flow
//  Category: advanced-hybrid
//  Features: generative, mouse-driven, flow-field, cellular, audio-reactive
//  Complexity: Very High
//  Chunks From: gen-raptor-mini.wgsl, conv-structure-tensor-flow.wgsl
//  Created: 2026-04-18
//  By: Agent CB-5 — Generative & Hybrid Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Predatory raptor agents navigate structure-tensor flow fields,
//  hunting along image edges and orientations. Their trails follow
//  dominant eigenvectors while audio rage pulses through the swarm.
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

// ═══ CHUNK: hash21 (from gen-raptor-mini.wgsl) ═══
fn hash21(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
  let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
  return dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

// ═══ CHUNK: structureTensor (from conv-structure-tensor-flow.wgsl) ═══
fn structureTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  let gx =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
    -2.0 * sampleLuma(uv, pixelSize, -1,  0) +
    -1.0 * sampleLuma(uv, pixelSize, -1,  1) +
     1.0 * sampleLuma(uv, pixelSize,  1, -1) +
     2.0 * sampleLuma(uv, pixelSize,  1,  0) +
     1.0 * sampleLuma(uv, pixelSize,  1,  1);

  let gy =
    -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
    -2.0 * sampleLuma(uv, pixelSize,  0, -1) +
    -1.0 * sampleLuma(uv, pixelSize,  1, -1) +
     1.0 * sampleLuma(uv, pixelSize, -1,  1) +
     2.0 * sampleLuma(uv, pixelSize,  0,  1) +
     1.0 * sampleLuma(uv, pixelSize,  1,  1);

  let Ix2 = gx * gx;
  let Iy2 = gy * gy;
  let Ixy = gx * gy;
  return vec4<f32>(Ix2, Iy2, Ixy, 0.0);
}

fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  var sum = vec4<f32>(0.0);
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      sum += structureTensor(uv + offset, pixelSize);
    }
  }
  return sum / 9.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  let coords = vec2<i32>(global_id.xy);
  if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

  let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
  let screen_uv = (vec2<f32>(coords) + 0.5) / vec2<f32>(dims);
  let pixelSize = 1.0 / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;

  // Parameters
  let turnSpeed = u.zoom_params.x;
  let maxSpeed = u.zoom_params.y;
  let rageDuration = u.zoom_params.z;
  let flowInfluence = u.zoom_params.w;

  // Audio rage mode
  let rage = bass * 3.0;

  // Compute structure tensor flow at this pixel
  let tensor = smoothTensor(screen_uv, pixelSize);
  let Jxx = tensor.x;
  let Jyy = tensor.y;
  let Jxy = tensor.z;

  let trace = Jxx + Jyy;
  let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
  let lambda1 = (trace + diff) * 0.5;
  let lambda2 = (trace - diff) * 0.5;

  // Dominant eigenvector (flow direction)
  var eigenvec = vec2<f32>(1.0, 0.0);
  if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
    eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
  }

  // Coherency: how strongly oriented
  let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);

  // Mouse target
  let mouse = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0) * vec2<f32>(f32(dims.x) / f32(dims.y), 1.0);

  // Raptor cellular simulation
  var col = vec3<f32>(0.0);
  var alpha = 0.0;

  let scale_pattern = 4.0;
  var st = uv * scale_pattern * 5.0;

  // Blend flow direction with mouse direction
  let toMouse = normalize(mouse - uv);
  let flowDir = mix(toMouse, eigenvec, flowInfluence);

  // Turn speed controls how intensely they align to flow
  let dir = mix(normalize(uv), flowDir, turnSpeed);

  // Offset cells by time and flow-driven speed
  st += dir * time * maxSpeed * (1.0 + coherency);

  let id = floor(st);
  let f = fract(st) - 0.5;

  let rng = hash21(id);
  let bodyRadius = 0.2 * (1.0 + rage * 0.5);
  let dist = length(f) - bodyRadius;
  let glow_radius = 0.15 + rageDuration * 0.3;

  if(dist < 0.0) {
    // Raptor body with flow-aligned color
    let flowAngle = atan2(eigenvec.y, eigenvec.x) * 0.15915 + 0.5;
    let flowHue = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.0)),
      0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.33)),
      0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.67))
    );
    col = flowHue * (0.5 + 0.5 * rng.x) + vec3<f32>(rage * 0.8, 0.0, 0.0);

    // Scale pattern on raptor
    let scale_tex = fract(length(f * rageDuration * 10.0));
    col *= scale_tex;
    alpha = 1.0;
  } else {
    // Trail / Background with flow-aligned glow
    let trail = mix(vec3<f32>(0.01, 0.02, 0.03), vec3<f32>(0.05, 0.1, 0.05), pow(max(0.0, 1.0 - length(uv - mouse)), 2.0));
    let glow = smoothstep(glow_radius, 0.0, dist);

    // Flow field visualization underneath
    let flowVis = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (coherency + 0.0)),
      0.5 + 0.5 * cos(6.28318 * (coherency + 0.33)),
      0.5 + 0.5 * cos(6.28318 * (coherency + 0.67))
    ) * 0.1 * coherency;

    col = mix(trail + flowVis, vec3<f32>(0.2, 0.8, 0.3), glow * 0.5);
    alpha = glow * 0.35;
  }

  textureStore(writeTexture, coords, vec4<f32>(col, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screen_uv, 0.0).r;
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
