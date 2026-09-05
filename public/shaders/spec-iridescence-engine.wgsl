// ═══════════════════════════════════════════════════════════════════
//  spec-iridescence-engine — Thin-Film Interference & Spectral Optics
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            thin-film-interference, spectral-render, semantic-alpha, ACES
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
  zoom_params: vec4<f32>,  // x=FilmThickness, y=FilmIOR, z=Intensity, w=Turbulence
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
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
  for (var lambda = 380.0; lambda <= 700.0; lambda += 20.0) {
    let phase = opd / lambda;
    let interference = cos(phase * 6.2831853) * 0.5 + 0.5;
    color += wavelengthToRGB(lambda) * interference;
    sampleCount += 1.0;
  }
  return color / max(sampleCount, 1.0);
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
  let isMouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, isMouseDown);

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
  let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.x);
  let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
  var intensity = mix(0.3, 1.5, u.zoom_params.z) * (1.0 + bass * 0.35);
  let turbulence = mix(0.0, 1.0, u.zoom_params.w);

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let toCenter = uv - vec2<f32>(0.5);
  let dist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

  let noiseVal = hash12(uv * 12.0 + time * 0.1) * 0.5 + hash12(uv * 25.0 - time * 0.15) * 0.25;
  var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * turbulence);

  let lensVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let lensDist = length(lensVec);
  let lensG = exp(-(lensDist * lensDist) / 0.0625);
  thickness += 80.0 * lensG;

  if (isMouseDown) {
    let mouseInfluence = exp(-lensDist * lensDist * 600.0);
    thickness += mouseInfluence * 300.0 * sin(time * 3.0 + lensDist * 30.0);
  }

  // Click ripples
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age <= 1.8) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let ring = exp(-abs(rDist - age * 0.45) * 18.0);
      thickness += 150.0 * sin(age * 20.0 - rDist * 40.0) * exp(-age * 1.8) * ring;
    }
  }

  var iridescent = thinFilmColor(thickness, cosTheta, filmIOR);

  // Per-wavelength audio energy modulation
  iridescent = vec3<f32>(
    iridescent.r * (1.0 + plasmaBuffer[7u].x * 0.35),
    iridescent.g * (1.0 + plasmaBuffer[4u].x * 0.35),
    iridescent.b * (1.0 + plasmaBuffer[2u].x * 0.35 + treble * 0.2)
  ) * intensity;

  let fresnel = pow(1.0 - cosTheta, 3.0);
  var outColor = mix(baseColor, iridescent, fresnel * 0.75 + held * 0.1);

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  outColor = mix(outColor, prevC, 0.08);

  let finalRGB = aces(outColor);
  let thicknessAlpha = clamp(thickness / 1000.0 + fresnel * 0.3 + held * 0.1, 0.15, 1.0);
  let finalPixel = vec4<f32>(finalRGB, thicknessAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
