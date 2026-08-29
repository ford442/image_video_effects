// Aurora Rift Iridescence — dimensional auroral plasma rift with curl advection, Voronoi foam, and thin-film interference.
// A/C stores ACES display RGBA for continuous plasma trail persistence; B is unused; depth passes through source depth.

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

fn hash2(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    sum += amp * (hash2(p * freq + time * 0.1) - 0.5);
    freq *= 2.0;
    amp *= 0.5;
  }
  return sum;
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
  let eps = 0.001;
  let n1 = fbm(p + vec2<f32>(eps, 0.0), time);
  let n2 = fbm(p + vec2<f32>(0.0, eps), time);
  let n3 = fbm(p - vec2<f32>(eps, 0.0), time);
  let n4 = fbm(p - vec2<f32>(0.0, eps), time);
  return vec2<f32>(n2 - n4, n1 - n3) / (2.0 * eps);
}

fn voronoiCell(p: vec2<f32>) -> f32 {
  let i = floor(p);
  var best = 1e5;
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let cellPos = i + vec2<f32>(f32(x), f32(y));
      let seed = vec2<f32>(hash2(cellPos), hash2(cellPos + 13.37));
      let point = cellPos + seed - 0.5;
      let d = length(point - p);
      best = min(best, d);
    }
  }
  return best;
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
  for (var lambda = 400.0; lambda <= 700.0; lambda = lambda + 30.0) {
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

  let scale = 0.5 + u.zoom_params.x * 3.5;
  let flowSpeed = 0.2 + u.zoom_params.y * 2.5;
  let filmIOR = mix(1.2, 2.4, u.zoom_params.z);
  let intensity = mix(0.3, 1.8, u.zoom_params.w) * (1.0 + bass * 0.4);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mouse = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // Click ripple interaction
  var rippleOffset = vec2<f32>(0.0);
  var rippleBurst = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.35 + bass * 0.1);
      let wave = sin((rd - front) * 55.0) * exp(-abs(rd - front) * 25.0) * exp(-age * 1.1);
      rippleOffset += rDelta / max(rd, 0.0001) * wave * 0.025;
      rippleBurst += abs(wave) * 0.25;
    }
  }

  // Curl flow field
  let curl = curlNoise(uv * scale + rippleOffset, time * flowSpeed);

  // Mouse rift attractor
  let toMouse = (mouse - uv) * aspectVec;
  let mouseDist = length(toMouse);
  let mousePull = toMouse / max(mouseDist, 0.001) * exp(-mouseDist * 3.5) * select(0.04, 0.12, held);

  // Multi-layer parallax warp
  var totalWarp = vec2<f32>(0.0);
  var totalWeight = 0.0;
  for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
    let layerDepth = f32(layer) / 2.0;
    let layerWeight = 1.0 / (1.0 + abs(depth - layerDepth) * 12.0);
    let advected = curlNoise(uv * scale + curl * 0.3 + mousePull, time * flowSpeed * (1.0 + f32(layer) * 0.4));
    totalWarp += advected * 0.25 * layerWeight;
    totalWeight += layerWeight;
  }
  totalWarp = totalWarp / max(totalWeight, 0.0001);

  // Voronoi + FBM hybrid pattern
  let cellDist = voronoiCell(uv * scale * 2.0 + totalWarp);
  let fbmVal = fbm(uv * scale * 4.0 + curl, time);
  let foamPattern = smoothstep(0.0, 0.14, cellDist) * 0.6 + smoothstep(0.2, 0.4, fbmVal) * 0.4;

  // Phase interference waves
  let waveA = sin(length(uv - 0.5) * 28.0 - time * 3.2);
  let waveB = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 18.0 + time * 2.4);
  let waveC = sin(dot(uv - 0.5, vec2<f32>(1.1, 0.9)) * 30.0 - time * 3.8);
  let interference = (waveA * waveB * waveC + 1.0) * 0.5;

  let pattern = (foamPattern * 0.45 + interference * 0.3) * (1.0 + (1.0 - depth) * 1.2) * (1.0 + mids * 0.3);

  // Thin-film interference
  let toCenter = uv - vec2<f32>(0.5);
  let dist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

  let noiseVal = hash2(uv * 14.0 + time * 0.1) * 0.5 + hash2(uv * 28.0 - time * 0.15) * 0.25;
  let filmThicknessBase = mix(260.0, 760.0, pattern);
  var thickness = filmThicknessBase * (0.75 + depth * 0.5 + noiseVal * 0.4);

  if (held) {
    let mouseInfluence = exp(-mouseDist * mouseDist * 40.0);
    thickness += mouseInfluence * 280.0 * sin(time * 4.0 + mouseDist * 25.0);
  }

  let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * intensity;

  // Chromatic dispersion from aurora rift
  let disp = pattern * 0.025 * (1.0 + treble * 0.5);
  let rUV = clamp(uv + totalWarp * disp + curl * 0.014 + rippleOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + totalWarp * disp * 0.94 + curl * 0.01 + rippleOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv + totalWarp * disp * 1.06 - curl * 0.012 + rippleOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  let dispersed = vec3<f32>(r, g, b);

  let fresnel = pow(1.0 - cosTheta, 2.5);
  let blended = mix(dispersed, iridescent, fresnel * 0.65 + 0.35);

  let history = historyAt(uv - rippleOffset * 0.5, resolution);

  var hdr = mix(sourceColor.rgb, blended, 0.82) + vec3<f32>(rippleBurst);
  hdr += history.rgb * 0.06;

  let volAlpha = 1.0 - exp(-pattern * 2.2);
  let finalAlpha = clamp(sourceColor.a * 0.5 + volAlpha * 0.5 + rippleBurst * 0.1, 0.0, 1.0);

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), finalAlpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
