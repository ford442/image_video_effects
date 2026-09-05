// ═══════════════════════════════════════════════════════════════════
//  Sliding Tile Glitch
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: directional row/column tile sliding conveyors + chromatic tear
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
  zoom_params: vec4<f32>,  // x=GridSize, y=SlideAmount, z=Chaos, w=Restoration
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
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
  let binA = plasmaBuffer[1].w;
  let binB = plasmaBuffer[5].z;

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
      let omega = 15.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-4.5), vec2<f32>(4.5));
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
  let gridDensity = mix(6.0, 32.0, u.zoom_params.x);
  let slideAmount = mix(0.02, 0.28, u.zoom_params.y) * (1.0 + bass * 0.45);
  let chaos = u.zoom_params.z;
  let restoration = mix(0.04, 0.40, u.zoom_params.w);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.65, 1.35, depth);

  // Capped click ripple fronts
  var rippleImpulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.0) {
      let d = length((uv - r.xy) * aspectVec);
      let ring = exp(-abs(d - age * 0.45) * 32.0) * exp(-age * 1.6);
      rippleImpulse += ring;
    }
  }

  // Grid index calculation
  let gridCoord = uv * vec2<f32>(gridDensity * aspect, gridDensity);
  let cellId = floor(gridCoord);
  let cellFract = fract(gridCoord);

  // Random cell properties
  let cellRandX = hash21(cellId);
  let cellRandY = hash21(cellId + vec2<f32>(17.3, 41.7));
  let isRowSliding = (cellRandX > 0.45);

  // Mouse distance to cell center
  let cellCenterUV = (cellId + vec2<f32>(0.5)) / vec2<f32>(gridDensity * aspect, gridDensity);
  let distMouse = length((cellCenterUV - spring) * aspectVec);
  let mouseProximity = smoothstep(0.45, 0.02, distMouse) * select(1.0, 1.4, held);

  // Glitch trigger from mouse, ripples, audio
  let glitchActivity = clamp(mouseProximity + rippleImpulse * 0.9 + bass * 0.35 + binA * 0.25, 0.0, 2.5);

  // Continuous slide displacement with restoring oscillatory decay
  let slideFreq = 4.0 + chaos * 8.0 + mids * 3.0;
  let rawSlide = sin(time * slideFreq + cellRandX * 6.28318) * slideAmount;
  let dirChoice = select(select(vec2<f32>(1.0, 0.0), vec2<f32>(-1.0, 0.0), cellRandX > 0.7),
                         select(vec2<f32>(0.0, 1.0), vec2<f32>(0.0, -1.0), cellRandY > 0.7),
                         chaos > 0.5 && !isRowSliding);
  
  let slideVec = dirChoice * rawSlide * glitchActivity * (1.0 - restoration * 0.5);

  // Slid sampling UV
  let shiftedUV = clamp(uv + slideVec, vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic split on displaced tiles
  let chromaOffset = length(slideVec) * 0.035 * (1.0 + treble * 0.6 + binB * 0.4);
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(shiftedUV + vec2<f32>(chromaOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gSample = textureSampleLevel(readTexture, u_sampler, shiftedUV, 0.0).g;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(shiftedUV - vec2<f32>(chromaOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(rSample, gSample, bSample);

  // Grid line highlight for high-chaos glitch zones
  let cellEdge = min(min(cellFract.x, 1.0 - cellFract.x), min(cellFract.y, 1.0 - cellFract.y));
  let gridLine = smoothstep(0.06, 0.01, cellEdge) * glitchActivity * (0.2 + chaos * 0.8);
  let gridNeon = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + cellRandX * 6.28 + time * 2.0);
  color += gridNeon * gridLine * 0.75;

  // Exact previous frame history load from dataTextureC
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.06, 0.28, clamp(glitchActivity * 0.5, 0.0, 1.0));
  var hdr = mix(color, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp(0.72 + glitchActivity * 0.25 + gridLine * 0.3, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * depthFactor + length(slideVec) * 0.5, 0.0, 1.0), 0.0, 0.0, 0.0));
}
