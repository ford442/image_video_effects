// Vaporwave Horizon Prismatic — retro synthwave perspective grid with 4-band Cauchy spectral reflection and sunset sky.
// A/C stores ACES display RGBA for CRT phosphor persistence; B is unused; depth passes through source depth.

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

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
  let lambdaUm = wavelengthNm * 0.001;
  return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
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

  let gridSpeed = 0.2 + u.zoom_params.x * 2.5;
  let glowIntensity = (0.25 + u.zoom_params.y * 2.2) * (1.0 + bass * 0.45);
  let gridScale = 0.3 + u.zoom_params.z * 1.8;
  let warpAmount = 0.1 + u.zoom_params.w * 1.6;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let horizon = select(0.52, clamp(rawMouse.y, 0.2, 0.8), hasMouse);
  let mouseX = select(0.5, rawMouse.x, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // Click ripple interaction
  var rippleOffset = vec2<f32>(0.0);
  var rippleGlow = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.34 + bass * 0.12);
      let wave = sin((rd - front) * 58.0) * exp(-abs(rd - front) * 25.0) * exp(-age * 1.1);
      rippleOffset += rDelta / max(rd, 0.0001) * wave * 0.025;
      rippleGlow += abs(wave) * 0.2;
    }
  }

  let curve = (mouseX - 0.5) * 3.0 * warpAmount;
  let heldBoost = select(1.0, 1.5, held);

  var outRGB = vec3<f32>(0.0);
  var alpha = 1.0;

  if (uv.y < horizon) {
    // ═══ SKY REGION ═══
    let skyNormY = uv.y / max(horizon, 0.01);
    let skyUV = vec2<f32>(uv.x, skyNormY) + rippleOffset;
    let bgSky = textureSampleLevel(readTexture, u_sampler, clamp(skyUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    // Sunset gradient (deep violet top to fiery magenta/orange bottom)
    let violet = vec3<f32>(0.12, 0.04, 0.28);
    let magenta = vec3<f32>(0.85, 0.12, 0.55);
    let orange = vec3<f32>(1.0, 0.55, 0.15) * (1.0 + mids * 0.3);
    let skyGradient = mix(violet, mix(magenta, orange, pow(skyNormY, 2.0)), skyNormY);

    // Glowing retro sun disc centered on horizon
    let sunPos = vec2<f32>(0.5, horizon);
    let sunDelta = (uv - sunPos) * aspectVec;
    let sunDist = length(sunDelta);
    let sunRadius = 0.22 * heldBoost;
    let sunDisc = smoothstep(sunRadius, sunRadius - 0.015, sunDist);

    // Horizontal retro blinds stripes across the sun
    let stripeY = fract((uv.y - horizon + sunRadius) * 24.0);
    let stripeGap = smoothstep(0.0, 0.35, skyNormY) * 0.45;
    let stripeMask = step(stripeGap, stripeY);
    let stripedSun = sunDisc * stripeMask;

    // Sun gradient (yellow top, magenta bottom)
    let sunColor = mix(vec3<f32>(1.2, 0.9, 0.2), vec3<f32>(1.0, 0.15, 0.5), (uv.y - (horizon - sunRadius)) / (2.0 * sunRadius));
    let sunGlow = exp(-sunDist * 8.0) * glowIntensity * 0.75 * vec3<f32>(1.0, 0.3, 0.6);

    outRGB = mix(bgSky * 0.6 + skyGradient * 0.7, sunColor * 1.5, stripedSun) + sunGlow;
    alpha = 0.92;
  } else {
    // ═══ FLOOR REGION (Prismatic Perspective Grid) ═══
    let dy = max(uv.y - horizon, 0.001);
    let zDepth = 1.0 / dy;
    let xOffset = curve * dy * dy;

    let gridU = (uv.x - 0.5 - xOffset + rippleOffset.x) * zDepth * (0.4 + gridScale * 0.6) + 0.5;
    let gridV = zDepth * (0.4 + gridScale * 0.6) + time * gridSpeed * heldBoost + rippleOffset.y * 10.0;

    let gridX = abs(fract(gridU) - 0.5);
    let gridY = abs(fract(gridV) - 0.5);
    let lineWidth = 0.06 * (1.0 + dy * 0.5);
    let lineMask = smoothstep(lineWidth, 0.0, gridX) + smoothstep(lineWidth, 0.0, gridY);
    let gridVal = clamp(lineMask, 0.0, 1.0);

    // 4-band spectral Cauchy reflection
    let reflY = clamp(horizon - dy, 0.0, 1.0);
    let reflUV = vec2<f32>(uv.x, reflY);

    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var reflColor = vec3<f32>(0.0);
    let cauchyB = 0.04 * warpAmount;

    for (var i: i32 = 0; i < 4; i = i + 1) {
      let lambda = WAVELENGTHS[i];
      let ior = cauchyIOR(lambda, 1.45, cauchyB);
      let dispOffset = (reflUV - vec2<f32>(0.5, horizon)) * (1.0 - 1.0 / ior) * 0.2;
      let sampleUV = clamp(reflUV + dispOffset, vec2<f32>(0.0), vec2<f32>(1.0));
      let sampleCol = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      let spectralWeight = wavelengthToRGB(lambda);
      reflColor += spectralWeight * dot(sampleCol, spectralWeight) * 0.45;
    }

    // Neon cyan grid color with magenta intersections
    let neonCyan = vec3<f32>(0.05, 0.95, 1.0) * glowIntensity * 1.8;
    let neonMagenta = vec3<f32>(1.0, 0.1, 0.8) * glowIntensity * 2.2;
    let gridColor = mix(neonCyan, neonMagenta, gridX * gridY * 4.0) * gridVal;

    // Reflection blend with floor
    let reflectionFade = smoothstep(0.0, 0.35, dy);
    let floorBase = reflColor * 0.65 * reflectionFade;

    // Volumetric distance fog near horizon
    let fogDist = zDepth * 0.25;
    let fogDensity = exp(-fogDist * 0.8);
    let fogColor = vec3<f32>(0.45, 0.08, 0.4) * (1.0 + mids * 0.3);

    outRGB = mix(fogColor, floorBase + gridColor, 1.0 - fogDensity * 0.85);
    alpha = clamp(0.85 + gridVal * 0.15, 0.0, 1.0);
  }

  // Exact previous frame history load for CRT phosphor glow
  let history = historyAt(uv - rippleOffset * 0.5, resolution);

  var hdr = outRGB + vec3<f32>(rippleGlow);
  hdr += history.rgb * 0.06;

  // CRT scanlines
  let scanline = 0.94 + 0.06 * sin(uv.y * resolution.y * 3.14159);
  hdr *= scanline;

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
