// ═══════════════════════════════════════════════════════════════════
//  Cyber Lens — Holographic Tactical Sensor & HUD
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-aberration,
//            hud-overlay, rolling-shutter, telemetry-rings, semantic-alpha, ACES
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=HUDScale, y=TargetSize, z=GlitchIntensity, w=ChromaticAberration
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash13(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hudFlicker(t: f32, bass: f32) -> f32 {
  return 1.0 - step(0.92 + bass * 0.06, fract(sin(t * 37.0) * 43758.5453)) * 0.35;
}

fn hexDist(p: vec2<f32>) -> f32 {
  let s = vec2<f32>(1.0, 1.732);
  let h = s * 0.5;
  let a = fract(p) - 0.5;
  let b = abs(a) - h;
  return dot(max(b, vec2<f32>(0.0)), vec2<f32>(1.0)) + min(max(b.x, b.y), 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / dims;
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let audio = plasmaBuffer[0].xyz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Exact parameter contracts
  let hudScale = mix(0.06, 0.45, u.zoom_params.x);
  let targetSize = mix(0.02, 0.18, u.zoom_params.y);
  let glitchIntensity = u.zoom_params.z;
  let chroma = u.zoom_params.w * 0.06;

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
    let stiffness = 50.0;
    let damping = 14.14; // 2 * sqrt(50)
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

  let flicker = hudFlicker(time, audio.x);
  let bassPulse = 1.0 + audio.x * 0.4;
  let timeWarp = time * bassPulse;

  // Rolling-shutter scan skew
  let rowTime = uv.y * (0.012 + audio.y * 0.018);
  let shutterPhase = time - rowTime;
  let skew = sin(shutterPhase * 3.1 + uv.y * 24.0) * (0.002 + glitchIntensity * 0.010) * (0.4 + audio.z * 1.4);
  let shutterUV = clamp(uv + vec2<f32>(skew, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  // Depth parallax between HUD layers
  let parallax1 = (uv - 0.5) * depth * 0.04;
  let parallax2 = (uv - 0.5) * depth * 0.015;
  let hudUV1 = uv - parallax1;
  let hudUV2 = uv - parallax2;

  // Chromatic aberration around mouse
  let offset = uv - mouse;
  let delta = vec2<f32>(offset.x * aspect, offset.y);
  let dist = length(delta);
  let dir = offset / max(length(offset), 1e-4);
  let lensMask = 1.0 - smoothstep(hudScale, hudScale + 0.03, dist);

  let split = dir * chroma * lensMask * (1.0 + audio.z * 0.6 + held * 0.4);
  var lensColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(shutterUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, shutterUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(shutterUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  // Glitch horizontal slice displacement
  let glitchSeed = floor(timeWarp * 4.0);
  let glitchLine = step(0.88, hash12(vec2<f32>(glitchSeed, uv.y * 40.0))) * glitchIntensity;
  let glitchOffset = (hash12(vec2<f32>(glitchSeed, floor(uv.y * 40.0))) - 0.5) * 0.08 * bassPulse;
  let glitchUV = vec2<f32>(shutterUV.x + glitchOffset * glitchLine, shutterUV.y);
  let glitchColor = textureSampleLevel(readTexture, u_sampler, clamp(glitchUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  lensColor = mix(lensColor, glitchColor, glitchLine);

  // Primary HUD grid
  let gridUV = hudUV1 * 48.0;
  let lineX = 1.0 - smoothstep(0.0, 0.05, abs(fract(gridUV.x - timeWarp * 0.5) - 0.5));
  let lineY = 1.0 - smoothstep(0.0, 0.05, abs(fract(gridUV.y + timeWarp * 0.2) - 0.5));
  let grid = max(lineX, lineY) * flicker * (0.5 + audio.y * 0.7);

  // Scan lines
  let scan = 0.85 + 0.15 * sin(uv.y * dims.y * 0.5 + timeWarp * 9.0);

  // Targeting reticle at mouse
  let reticleDist = length((hudUV1 - mouse) * vec2<f32>(aspect, 1.0));
  let reticleRing = smoothstep(targetSize, targetSize - 0.005, reticleDist) - smoothstep(targetSize - 0.005, targetSize - 0.01, reticleDist);
  let reticleCrossH = (1.0 - smoothstep(0.0, 0.003, abs(hudUV1.y - mouse.y))) * step(reticleDist, targetSize * 1.3);
  let reticleCrossV = (1.0 - smoothstep(0.0, 0.003, abs(hudUV1.x - mouse.x))) * step(reticleDist, targetSize * 1.3);
  let reticle = (reticleRing + reticleCrossH + reticleCrossV) * flicker;

  // Corner brackets
  let cornerUV = abs(hudUV2 - 0.5);
  let cornerBracket = step(cornerUV.x, 0.04) * step(cornerUV.y, 0.003) + step(cornerUV.x, 0.003) * step(cornerUV.y, 0.04);
  let corner = cornerBracket * flicker;

  // Hexagonal threat zone around mouse
  let hexUV = (hudUV2 - mouse) * vec2<f32>(aspect, 1.0) * 14.0;
  let hex = 1.0 - smoothstep(0.0, 0.04, abs(hexDist(hexUV) - 0.42));
  let hexPulse = sin(timeWarp * 3.0 + audio.x * 6.0) * 0.5 + 0.5;
  let threat = hex * hexPulse * flicker;

  // Cyan holographic HUD composition
  let hudColor = vec3<f32>(0.05, 0.95, 0.95) * (grid + corner * 0.8) +
                 vec3<f32>(0.95, 0.35, 1.0) * reticle * 0.9 +
                 vec3<f32>(1.0, 0.2, 0.3) * threat * 0.7;

  let bloom = reticle * 0.5 * (1.0 + audio.y * 0.6);
  let grain = (hash13(vec3<f32>(uv * 300.0, time)) - 0.5) * 0.03;
  let radialGlow = exp(-dist * 4.0) * 0.12 * bassPulse;

  // Per-band HUD telemetry rings
  let toReticle = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let ringR = length(toReticle);
  let ringA = atan2(toReticle.y, toReticle.x);
  var telemetry = 0.0;
  for (var b = 0u; b < 8u; b = b + 1u) {
    let fb = f32(b);
    let energy = plasmaBuffer[b + 1u].x;
    let radius = targetSize * (1.6 + fb * 0.42);
    let band = exp(-pow((ringR - radius) * 210.0, 2.0));
    let sweep = ringA + time * (0.6 + fb * 0.23) * select(1.0, -1.0, (b & 1u) == 1u);
    let arc = smoothstep(0.0, 0.35, sin(sweep) * 0.5 + 0.5 - (1.0 - energy) * 0.6);
    telemetry += band * arc * (0.25 + energy * 1.5);
  }
  telemetry = min(telemetry, 2.0);

  // Click target-lock pings
  var lockPing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.0) {
      let r = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let front = r - age * 0.45;
      lockPing += exp(-front * front * 320.0) * exp(-age * 1.6);
    }
  }
  lockPing = min(lockPing, 1.5);

  var finalColor = lensColor * scan + hudColor + vec3<f32>(bloom) + grain + radialGlow;
  finalColor += vec3<f32>(0.25, 1.0, 0.75) * telemetry * 0.35;
  finalColor += vec3<f32>(1.0, 0.55, 0.25) * lockPing * (0.5 + audio.x * 0.8);

  // Phosphor persistence (exact dataTextureC load)
  let prevFrame = textureLoad(dataTextureC, coord, 0);
  finalColor = max(finalColor, prevFrame.rgb * (0.70 + glitchIntensity * 0.14));

  finalColor = acesToneMap(finalColor);

  let vignette = 1.0 - smoothstep(0.3, 0.8, dist) * 0.2;
  finalColor = finalColor * vignette;

  let hudIntensity = clamp(lensMask + grid * 0.5 + reticle * 0.8 + corner * 0.4 + telemetry * 0.3, 0.0, 1.0);
  let targetingConfidence = smoothstep(targetSize * 2.0, 0.0, reticleDist);
  let finalAlpha = clamp(hudIntensity * targetingConfidence * depth + lockPing * 0.25 + telemetry * 0.15 + 0.1, 0.08, 0.98);

  let outDepth = clamp(mix(depth, 0.3 + hudIntensity * 0.5, 0.25), 0.0, 1.0);

  let outColor = vec4<f32>(finalColor, finalAlpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
