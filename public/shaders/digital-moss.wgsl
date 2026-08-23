// ═══════════════════════════════════════════════════════════════════
//  Digital Moss — Batch 61
//  Organic moss growth on dark pixels: spring cursor, held plant/clean,
//  capped spore ripples, exact C propagation, iridescent palette, ACES.
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn mossPalette(growth: f32, t: f32, mids: f32) -> vec3<f32> {
  let healthy = vec3<f32>(0.15, 0.92, 0.32);
  let sparse = vec3<f32>(0.45, 0.78, 0.18);
  let base = mix(sparse, healthy, smoothstep(0.2, 0.85, growth));
  let irid = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (t + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.67))
  );
  return base * (0.7 + irid * 0.3) * (1.0 + mids * 0.12);
}

fn mossThickness(growth: f32, detail: f32) -> f32 {
  return mix(0.08, 0.45, growth) + detail * 0.15;
}

fn mossAlpha(growth: f32, thickness: f32, scan: f32) -> f32 {
  let growthAlpha = mix(0.42, 0.9, growth);
  let absorption = exp(-thickness * 1.4);
  let thicknessAlpha = mix(0.42, growthAlpha, absorption);
  let scanAlpha = mix(thicknessAlpha, thicknessAlpha * 0.88, scan * 0.25);
  return clamp(scanAlpha * smoothstep(0.0, 0.12, growth) + 0.18, 0.22, 0.95);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let aspect = f32(dims.x) / f32(dims.y);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let intensity = u.zoom_params.x;
  let growSpeed = u.zoom_params.y * (1.0 + bass * 0.25);
  let mossScale = mix(280.0, 720.0, u.zoom_params.z);
  let detail = u.zoom_params.w;

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

  let oldState = textureLoad(dataTextureC, coord, 0).r;
  let seed = hash12(uv + vec2<f32>(time * 0.1, time * 0.05));
  var grown = oldState;

  let spawnChance = 0.995 - intensity * 0.08 - treble * 0.01;
  if (luma < mix(0.22, 0.12, intensity) && seed > spawnChance) {
    grown = 1.0;
  }

  if (grown < 0.92) {
    let angle = hash12(uv * 10.0 + time) * 6.28;
    let offset = vec2<i32>(i32(cos(angle) * 2.0), i32(sin(angle) * 2.0));
    let neighborState = textureLoad(
      dataTextureC,
      clamp(coord + offset, vec2<i32>(0), dims - vec2<i32>(1)),
      0
    ).r;
    if (neighborState > 0.5 && luma < mix(0.5, 0.32, intensity)) {
      grown = min(1.0, grown + 0.05 * growSpeed);
    }
  }

  if (luma > mix(0.55, 0.68, intensity)) {
    grown *= 0.9;
  }

  let pAspect = vec2<f32>(uv.x * aspect, uv.y);
  let mAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let mDist = length(pAspect - mAspect);
  let brushRadius = mix(0.04, 0.08, intensity) * select(1.0, 1.35, held);
  let mouseInfluence = smoothstep(brushRadius, 0.0, mDist);

  if (held) {
    grown = min(1.0, grown + mouseInfluence * 0.18 * intensity);
  } else if (u.zoom_config.w > 0.0) {
    grown = max(0.0, grown - mouseInfluence);
  }

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.4) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let spore = smoothstep(0.1, 0.0, rDist) * (1.0 - age * 0.75);
      grown = min(1.0, grown + spore * 0.35 * intensity);
    }
  }

  textureStore(dataTextureA, coord, vec4<f32>(grown, mouseInfluence, detail, 1.0));

  let thickness = mossThickness(grown, detail);
  let scan = 0.82 + 0.18 * sin(uv.y * mossScale + time * 2.0);
  let lightExposure = 1.0 - luma;
  let mossColor = mossPalette(grown, time * 0.04 + uv.x * 2.0, mids) * (1.0 + lightExposure * 0.25);
  let scannedMossColor = mossColor * scan;
  let mossMix = grown * mossAlpha(grown, thickness, scan);
  var finalColor = mix(imgColor, scannedMossColor, mossMix);
  finalColor = acesToneMap(finalColor * (0.95 + bass * 0.06));
  let alpha = clamp(mix(1.0, mossAlpha(grown, thickness, scan), grown), 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
