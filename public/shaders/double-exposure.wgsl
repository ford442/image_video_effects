// ═══════════════════════════════════════════════════════════════════
//  Double Exposure Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: spring-anchored secondary exposure warp + rotational ripple shockwaves
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ZoomLevel, y=Rotation, z=Opacity, w=WarpStrength
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;

fn hash21(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
  return fract(vec2<f32>(n, n * 1.6180339887)) * 2.0 - 1.0;
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i).x;
  let b = hash21(i + vec2<f32>(1.0, 0.0)).x;
  let c = hash21(i + vec2<f32>(0.0, 1.0)).x;
  let d = hash21(i + vec2<f32>(1.0, 1.0)).x;
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var a = 0.5;
  var s = 0.0;
  var q = p;
  for (var i = 0; i < 4; i = i + 1) {
    s += a * valueNoise(q);
    q = q * 2.02;
    a *= 0.5;
  }
  return s;
}

fn rotate2d(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[3].z;
  let binB = plasmaBuffer[7].y;

  // Single-writer spring cursor in extraBuffer[133..138]
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
      let omega = 13.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-4.0), vec2<f32>(4.0));
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

  // Four saved controls preserved
  let zoomLevel = mix(0.4, 2.8, u.zoom_params.x) * (1.0 + bass * 0.22);
  let rotationParam = (u.zoom_params.y - 0.5) * PI * 1.5;
  let opacity = mix(0.1, 0.95, u.zoom_params.z);
  let warpStrength = mix(0.0, 0.65, u.zoom_params.w);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthParallax = mix(0.8, 1.25, depth);

  // Capped click ripple rotational shockwaves
  var rippleRotation = 0.0;
  var rippleFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let d = length((uv - r.xy) * aspectVec);
      let ring = exp(-abs(d - age * 0.44) * 28.0) * exp(-age * 1.4);
      rippleRotation += ring * sin(age * 8.0) * 0.4;
      rippleFlash += ring;
    }
  }

  // Base exposure (layer 1)
  let c1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Transform secondary layer relative to spring pivot
  var p = (uv - spring) * aspectVec;
  let totalAngle = rotationParam + time * (0.15 + mids * 0.2) + rippleRotation + select(0.0, 0.25, held);
  p = rotate2d(p, totalAngle);
  p = p / max(zoomLevel * depthParallax, 0.01);

  // Domain warp for second exposure
  let warpScale = 2.5 + warpStrength * 4.0;
  let wVal = fbm(p * warpScale + vec2<f32>(time * 0.15, -time * 0.1)) * warpStrength * 0.12;
  p += vec2<f32>(cos(time * 0.6 + wVal * 6.28), sin(time * 0.5 + wVal * 6.28)) * wVal;

  p.x = p.x / aspect;
  let uv2 = clamp(p + spring, vec2<f32>(0.0), vec2<f32>(1.0));

  // Sample secondary exposure with chromatic aberration
  let chromaOffset = (warpStrength * 0.008 + length(p) * 0.004) * (1.0 + treble * 0.7 + binA * 0.4);
  let r2 = textureSampleLevel(readTexture, u_sampler, clamp(uv2 + vec2<f32>(chromaOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0).g;
  let b2 = textureSampleLevel(readTexture, u_sampler, clamp(uv2 - vec2<f32>(chromaOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let c2 = vec3<f32>(r2, g2, b2);

  // Cellular interference mask modulating exposure interaction
  let voroPattern = sin(uv.x * 14.0 + time) * cos(uv.y * 14.0 - time * 0.8) * 0.5 + 0.5;
  let layerMix = opacity * (0.75 + voroPattern * 0.25) * (1.0 + held_bonus(held));

  // Photographic Screen / Soft-Light exposure blend
  let screenBlend = 1.0 - (1.0 - c1) * (1.0 - c2 * layerMix);
  let overlayBlend = mix(c1 * (c2 * 2.0), 1.0 - 2.0 * (1.0 - c1) * (1.0 - c2), step(vec3<f32>(0.5), c1));
  var composite = mix(screenBlend, overlayBlend, 0.35);

  // Flash tint at ripple fronts
  let flashColor = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + time * 1.5 + binB * 2.0);
  composite += flashColor * rippleFlash * 0.35;

  // Exact previous frame history load from dataTextureC for ghost trails
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.05, 0.25, layerMix);
  var hdr = mix(composite, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let luma = dot(finalRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
  let semanticAlpha = clamp(0.70 + luma * 0.25 + rippleFlash * 0.3, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, 0.3 + luma * 0.5, 0.35), 0.0, 1.0), 0.0, 0.0, 0.0));
}

fn held_bonus(h: bool) -> f32 {
  return select(0.0, 0.2, h);
}
