// ═══════════════════════════════════════════════════════════════════
//  Glass Bead Curtain Iridescence — Spherical Thin-Film Lenses
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, refraction, thin-film-interference,
//            spectral-render, semantic-alpha, ACES
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
  let g = 1.0 - abs(t - 0.45) * 2.5;
  let b = 1.0 - smoothstep(0.0, 0.45, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
  let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
  let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
  let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;

  var color = vec3<f32>(0.0);
  var sampleCount = 0.0;
  for (var lambda = 380.0; lambda <= 700.0; lambda += 25.0) {
    let phase = opd / lambda;
    let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
    color += wavelengthToRGB(lambda) * interference;
    sampleCount += 1.0;
  }
  return color / max(sampleCount, 1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Sliders: exact parameter contracts
  let beadSizeParam = u.zoom_params.x;  // 0..1, def 0.5
  let refractParam = u.zoom_params.y;   // 0..1, def 0.5
  let iridParam = u.zoom_params.z;      // 0..1, def 0.6
  let thickParam = u.zoom_params.w;     // 0..1, def 0.5

  let beadSize = mix(15.0, 80.0, beadSizeParam) * (1.0 + bass * 0.15);
  let refractionStr = refractParam * 0.45;
  let iridescenceIntensity = mix(0.1, 1.8, iridParam) * (1.0 + mids * 0.4);
  let filmThicknessBase = mix(220.0, 780.0, thickParam) * (1.0 + treble * 0.25);

  // Critically damped spring cursor in extraBuffer[133..138]
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
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

  // Interactive bead curtain parting
  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let repelRadius = 0.35 * (1.0 + held * 0.3);
  let interact = smoothstep(repelRadius, 0.0, dist);
  let curtainPart = normalize(distVec + vec2<f32>(0.0001)) * interact * 0.18;

  // Click ripple dispersion
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleDisp = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let wave = sin((rDist - age * 0.5) * 30.0) * exp(-rDist * 3.5) * exp(-age * 1.4);
    let rDir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
    rippleDisp += rDir * wave * 0.06;
  }

  let activeUV = clamp(uv - vec2<f32>(curtainPart.x / aspect, curtainPart.y) - rippleDisp, vec2<f32>(0.0), vec2<f32>(1.0));

  // Bead lattice geometry
  let pxActive = activeUV * resolution;
  let cellIndex = floor(pxActive / beadSize);
  let cellUV = fract(pxActive / beadSize) - 0.5;
  let rCell = length(cellUV);

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var color = src.rgb;
  var alpha = src.a;

  if (rCell < 0.48) {
    let z = sqrt(max(0.0, 0.2304 - rCell * rCell));
    let normal = normalize(vec3<f32>(cellUV, z));
    let glassThickness = 2.0 * z;

    // Refracted UV through spherical bead
    let refractOffset = -normal.xy * refractionStr;
    let refractUV = clamp(activeUV + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    // Fresnel reflection
    let cosTheta = clamp(normal.z, 0.0, 1.0);
    let R0 = 0.045;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cosTheta, 5.0);

    // Beer-Lambert physical transmission
    let glassColor = vec3<f32>(0.96, 0.98, 1.0);
    let absorption = exp(-(vec3<f32>(1.0) - glassColor) * glassThickness * 2.0);
    let transmission = (1.0 - fresnel) * dot(absorption, vec3<f32>(0.3333));

    // Load background through bead
    let beadSample = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).rgb;

    // Exact dataTextureC temporal ghost reflection inside bead
    let prevCoord = clamp(vec2<i32>(refractUV * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    let prevC = textureLoad(dataTextureC, prevCoord, 0).rgb;
    let beadBase = mix(beadSample, prevC, 0.15) * glassColor;

    // Thin-film interference on bead surface
    let cosThetaFilm = sqrt(max(1.0 - rCell * rCell * 1.5, 0.02));
    let filmNoise = hash12(cellIndex * 13.7 + time * 0.05) * 0.4;
    let filmThickness = filmThicknessBase * (0.8 + filmNoise);
    let filmIOR = 1.48;
    let iridescent = thinFilmColor(filmThickness, cosThetaFilm, filmIOR) * iridescenceIntensity;

    // Specular highlight on bead dome
    let lightDir = normalize(vec3<f32>(-0.6, -0.6, 0.9));
    let spec = pow(max(dot(normal, lightDir), 0.0), 24.0) * (0.65 + treble * 0.35);

    color = mix(beadBase, iridescent, fresnel * iridescenceIntensity * 0.65) + vec3<f32>(1.0, 0.98, 0.95) * spec;

    // Bead shadow rim
    let rimShadow = smoothstep(0.48, 0.44, rCell);
    color *= (0.85 + 0.15 * rimShadow);
    alpha = clamp(transmission + fresnel * 0.5 + spec * 0.3, 0.4, 1.0);
  } else {
    // Backdrop visible between bead strings with subtle shadow
    let gapDist = rCell - 0.48;
    let gapShadow = smoothstep(0.0, 0.1, gapDist);
    color = src.rgb * (0.88 + 0.12 * gapShadow);
    alpha = clamp(src.a * 0.9, 0.3, 1.0);
  }

  // Exact dataTextureC persistence
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prev, 0.06);

  // ACES Tonemap
  let finalRGB = aces(color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
