// ═══════════════════════════════════════════════════════════════════
//  Refraction Shards
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: crystalline shard facet drift + traveling fracture wavefronts
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
  zoom_params: vec4<f32>,  // x=ShardSize, y=Refraction, z=Roughness, w=PrismEffect
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec2<f32>(
    sin(dot(p, vec2<f32>(127.1, 311.7))),
    sin(dot(p, vec2<f32>(269.5, 183.3)))
  ) * 43758.5453;
  return fract(q);
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
}

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.50, 0.50, 0.52) +
         vec3<f32>(0.46, 0.42, 0.48) *
         cos(6.28318 * (vec3<f32>(1.0, 0.72, 0.53) * t + vec3<f32>(0.02, 0.32, 0.62)));
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
  let binA = plasmaBuffer[3].y;
  let binB = plasmaBuffer[7].x;

  // Single-writer spring-damper cursor in extraBuffer[133..138]
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
      let omega = 14.0;
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
  let shardScale = mix(5.0, 28.0, u.zoom_params.x);
  let refraction = mix(0.01, 0.14, u.zoom_params.y) * (1.0 + bass * 0.4);
  let roughness = u.zoom_params.z * 0.04;
  let prism = mix(0.005, 0.05, u.zoom_params.w) * (1.0 + treble * 0.65 + binB * 0.3);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.65, 1.4, depth);

  // Capped click ripple fracture wavefronts
  var rippleFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let d = length((uv - r.xy) * aspectVec);
      let front = exp(-abs(d - age * 0.44) * 34.0) * exp(-age * 1.5);
      rippleFront += front;
    }
  }

  // Continuous smooth facet drift (no frame-quantized hash jumps)
  let p = uv * shardScale;
  let cell = floor(p);
  let local = fract(p);

  var bestDist = 10.0;
  var secondDist = 10.0;
  var bestDelta = vec2<f32>(0.0);
  var cellSeed = vec2<f32>(0.0);

  for (var j = -1; j <= 1; j = j + 1) {
    for (var i = -1; i <= 1; i = i + 1) {
      let neighbor = vec2<f32>(f32(i), f32(j));
      let h = hash22(cell + neighbor);
      // Smooth sinusoidal orbital drift per shard
      let drift = vec2<f32>(sin(time * 0.6 + h.x * 6.28), cos(time * 0.5 + h.y * 6.28)) * 0.15;
      let point = neighbor + h * 0.7 + 0.15 + drift;
      let delta = point - local;
      let d = dot(delta, delta);
      if (d < bestDist) {
        secondDist = bestDist;
        bestDist = d;
        bestDelta = delta;
        cellSeed = h;
      } else if (d < secondDist) {
        secondDist = d;
      }
    }
  }

  // Shard facet edge
  let facetEdge = sqrt(secondDist) - sqrt(bestDist);
  let edgeLine = 1.0 - smoothstep(0.01, 0.08, facetEdge);

  // Proximity to smoothed cursor
  let toSpring = (uv - spring) * aspectVec;
  let distSpring = length(toSpring);
  let mouseInteraction = smoothstep(0.50, 0.02, distSpring) * select(1.0, 1.5, held);

  // Normal deflection vector from shard geometry and pointer
  let shardNormal = safeNormalize(bestDelta + toSpring * (0.35 + rippleFront * 0.6));
  let wobble = (hash22(cell + cellSeed) - vec2<f32>(0.5)) * roughness;
  let totalOffset = (shardNormal * refraction + wobble) * (1.0 + mouseInteraction * 0.7 + rippleFront * 0.8) * depthFactor;

  let centerUV = clamp(uv + totalOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  // Cauchy 3-band spectral dispersion
  let dispVec = shardNormal * prism;
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(centerUV + dispVec * 1.2, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gSample = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0).g;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(centerUV - dispVec * 1.2, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(rSample, gSample, bSample);

  // Prismatic iridescent facet edge glint
  let glintPalette = palette(cellSeed.x * 2.0 + time * 0.2 + mids * 0.4 + rippleFront);
  let facetGlint = pow(edgeLine, 2.0) * (0.4 + treble * 0.8 + binA * 0.5);
  color += glintPalette * facetGlint * 1.3;

  // Specular flare at cursor
  color += vec3<f32>(1.0, 0.95, 0.8) * mouseInteraction * edgeLine * (0.4 + bass * 0.5);

  // Exact previous frame history load from dataTextureC for crystal persistence
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.06, 0.26, clamp(mouseInteraction * 0.5 + rippleFront * 0.4, 0.0, 1.0));
  var hdr = mix(color, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp(0.78 + edgeLine * 0.2 + mouseInteraction * 0.15 + rippleFront * 0.2, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, 0.25 + (1.0 - edgeLine) * 0.65, 0.4), 0.0, 1.0), 0.0, 0.0, 0.0));
}
