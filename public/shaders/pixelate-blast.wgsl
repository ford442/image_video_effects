// ═══════════════════════════════════════════════════════════════════
//  Pixelate Blast
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: Voronoi cellular explosion + domain-warped blast shockwaves
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
  zoom_params: vec4<f32>,  // x=CellDensity, y=BlastRadius, z=EdgeGlowAmount, w=ChromaticAmount
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = hash12(p);
  return vec2<f32>(n, hash12(p + vec2<f32>(1.0, 0.0)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn voronoi(p: vec2<f32>, time: f32) -> vec3<f32> {
  let n = floor(p);
  let f = fract(p);
  var md = 8.0;
  var md2 = 8.0;
  var closest = vec2<f32>(0.0);
  for (var j = -1; j <= 1; j = j + 1) {
    for (var i = -1; i <= 1; i = i + 1) {
      let g = vec2<f32>(f32(i), f32(j));
      let o = hash22(n + g) * 0.5 + 0.25;
      let anim = vec2<f32>(sin(time + hash12(n + g) * 6.28), cos(time + hash12(n + g + 1.0) * 6.28)) * 0.15;
      let r = g + o + anim - f;
      let d = dot(r, r);
      if (d < md) {
        md2 = md;
        md = d;
        closest = n + g + o;
      } else if (d < md2) {
        md2 = min(md2, d);
      }
    }
  }
  return vec3<f32>(sqrt(md), sqrt(md2), closest.x + closest.y);
}

fn domainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
  let q = vec2<f32>(sin(p.y * 2.0 + time), cos(p.x * 2.0 + time * 0.8));
  return p + q * 0.25;
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
  let binA = plasmaBuffer[2].x;
  let binB = plasmaBuffer[5].y;

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
  let cellDensity = mix(8.0, 52.0, u.zoom_params.x) * (1.0 + bass * 0.2);
  let blastRadius = mix(0.12, 0.75, u.zoom_params.y) * select(1.0, 1.4, held);
  let edgeGlowAmt = mix(0.1, 1.8, u.zoom_params.z);
  let chromaAmt = mix(0.002, 0.045, u.zoom_params.w) * (1.0 + treble * 0.7);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFade = mix(0.7, 1.35, depth);

  // Epicenter distance
  let toSpring = (uv - spring) * aspectVec;
  let dist = length(toSpring);
  let blastFade = smoothstep(blastRadius, 0.0, dist);

  // Capped click ripple blast waves
  var blastEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let rd = length((uv - r.xy) * aspectVec);
      blastEnergy += exp(-abs(rd - age * 0.5) * 24.0) * exp(-age * 1.4);
    }
  }

  // Audio acoustic wave
  let bassWave = sin(dist * 18.0 - time * (5.0 + bass * 3.0)) * 0.5 + 0.5;
  blastEnergy += blastFade * (1.2 + held_boost(held)) + bassWave * bass * 0.4 + binA * 0.25;

  // Domain warped Voronoi cells
  let warpedUV = domainWarp(uv * cellDensity, time * (0.4 + mids * 0.3));
  let v = voronoi(warpedUV + toSpring * blastEnergy * 0.4, time * 0.5);

  let cellCenter = floor(warpedUV) + 0.5;
  let cellUV = clamp((cellCenter + 0.5) / cellDensity, vec2<f32>(0.0), vec2<f32>(1.0));

  // Cauchy chromatic sampling across blast direction
  let blastDir = select(vec2<f32>(1.0, 0.0), toSpring / max(dist, 1e-4), dist > 0.001);
  let ca = blastDir * chromaAmt * (1.0 + blastEnergy);

  let rCol = textureSampleLevel(readTexture, u_sampler, clamp(cellUV + ca, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gCol = textureSampleLevel(readTexture, u_sampler, cellUV, 0.0).g;
  let bCol = textureSampleLevel(readTexture, u_sampler, clamp(cellUV - ca, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let baseColor = vec3<f32>(rCol, gCol, bCol);

  // Voronoi cell facet edges & glow
  let edgeDist = v.y - v.x;
  let edgeMask = smoothstep(0.08, 0.01, edgeDist);
  let edgePalette = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + v.z * 1.5 + time * 1.5);
  let glowCol = edgePalette * edgeMask * edgeGlowAmt * (1.0 + blastEnergy * 0.8 + treble * 0.5);

  let internalGrad = 1.0 - v.x * 1.8;
  var hdr = baseColor * (0.65 + internalGrad * 0.35) + glowCol;

  // Radial blast wave highlight
  hdr += vec3<f32>(1.0, 0.85, 0.6) * blastEnergy * edgeMask * 0.5;

  // Exact previous frame history load from dataTextureC for temporal persistence
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.06, 0.28, clamp(blastEnergy * 0.4, 0.0, 1.0));
  hdr = mix(hdr, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp((blastEnergy * 0.3 + blastFade * 0.4 + edgeMask * 0.3) * depthFade + 0.35, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, 0.3 + blastEnergy * 0.5, 0.3), 0.0, 1.0), 0.0, 0.0, 0.0));
}

fn held_boost(h: bool) -> f32 {
  return select(0.0, 0.6, h);
}
