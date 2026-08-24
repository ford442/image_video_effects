// ═══════════════════════════════════════════════════════════════════
//  Prismatic Mosaic — Multi-Layer Prismatic Facet Tiles & Volumetric Fog
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, multi-layer-mosaic,
//            chromatic-dispersion, volumetric-fog, semantic-alpha, ACES
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=MinSpeed, y=MaxSpeed, z=SaturationBoost, w=FogDensity
  ripples: array<vec4<f32>, 50>,
};

fn pingPong(a: f32) -> f32 {
  return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn pingPongV2(v: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(pingPong(v.x), pingPong(v.y));
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  let a = hash21(i + vec2<f32>(0.0, 0.0));
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u2.x), mix(c, d, u2.x), u2.y);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let h6 = h * 6.0;
  let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
  var rgb = vec3<f32>(c, x, 0.0);
  if (h6 >= 1.0 && h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h6 >= 2.0 && h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h6 >= 3.0 && h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h6 >= 4.0 && h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else if (h6 >= 5.0 && h6 < 6.0) { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(v - c);
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let zoom_time = u.zoom_config.x;

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
    let stiffness = 42.0;
    let damping = 12.96; // 2 * sqrt(42)
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
  let minSpeed = u.zoom_params.x;
  let maxSpeed = u.zoom_params.y;
  let saturationBoost = u.zoom_params.z;
  let fogDensity = u.zoom_params.w;

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var clickRipple = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.5) * 30.0) * exp(-rDist * 3.5) * exp(-age * 1.4);
      clickRipple += wave * 0.35;
    }
  }

  var accumulatedColor = vec3<f32>(0.0);
  var accumulatedDepth = 0.0;
  var totalWeight = 0.0;

  let zoom_center = mouse;

  for (var layer = 0; layer < 5; layer = layer + 1) {
    let layerDepth = f32(layer) / 4.0;
    let layerSpeed = mix(minSpeed, maxSpeed, layerDepth);
    let layerZoom = 1.0 + fract(zoom_time * layerSpeed + time * 0.1) * 4.0;

    let toCenter = (uv - zoom_center) * vec2<f32>(aspect, 1.0);
    let dist = length(toCenter);
    let vortexStrength = (held * 0.4 + abs(clickRipple) * 0.3 + bass * 0.2) / (dist + 0.1);
    let spinAngle = vortexStrength * layerDepth * (1.0 - layerDepth);

    let cosA = cos(spinAngle);
    let sinA = sin(spinAngle);
    let rotated = vec2<f32>(toCenter.x * cosA - toCenter.y * sinA, toCenter.x * sinA + toCenter.y * cosA);
    let rotatedUV = vec2<f32>(rotated.x / aspect, rotated.y) + zoom_center;

    let nX = noise(rotatedUV * 6.0 + vec2<f32>(time * 0.15, 0.0));
    let nY = noise(rotatedUV * 6.0 + vec2<f32>(0.0, time * 0.15));
    let flowUV = rotatedUV + vec2<f32>(nX, nY) * (0.015 * layerDepth);

    let transformed = (flowUV - zoom_center) / layerZoom + zoom_center;
    let sampleUV = pingPongV2(transformed);

    let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;

    let density = exp(-layerDepth * 1.5);
    let weight = density * (1.0 + sampleDepth * 0.5);

    accumulatedColor += sampleColor * weight;
    accumulatedDepth += sampleDepth * weight;
    totalWeight += weight;
  }

  let baseColor = accumulatedColor / max(totalWeight, 0.0001);
  let baseDepth = accumulatedDepth / max(totalWeight, 0.0001);

  // Chromatic dispersion
  let chroma = 0.02 * (1.0 + treble * 0.5);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(chroma * baseDepth, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(chroma * baseDepth, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var chromaticColor = mix(baseColor, vec3<f32>(r, g, b), 0.5);

  // Apply saturation boost
  let luma = dot(chromaticColor, vec3<f32>(0.299, 0.587, 0.114));
  chromaticColor = mix(vec3<f32>(luma), chromaticColor, 1.0 + saturationBoost * 1.5 + mids * 0.3);

  // Edge glow from depth gradient
  let ps = vec2<f32>(1.0) / resolution;
  let depthX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0).r;
  let depthY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, ps.y), 0.0).r;
  let depthGrad = length(vec2<f32>(depthX - baseDepth, depthY - baseDepth));
  let edgeGlow = exp(-depthGrad * 30.0) * baseDepth * 1.5;
  var finalColor = chromaticColor + vec3<f32>(edgeGlow, edgeGlow * 0.8, edgeGlow * 0.6);

  // Volumetric fog
  let fog = exp(-baseDepth * fogDensity * 3.0);
  let fogColor = vec3<f32>(0.02, 0.05, 0.1) * (1.0 + bass * 0.5);
  finalColor = mix(finalColor, fogColor, (1.0 - fog) * 0.7);

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  finalColor = mix(finalColor, prevC, 0.08);

  let finalRGB = aces(finalColor);

  // Volumetric alpha
  let fresnel = schlickFresnel(0.8, 0.03);
  let alpha = clamp((mix(0.95, 0.4, fog) * 0.8 + edgeGlow * 0.3) * (1.0 - fresnel * 0.2) + held * 0.1, 0.15, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
