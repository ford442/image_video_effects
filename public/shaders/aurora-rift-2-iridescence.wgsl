// Aurora Rift 2 Iridescence — 5-layer volumetric aurora curtains with thin-film interference, Beer's Law, and geomagnetic turbulence.
// A/C stores ACES display RGBA for atmospheric luminescence persistence; B is unused; depth passes through layered depth.

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

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u_vec = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u_vec.x),
             mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u_vec.x), u_vec.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value += amplitude * noise(p * frequency);
    frequency *= 2.0;
    amplitude *= 0.5;
  }
  return value;
}

fn physicalTransmittance(baseColor: vec3<f32>, opticalDepth: f32, absorptionCoeff: vec3<f32>) -> vec3<f32> {
  let transmittance = exp(-absorptionCoeff * opticalDepth);
  return baseColor * transmittance;
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
  for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 30.0) {
    let phase = opd / lambda;
    let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
    color += wavelengthToRGB(lambda) * interference;
    sampleCount = sampleCount + 1.0;
  }
  return color / max(sampleCount, 1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let intensity = (0.3 + u.zoom_params.x * 1.8) * (1.0 + bass * 0.35);
  let speed = (0.2 + u.zoom_params.y * 1.8) * (1.0 + mids * 0.25);
  let depthWeight = clamp(u.zoom_params.z, 0.0, 1.0);
  let turbulence = (0.5 + u.zoom_params.w * 2.5) * (1.0 + mids * 0.3);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mousePos = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let isMouseDown = u.zoom_config.w > 0.5;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Viewing angle from center
  let toCenter = uv - vec2<f32>(0.5);
  let dist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));
  let fresnel = pow(1.0 - cosTheta, 3.0);

  // Click ripple interactions
  var ripplePerturb = vec2<f32>(0.0);
  var rippleLight = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.35 + bass * 0.15);
      let wave = sin((rd - front) * 55.0) * exp(-abs(rd - front) * 22.0) * exp(-age * 1.1);
      ripplePerturb += rDelta / max(rd, 0.0001) * wave * 0.03;
      rippleLight += abs(wave) * 0.25;
    }
  }

  let filmThicknessBase = mix(200.0, 800.0, 0.3 + u.zoom_params.x * 0.4);
  let filmIOR = mix(1.2, 2.4, 0.3 + turbulence * 0.15);
  let iridIntensity = mix(0.5, 2.2, intensity);

  // Aurora curtain simulation
  let curtainUV = (uv + ripplePerturb) * vec2<f32>(3.0, 1.0);
  var accumulatedLight = vec3<f32>(0.0);
  var accumulatedOpticalDepth = 0.0;

  for (var i: i32 = 0; i < 5; i = i + 1) {
    let layer = f32(i);
    let layerOffset = vec2<f32>(time * speed * 0.08 * (1.0 + layer * 0.12), 0.0);

    let n1 = fbm(curtainUV + layerOffset + vec2<f32>(layer * 10.0), 3);
    let n2 = fbm(curtainUV * 2.0 - layerOffset * 0.5 + vec2<f32>(layer * 5.0), 2);

    let curtainY = 0.35 + n1 * 0.35 + n2 * 0.15;
    let curtainWidth = 0.12 + n2 * 0.08;
    let distFromCurtain = abs(uv.y - curtainY);
    let curtainIntensity = smoothstep(curtainWidth, 0.0, distFromCurtain);

    let layerOpticalDepth = curtainIntensity * (0.25 + n1 * 0.35);

    let noiseVal = hash12(uv * 12.0 + layer * 7.0 + time * 0.1) * 0.5
                 + hash12(uv * 25.0 - layer * 3.0 - time * 0.15) * 0.25;

    var thickness = filmThicknessBase * (0.7 + depth * 0.6 * depthWeight + noiseVal * turbulence + layer * 0.15);

    if (hasMouse) {
      let mouseDelta = (uv - mousePos) * aspectVec;
      let mouseDist = length(mouseDelta);
      let mouseInfluence = exp(-mouseDist * mouseDist * select(100.0, 250.0, isMouseDown));
      thickness += mouseInfluence * 320.0 * sin(time * 3.5 + mouseDist * 25.0);
    }

    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * iridIntensity;
    let transmittance = exp(-accumulatedOpticalDepth * 2.0);

    accumulatedLight += iridescent * layerOpticalDepth * transmittance;
    accumulatedOpticalDepth += layerOpticalDepth;
  }

  // Background sample
  let bgSample = textureSampleLevel(readTexture, u_sampler, uv + ripplePerturb * 0.5, 0.0);

  // Beer's Law physical transmittance
  let absorptionCoeff = vec3<f32>(0.5, 0.3, 0.8);
  let transmitted = physicalTransmittance(bgSample.rgb, accumulatedOpticalDepth, absorptionCoeff);

  var finalColor = transmitted + accumulatedLight;

  // Rim iridescence from Fresnel
  let rimIrid = thinFilmColor(filmThicknessBase * 1.2, cosTheta, filmIOR) * fresnel * 0.6 * (1.0 + treble * 0.4);
  finalColor += rimIrid + vec3<f32>(rippleLight);

  // Exact previous frame history load for luminescence persistence
  let history = historyAt(uv - ripplePerturb * 0.5, resolution);
  var hdr = finalColor + history.rgb * 0.06;

  // Semantic alpha: composite coverage + atmospheric density
  let density = accumulatedOpticalDepth * 2.0;
  let volAlpha = 1.0 - exp(-density * 1.5);
  let depthAlpha = mix(1.0, mix(0.4, 1.0, depth), depthWeight);
  let alpha = clamp(volAlpha * depthAlpha + bgSample.a * 0.35, 0.0, 1.0);

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
