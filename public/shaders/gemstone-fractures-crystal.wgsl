// ═══════════════════════════════════════════════════════════════════
//  Gemstone Fractures Crystal — Faceted Shards & Dendritic Growth
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, voronoi-shards, crystal-growth,
//            physical-refraction, birefringence, semantic-alpha, ACES
//  Complexity: Very High
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

const IOR_QUARTZ: f32 = 1.54;
const IOR_DIAMOND: f32 = 2.42;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Sliders: exact parameter contracts
  let scaleParam = u.zoom_params.x;     // 0..1, default 0.5
  let iorMixParam = u.zoom_params.y;    // 0..1, default 0.5
  let rotParam = u.zoom_params.z;       // 0..1, default 0.5
  let fractureParam = u.zoom_params.w;  // 0..1, default 0.5

  let scale = (scaleParam * 18.0 + 3.0) * (1.0 + bass * 0.2);
  let iorMix = iorMixParam;
  let rotationBase = rotParam;
  let fractureDensity = fractureParam;

  let ior = mix(IOR_QUARTZ, IOR_DIAMOND, iorMix);
  let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

  // Critically damped spring cursor in extraBuffer[133..138]
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let isWriter = (gid.x == 0u && gid.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.1);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 36.0;
    let damping = 12.0;
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel = sVel + accel * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Voronoi gemstone facet cells with aspect correction
  let st = uv * vec2<f32>(aspect, 1.0) * scale;
  let i_st = floor(st);
  let f_st = fract(st);

  var m_dist = 1.0;
  var second_dist = 1.0;
  var cell_id = vec2<f32>(0.0);

  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let point = hash22(i_st + neighbor);
      let animPoint = 0.5 + 0.5 * sin(time * 0.4 + 6.2831 * point + bass * 0.5);
      let diff = neighbor + animPoint - f_st;
      let d = length(diff);
      if (d < m_dist) {
        second_dist = m_dist;
        m_dist = d;
        cell_id = i_st + neighbor;
      } else if (d < second_dist) {
        second_dist = d;
      }
    }
  }

  // Mouse interaction: facet rotation and light orientation
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseInfluence = smoothstep(0.4, 0.0, mouseDist);

  let cellHash = hash22(cell_id);
  let rotAngle = (cellHash.x - 0.5) * rotationBase * 8.0 + (time * 0.2 + mouseInfluence * 2.0) * (cellHash.y - 0.5);
  let cA = cos(rotAngle);
  let sA = sin(rotAngle);
  let cellCenterUV = (cell_id + 0.5) / (vec2<f32>(aspect, 1.0) * scale);
  let fromCenter = uv - cellCenterUV;
  let rotOffset = vec2<f32>(fromCenter.x * cA - fromCenter.y * sA, fromCenter.x * sA + fromCenter.y * cA);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var clickFracture = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
    clickFracture += abs(wave) * 0.5;
  }

  // Spectral dispersion & mineral refraction
  let dispersion = (ior - 1.0) * 0.35;
  let refractionDist = (iorMix * 0.04 + clickFracture * 0.02) * (1.0 + treble * 0.3);
  let sampleBase = clamp(cellCenterUV + rotOffset * 0.8, vec2<f32>(0.0), vec2<f32>(1.0));

  let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleBase + vec2<f32>(refractionDist * (1.0 + dispersion), 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, sampleBase, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(sampleBase - vec2<f32>(refractionDist * (1.0 + dispersion), 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r, g, b);

  // Dendritic crystal growth inside each gemstone cell
  let cellFracture = hash21(cell_id);
  let effectiveFracture = fractureDensity * (0.4 + 0.6 * cellFracture) + clickFracture * 0.3;
  let purity = clamp(1.0 - effectiveFracture, 0.1, 1.0);

  let cellDist = length(fromCenter * vec2<f32>(aspect, 1.0));
  let supercooling = mix(0.15, 0.85, scaleParam);
  let crystalPhase = smoothstep(0.45, 0.0, cellDist) * supercooling;
  let anisoAngle = atan2(fromCenter.y, fromCenter.x * aspect);
  let anisoFactor = 1.0 + 0.4 * sin(anisoAngle * 6.0 + time * 1.5 + mids * 2.0);
  let growth = smoothstep(0.0, 1.0, crystalPhase * 0.008 * anisoFactor * 60.0 + time * 0.15 + held * 0.2);

  // Birefringence orientation colors
  let orientNorm = fract((anisoAngle + time * 0.15 + mouseInfluence * 0.5) / 6.2831853);
  let h6 = orientNorm * 6.0;
  let cc = 0.85;
  let xx = cc * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
  var crystalColor = vec3<f32>(cc, xx, 0.3);
  if (h6 >= 1.0 && h6 < 2.0) { crystalColor = vec3<f32>(xx, cc, 0.3); }
  else if (h6 >= 2.0 && h6 < 3.0) { crystalColor = vec3<f32>(0.3, cc, xx); }
  else if (h6 >= 3.0 && h6 < 4.0) { crystalColor = vec3<f32>(0.3, xx, cc); }
  else if (h6 >= 4.0 && h6 < 5.0) { crystalColor = vec3<f32>(xx, 0.3, cc); }
  else if (h6 >= 5.0) { crystalColor = vec3<f32>(cc, 0.3, xx); }

  color = mix(color, color * crystalColor * 1.6, growth * 0.45);

  // Facet Fresnel & fracture lines
  let cosTheta = clamp(1.0 - m_dist, 0.0, 1.0);
  let fresnel = fresnelSchlick(cosTheta, F0);
  let pathLength = mix(0.06, 0.45, m_dist) / purity;
  let absorption = exp(-vec3<f32>(0.25, 0.2, 0.15) * pathLength * (effectiveFracture * 3.0 + 0.5));

  let edgeDist = second_dist - m_dist;
  let edgeFactor = smoothstep(0.025, 0.0, edgeDist);
  let fractureLine = smoothstep(0.015, 0.0, edgeDist) * effectiveFracture;

  let specular = edgeFactor * fresnel * (1.2 + treble * 0.8);
  color = color * absorption + vec3<f32>(1.0, 0.98, 0.92) * specular;

  // Exact dataTextureC facet reflection trail
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prev, 0.08 + held * 0.05);

  // ACES Tonemap
  let finalRGB = aces(color);

  // Semantic alpha: transmission + diamond facet reflectivity + depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let transmission = (1.0 - fresnel) * purity;
  let alpha = clamp(transmission * (1.0 - fractureLine * 0.5) + specular * 0.4 + mouseInfluence * 0.15, 0.35, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
