// ═══════════════════════════════════════════════════════════════════
//  Alpha Multi-Layer Glass — Refractive Glass Stack
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, multi-layer-glass, fresnel,
//            chromatic-aberration, ggx-roughness, semantic-transmittance
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
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let sm = f * f * (3.0 - 2.0 * f);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, sm.x), mix(c, d, sm.x), sm.y);
}

fn fbm2(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var freq = 1.0;
  for (var i = 0; i < 3; i = i + 1) {
    v += a * valueNoise(p * freq);
    a *= 0.5;
    freq *= 2.0;
  }
  return v;
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
  let iorParam = u.zoom_params.x;     // 0..1, def 0.5 -> IOR 1.1 to 1.7
  let thickParam = u.zoom_params.y;   // 0..1, def 0.3 -> thickness
  let chromParam = u.zoom_params.z;   // 0..1, def 0.3 -> chromatic dispersion
  let roughParam = u.zoom_params.w;   // 0..1, def 0.4 -> surface roughness

  let iorBase = mix(1.15, 1.75, iorParam);
  let thickness = mix(0.003, 0.025, thickParam);
  let chromaticStrength = chromParam * (0.008 + mids * 0.006);
  let roughness = roughParam * (0.012 + treble * 0.008);

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

  // Procedural glass surface normals + acoustic plate vibrations
  let noiseUV = uv * 3.5 + vec2<f32>(time * 0.015, time * 0.01);
  let plateWave = sin(uv.x * 20.0 + time * 2.0) * sin(uv.y * 20.0 - time * 1.5) * bass * 0.4;
  let normalX = (fbm2(noiseUV) - 0.5) * 2.0 + plateWave;
  let normalY = (fbm2(noiseUV + vec2<f32>(43.12, 17.89)) - 0.5) * 2.0;
  let surfaceNormal = normalize(vec2<f32>(normalX, normalY));

  // Touch deflection & pointer influence
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseInfluence = smoothstep(0.35, 0.0, mouseDist) * (0.5 + held * 0.5);
  let mouseNormal = normalize(uv - mouse + vec2<f32>(0.0001));
  let combinedNormal = normalize(mix(surfaceNormal, mouseNormal, mouseInfluence * 0.6));

  // Click ripple shocks on glass surface
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleNormal = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let wave = sin((rDist - age * 0.6) * 40.0) * exp(-rDist * 4.5) * exp(-age * 1.6);
    let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
    rippleNormal += dir * wave * 0.4;
  }
  let totalNormal = normalize(combinedNormal + rippleNormal * 0.5);

  // Multi-layer glass refraction stack (3 distinct physical panes)
  var totalTransmittance = 1.0;
  var accumulatedColor = vec3<f32>(0.0);
  var specularTotal = 0.0;

  for (var layer = 0; layer < 3; layer = layer + 1) {
    let layerF = f32(layer);
    let ior = iorBase + layerF * 0.08;

    // Schlick Fresnel
    let R0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
    let cosI = clamp(abs(totalNormal.y * 0.8 + 0.2), 0.0, 1.0);
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cosI, 5.0);
    let layerTransmittance = clamp(1.0 - fresnel * 0.65, 0.05, 1.0);

    // Refraction offset per pane with physical dispersion
    let paneOffset = totalNormal * thickness * (layerF + 1.0);
    let roughJitter = (hash12(uv * 200.0 + f32(layer) * 17.0) - 0.5) * roughness * (layerF + 1.0);

    let refractR = clamp(uv + paneOffset * (1.0 + chromaticStrength * 1.5) + vec2<f32>(roughJitter, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let refractG = clamp(uv + paneOffset + vec2<f32>(roughJitter * 0.5, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let refractB = clamp(uv + paneOffset * (1.0 - chromaticStrength * 1.5) - vec2<f32>(roughJitter, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let sampleR = textureSampleLevel(readTexture, u_sampler, refractR, 0.0).r;
    let sampleG = textureSampleLevel(readTexture, u_sampler, refractG, 0.0).g;
    let sampleB = textureSampleLevel(readTexture, u_sampler, refractB, 0.0).b;

    // Physical absorption tint per pane (Beer-Lambert law)
    let tint = vec3<f32>(
      1.0 - layerF * 0.08,
      1.0 - layerF * 0.03,
      0.95 + layerF * 0.02
    );

    let layerColor = vec3<f32>(sampleR, sampleG, sampleB) * tint;
    accumulatedColor += layerColor * (totalTransmittance * layerTransmittance);
    totalTransmittance *= layerTransmittance;

    // Specular glint on pane surface
    let lightDir = normalize(vec2<f32>(0.7, -0.7));
    let spec = pow(max(dot(totalNormal, lightDir), 0.0), mix(25.0, 8.0, roughParam)) * fresnel;
    specularTotal += spec * (0.35 + treble * 0.25);
  }

  // Internal multi-bounce reflection from exact dataTextureC load
  let prevInternal = textureLoad(dataTextureC, pixel, 0).rgb;
  accumulatedColor = mix(accumulatedColor, prevInternal, 0.08 + thickParam * 0.05);
  accumulatedColor += vec3<f32>(1.0, 0.98, 0.95) * specularTotal;

  // ACES Tonemap
  let finalRGB = aces(accumulatedColor);

  // Semantic transmittance alpha
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalAlpha = clamp(totalTransmittance * 0.75 + (1.0 - totalTransmittance) * 0.95 + mouseInfluence * 0.1, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
