// ═══════════════════════════════════════════════════════════════════
//  spec-bicubic-crystal — Bicubic Catmull-Rom Crystalline Distortion
//  Category: distortion
//  Features: mouse-driven, audio-reactive, bicubic, catmull-rom,
//            crystalline, chromatic-separation, semantic-alpha, ACES
//  Complexity: High
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
  zoom_params: vec4<f32>,  // x=CrystalScale, y=Distortion, z=FacetSharpness, w=ChromaticSep
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn catmullRom(t: f32) -> vec4<f32> {
  let t2 = t * t;
  let t3 = t2 * t;
  return vec4<f32>(
    -0.5 * t3 + t2 - 0.5 * t,
    1.5 * t3 - 2.5 * t2 + 1.0,
    -1.5 * t3 + 2.0 * t2 + 0.5 * t,
    0.5 * t3 - 0.5 * t2
  );
}

fn sampleBicubic(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, texSize: vec2<f32>) -> vec4<f32> {
  let pixel = uv * texSize - 0.5;
  let f = fract(pixel);
  let base = floor(pixel);

  let wx = catmullRom(f.x);
  let wy = catmullRom(f.y);

  var result = vec4<f32>(0.0);
  for (var j = -1; j <= 2; j = j + 1) {
    for (var i = -1; i <= 2; i = i + 1) {
      let coord = (base + vec2<f32>(f32(i), f32(j)) + 0.5) / texSize;
      let s = textureSampleLevel(tex, samp, clamp(coord, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
      let weight = wx[i + 1] * wy[j + 1];
      result += s * weight;
    }
  }
  return result;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (gid.x == 0u && gid.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 45.0;
    let damping = 13.416; // 2 * sqrt(45)
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Exact parameter contracts
  let crystalScale = mix(3.0, 20.0, u.zoom_params.x) * (1.0 + bass * 0.15);
  let distortion = mix(0.01, 0.18, u.zoom_params.y) * (1.0 + mids * 0.25);
  let facetSharp = mix(0.5, 4.0, u.zoom_params.z);
  let chromaSep = mix(0.002, 0.04, u.zoom_params.w) * (1.0 + treble * 0.4);

  // Crystalline facet UV distortion
  let cellId = floor(uv * crystalScale);
  let cellLocal = fract(uv * crystalScale) - 0.5;

  let facetHash = hash12(cellId + vec2<f32>(37.0, 17.0));
  let facetAngle = facetHash * 6.2831853 + time * 0.2;
  let facetOffset = vec2<f32>(cos(facetAngle), sin(facetAngle)) * distortion;

  let distFromCenter = length(cellLocal);
  let facetEdge = 1.0 - smoothstep(0.35, 0.5, distFromCenter);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleOffset = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleOffset += rDir * wave * 0.03;
    }
  }

  var distortedUV = uv + facetOffset * facetEdge + rippleOffset;
  let toMouse = (mouse - uv) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(toMouse);
  let mouseInfluence = exp(-mouseDist * mouseDist * (20.0 - held * 10.0)) * (0.5 + held * 0.5);
  distortedUV += vec2<f32>(toMouse.x / aspect, toMouse.y) * mouseInfluence * distortion * 2.0;

  // Bicubic Catmull-Rom sampling with chromatic separation
  let rSample = sampleBicubic(readTexture, u_sampler, distortedUV + vec2<f32>(chromaSep, 0.0), res).r;
  let gSample = sampleBicubic(readTexture, u_sampler, distortedUV, res).g;
  let bSample = sampleBicubic(readTexture, u_sampler, distortedUV - vec2<f32>(chromaSep, 0.0), res).b;
  var color = vec3<f32>(rSample, gSample, bSample);

  // Facet edge highlights
  let edgeGlow = pow(1.0 - distFromCenter * 2.0, facetSharp) * 0.35 * (1.0 + treble * 0.5);
  color += vec3<f32>(edgeGlow * 0.5, edgeGlow * 0.6, edgeGlow * 0.85);

  // Time-varying facet iridescence
  let iridHue = time * 0.15 + facetHash * 3.0 + distFromCenter * 5.0 + mids * 0.5;
  let iridColor = vec3<f32>(
    0.5 + 0.5 * cos(iridHue),
    0.5 + 0.5 * cos(iridHue + 2.094),
    0.5 + 0.5 * cos(iridHue + 4.188)
  );
  color += iridColor * edgeGlow * 0.35;

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prevC, 0.07);

  let finalRGB = aces(color);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(facetEdge * 0.7 + edgeGlow * 0.4 + mouseInfluence * 0.15 + 0.25, 0.1, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
