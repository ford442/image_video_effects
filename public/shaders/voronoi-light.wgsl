// ═══════════════════════════════════════════════════════════════════
//  Voronoi Light
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: spring-damper cursor lantern + photon ripple wavefronts
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
  zoom_params: vec4<f32>,  // x=CellDensity, y=LightRadius, z=Mode, w=PulseSpeed
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
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
  let binA = plasmaBuffer[2].w;
  let binB = plasmaBuffer[6].x;

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
  let density = mix(6.0, 48.0, u.zoom_params.x);
  let lightRadius = mix(0.12, 0.85, u.zoom_params.y) * (1.0 + bass * 0.45) * select(1.0, 1.4, held);
  let colorMode = u.zoom_params.z;
  let pulseSpeed = mix(0.5, 4.0, u.zoom_params.w) * (1.0 + mids * 0.5);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthScale = mix(0.7, 1.35, depth);

  // Proximity to spring cursor lantern
  let toSpring = (uv - spring) * aspectVec;
  let distSpring = length(toSpring);
  let lanternLight = smoothstep(lightRadius, lightRadius * 0.1, distSpring);
  let lanternPulse = 0.85 + 0.15 * sin(time * pulseSpeed * 2.5) + bass * 0.35;

  // Capped click ripple photon waves
  var ripplePhoton = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let d = length((uv - r.xy) * aspectVec);
      let ring = exp(-abs(d - age * 0.48) * 32.0) * exp(-age * 1.5);
      ripplePhoton += ring;
    }
  }

  // Voronoi cell calculations
  let st = uv * vec2<f32>(aspect, 1.0) * density;
  let i_st = floor(st);
  let f_st = fract(st);

  var m_dist = 8.0;
  var m_dist2 = 8.0;
  var cellPoint = vec2<f32>(0.0);
  var cellDelta = vec2<f32>(0.0);

  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let pHash = hash22(i_st + neighbor);
      // Smooth animated cell center offset
      let anim = vec2<f32>(sin(time * pulseSpeed + pHash.x * 6.28), cos(time * pulseSpeed * 0.8 + pHash.y * 6.28)) * 0.18;
      let point = neighbor + pHash * 0.6 + 0.2 + anim;
      let diff = point - f_st;
      let distSq = dot(diff, diff);
      if (distSq < m_dist) {
        m_dist2 = m_dist;
        m_dist = distSq;
        cellPoint = pHash;
        cellDelta = diff;
      } else if (distSq < m_dist2) {
        m_dist2 = distSq;
      }
    }
  }

  let d1 = sqrt(m_dist);
  let d2 = sqrt(m_dist2);
  let border = smoothstep(0.02, 0.08, d2 - d1);
  let borderGlow = (1.0 - border) * (0.4 + bass * 0.8 + ripplePhoton * 0.6);

  let rawSource = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  var color = rawSource;
  if (colorMode < 0.5) {
    // Mode 0: Tech Mode - Cybernetic dark lattice with illuminated cells and neon seams
    let cellLit = lanternLight * lanternPulse + ripplePhoton * 0.85;
    let darkBase = rawSource * (0.08 + cellLit * 0.92);
    let neonHue = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + cellPoint.x * 6.28 + time * 1.5 + binA * 2.0);
    color = mix(vec3<f32>(0.01, 0.02, 0.03), darkBase, border);
    color += neonHue * borderGlow * (0.8 + cellLit * 1.2);
  } else {
    // Mode 1: Glass Mode - Stained-glass facet refraction with caustic glints
    let refrOffset = cellDelta * 0.015 * (1.0 + lanternLight * 0.8);
    let refrUV = clamp(uv + refrOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let chroma = 0.005 * (1.0 + treble * 0.8 + binB * 0.4);
    let rRefr = textureSampleLevel(readTexture, u_sampler, clamp(refrUV + vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let gRefr = textureSampleLevel(readTexture, u_sampler, refrUV, 0.0).g;
    let bRefr = textureSampleLevel(readTexture, u_sampler, clamp(refrUV - vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let glassColor = vec3<f32>(rRefr, gRefr, bRefr) * (0.6 + 0.4 * lanternLight * lanternPulse);
    color = mix(glassColor * 0.35, glassColor * 1.15, border);
    
    // Prismatic glint at facet peaks
    let glint = pow(max(0.0, 1.0 - d1 * 2.2), 4.0) * (0.3 + treble * 0.7);
    color += vec3<f32>(1.0, 0.9, 0.75) * glint * (lanternLight + ripplePhoton);
  }

  // Bass-ignited borders across entire frame
  let emberHue = vec3<f32>(1.0, 0.45, 0.12) * (1.0 - border) * bass * 0.75;
  color += emberHue;

  // Exact previous frame history load from dataTextureC for luminescent decay
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.06, 0.28, clamp(lanternLight * 0.5 + ripplePhoton * 0.4, 0.0, 1.0));
  var hdr = mix(color, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp((lanternLight * lanternPulse + borderGlow * 0.5) * depthScale + 0.35, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, (1.0 - d1) * depthScale, 0.35), 0.0, 1.0), 0.0, 0.0, 0.0));
}
