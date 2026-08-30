// ═══════════════════════════════════════════════════════════════════
//  Mandelbrot Zoom Portal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: ACES display RGBA
//  Motion: nested zoom-burst packets + orbital pointer spin
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

const TAU: f32 = 6.28318530718;

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(TAU * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn mandelbrot(c: vec2<f32>, maxIter: i32) -> vec2<f32> {
  var z = vec2<f32>(0.0);
  var i = 0;
  for (; i < maxIter; i = i + 1) {
    if (dot(z, z) > 4.0) { break; }
    z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
  }
  let smoothI = select(f32(i), f32(i) - log2(log2(max(dot(z, z), 1.0001))) + 4.0, dot(z, z) > 1.0);
  return vec2<f32>(smoothI, f32(maxIter));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[3].z;
  let binB = plasmaBuffer[6].x;

  var spring = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 7.5;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-2.0), vec2<f32>(2.0));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
  }

  let zoomLevel = mix(0.5, 4.0, u.zoom_params.x);
  let maxIterBase = i32(mix(24.0, 96.0, u.zoom_params.y));
  let paletteSpeed = u.zoom_params.z * 2.0;
  let portalBlend = u.zoom_params.w;

  let orbit = time * (0.55 + mids * 0.4);
  let spinUv = rotate((uv - spring) * vec2<f32>(aspect, 1.0), orbit * 0.35 + bass * 0.15);
  let viewUv = spring + vec2<f32>(spinUv.x / aspect, spinUv.y);

  let burst = 0.12 * sin(time * 2.8 + length(spinUv) * 14.0) * (1.0 + bass * 0.5);
  let holdZoom = select(0.0, 0.45, held);
  let baseScale = exp2(-zoomLevel - holdZoom + burst);
  let baseCenter = vec2<f32>((spring.x - 0.5) * 3.0 - 0.5, (spring.y - 0.5) * 2.5);
  let baseCoord = baseCenter + (viewUv - 0.5) * vec2<f32>(baseScale * aspect, baseScale);

  let baseResult = mandelbrot(baseCoord, maxIterBase);
  let baseIter = baseResult.x;
  let paletteT = fract(baseIter / 50.0 + time * paletteSpeed * 0.1 + binA * 0.05);
  var mandelColor = palette(paletteT, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 0.9, 0.75), vec3<f32>(0.0, 0.33, 0.67));
  let insideSet = baseIter >= baseResult.y - 0.5;
  var finalColor = select(mandelColor, vec3<f32>(0.02, 0.0, 0.04), insideSet);
  var finalIter = baseIter;
  var portalAmt = 0.0;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    let alive = elapsed > 0.0 && elapsed < 5.0;
    let portalCenter = ripple.xy;
    let portalDist = length((uv - portalCenter) * vec2<f32>(aspect, 1.0));
    let portalRadius = 0.15 * smoothstep(0.0, 0.5, elapsed) * smoothstep(5.0, 3.0, elapsed);
    let inPortal = smoothstep(portalRadius, portalRadius * 0.7, portalDist) * select(0.0, 1.0, alive);
    let depthScale = exp2(-zoomLevel - 3.0 - f32(i) * 0.35 - elapsed * 0.15);
    let portalCoord = vec2<f32>((portalCenter.x - 0.5) * 3.0 - 0.5, (portalCenter.y - 0.5) * 2.5)
      + (uv - portalCenter) * vec2<f32>(depthScale * aspect, depthScale);
    let portalResult = mandelbrot(portalCoord, maxIterBase + 16);
    let portalT = fract(portalResult.x / 50.0 + time * paletteSpeed * 0.1 + f32(i) * 0.2);
    let portalColor = palette(portalT, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 0.8, 0.6), vec3<f32>(0.1, 0.4, 0.7));
    let pInside = portalResult.x >= portalResult.y - 0.5;
    let pColor = select(portalColor, vec3<f32>(0.05, 0.0, 0.1), pInside);
    let edgeGlow = smoothstep(portalRadius, portalRadius * 0.85, portalDist) - smoothstep(portalRadius * 0.85, portalRadius * 0.7, portalDist);
    finalColor = mix(finalColor, pColor + vec3<f32>(0.4, 0.8, 1.0) * edgeGlow * 1.6, inPortal * portalBlend);
    finalIter = mix(finalIter, portalResult.x, inPortal);
    portalAmt = max(portalAmt, inPortal);
  }

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let hist = textureLoad(dataTextureC, coord, 0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  var hdr = mix(finalColor, inputColor.rgb * 0.45 + finalColor * 0.55, 0.28);
  hdr = mix(hdr, hist.rgb, 0.12 * (1.0 - portalAmt));
  hdr = hdr + vec3<f32>(0.55, 0.85, 1.0) * portalAmt * (0.15 + treble * 0.1 + binB * 0.06);
  let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  hdr = luma + (hdr - vec3<f32>(luma)) * 1.25;
  let rgb = acesToneMap(hdr * 1.08);
  let alpha = clamp(finalIter / max(f32(maxIterBase), 1.0) * 0.65 + portalAmt * 0.3 + depth * 0.1, 0.08, 0.98);
  let outCol = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
