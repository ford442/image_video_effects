// ═══════════════════════════════════════════════════════════════════
//  Pixel Scattering
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: curl velocity field advection + Fibonacci scatter shockwaves
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
  zoom_params: vec4<f32>,  // x=ScatterRadius, y=ScatterDistance, z=TrailLength, w=Chaos
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.015;
  let n = noise2(p + vec2<f32>(0.0, eps) + t);
  let s = noise2(p - vec2<f32>(0.0, eps) + t);
  let e = noise2(p + vec2<f32>(eps, 0.0) + t);
  let w = noise2(p - vec2<f32>(eps, 0.0) + t);
  return vec2<f32>(n - s, -(e - w)) / (2.0 * eps);
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
  let binA = plasmaBuffer[2].y;
  let binB = plasmaBuffer[6].z;

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
  let scatterRadius = mix(0.08, 0.75, u.zoom_params.x);
  let scatterDistance = mix(0.01, 0.18, u.zoom_params.y);
  let trailLength = mix(0.1, 1.0, u.zoom_params.z);
  let chaos = u.zoom_params.w;

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.7, 1.3, depth);

  // Proximity to spring cursor
  let toSpring = (uv - spring) * aspectVec;
  let distSpring = length(toSpring);
  let mouseInteraction = smoothstep(scatterRadius, 0.01, distSpring) * select(1.0, 1.6, held);

  // Click ripple wavefronts
  var rippleScatter = 0.0;
  var rippleDir = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let dVec = (uv - r.xy) * aspectVec;
      let d = length(dVec);
      let ring = exp(-abs(d - age * 0.46) * 30.0) * exp(-age * 1.5);
      rippleScatter += ring;
      if (d > 0.001) {
        rippleDir += (dVec / d) * ring;
      }
    }
  }

  // Curl noise velocity
  let curlCoord = uv * 6.0 + vec2<f32>(time * 0.12, -time * 0.08);
  let curlVel = curlNoise(curlCoord, time * 0.2) * (0.01 + chaos * 0.035) * (1.0 + mids * 0.5);

  // Fibonacci spiral angle component
  let fibIndex = hash12(floor(uv * 45.0) + cell_time(time));
  let fibAngle = fibIndex * 2.39996 + time * (0.5 + chaos);
  let fibDir = vec2<f32>(cos(fibAngle), sin(fibAngle));

  // Tangential vortex rotation around pointer
  let tangent = select(vec2<f32>(0.0), vec2<f32>(-toSpring.y, toSpring.x) / max(distSpring, 0.001), distSpring > 0.001);

  // Combined physical velocity vector
  let mouseWind = tangent / aspectVec * mouseInteraction * (0.02 + scatterDistance * 0.6);
  let bassKick = 1.0 + bass * 0.7 + binA * 0.35;
  let shockKick = rippleDir / aspectVec * (0.03 + scatterDistance * 0.8);

  let velocity = (mouseWind + curlVel + fibDir * (chaos * 0.015) + shockKick) * bassKick * depthFactor;
  let velMag = length(velocity);

  // Multi-tap advection accumulation
  var accum = vec3<f32>(0.0);
  let sampleCount = 6;
  let stepMult = trailLength * 0.012;
  var weightSum = 0.0;

  for (var k: i32 = 0; k < sampleCount; k = k + 1) {
    let t = f32(k) / f32(sampleCount - 1);
    let sampleUV = clamp(uv - velocity * (f32(k) * 2.5) * stepMult, vec2<f32>(0.0), vec2<f32>(1.0));
    
    // Chromatic separation along velocity vector
    let chroma = velMag * 0.04 * (1.0 + treble * 0.8 + binB * 0.5) * t;
    let rSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + velocity * chroma, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let gSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let bSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - velocity * chroma, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    
    let w = 1.0 - t * 0.6;
    accum += vec3<f32>(rSample, gSample, bSample) * w;
    weightSum += w;
  }
  let blurred = accum / max(weightSum, 1e-4);

  // Velocity excitation glow
  let glowPalette = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + velMag * 80.0 + time * 2.0);
  let glow = glowPalette * velMag * (12.0 + treble * 8.0) * (mouseInteraction + rippleScatter * 0.8);

  var hdr = blurred + glow;

  // Exact previous frame history load from dataTextureC for long temporal streak tails
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.08, 0.35, clamp(velMag * 20.0 + mouseInteraction * 0.3, 0.0, 1.0));
  hdr = mix(hdr, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp(0.70 + velMag * 15.0 + mouseInteraction * 0.25 + rippleScatter * 0.3, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth + velMag * 2.0, 0.0, 1.0), 0.0, 0.0, 0.0));
}

fn cell_time(t: f32) -> vec2<f32> {
  return vec2<f32>(sin(t * 0.3), cos(t * 0.3));
}
