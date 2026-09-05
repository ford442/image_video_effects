// ═══════════════════════════════════════════════════════════════════
//  Gravitational Lensing — Schwarzschild Geodesics with Spectral Disk
//  Category: advanced-hybrid
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, schwarzschild-metric, geodesic-raytracing,
//            keplerian-disk, doppler-beaming, temporal-accretion,
//            depth-aware, upgraded-rgba, semantic-alpha, ACES
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Mass, y=DiskBrightness, z=CameraOrbit, w=Redshift
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 128;
const MAX_DIST: f32 = 50.0;
const DT: f32 = 0.05;

// ═══ ACES filmic tone map (Narkowicz fit) ═══
fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ BLACKBODY (Planck fit, temperature in Kelvin) ═══
fn blackbody(kelvin: f32) -> vec3<f32> {
  let t = clamp(kelvin, 1000.0, 40000.0) / 100.0;
  var r: f32;
  var g: f32;
  var b: f32;
  if (t <= 66.0) {
    r = 1.0;
    g = clamp((99.4708025861 * log(max(t, 1.0)) - 161.1195681661) / 255.0, 0.0, 1.0);
    if (t <= 19.0) {
      b = 0.0;
    } else {
      b = clamp((138.5177312231 * log(max(t - 10.0, 1.0)) - 305.0447927307) / 255.0, 0.0, 1.0);
    }
  } else {
    let lt = t - 60.0;
    r = clamp(329.698727446 * pow(max(lt, 1.0), -0.1332047592) / 255.0, 0.0, 1.0);
    g = clamp(288.1221695283 * pow(max(lt, 1.0), -0.0755148492) / 255.0, 0.0, 1.0);
    b = 1.0;
  }
  return vec3<f32>(r, g, b);
}

// ═══ ACCRETION DISK — Shakura-Sunyaev profile + Keplerian beaming ═══
fn renderAccretionDisk(
  rayPos: vec3<f32>,
  rayDir: vec3<f32>,
  blackHolePos: vec3<f32>,
  mass: f32,
  time: f32,
  clickPulse: f32
) -> vec3<f32> {
  let rs = 2.0 * mass;
  let innerRadius = rs * 3.0;   // ISCO for a Schwarzschild hole
  let outerRadius = rs * 15.0;

  let toCenter = blackHolePos - rayPos;
  if (abs(rayDir.y) < 1e-4) { return vec3<f32>(0.0); }
  let tHit = toCenter.y / rayDir.y;
  if (tHit <= 0.0) { return vec3<f32>(0.0); }

  let hitPos = rayPos + rayDir * tHit;
  let r = length(hitPos.xz - blackHolePos.xz);
  if (r <= innerRadius || r >= outerRadius) { return vec3<f32>(0.0); }

  // Shakura-Sunyaev: T ∝ r^(-3/4)
  let rNorm = r / innerRadius;
  let temperature = 30000.0 * pow(rNorm, -0.75);

  // Keplerian orbital speed (fraction of c) and relativistic Doppler beaming
  let beta = clamp(sqrt(rs / (2.0 * r)), 0.0, 0.85);
  let orbitalDir = normalize(vec3<f32>(-(hitPos.z - blackHolePos.z), 0.0, hitPos.x - blackHolePos.x));
  let cosAngle = dot(rayDir, orbitalDir);
  let gamma = 1.0 / sqrt(max(1.0 - beta * beta, 1e-4));
  let dopplerFactor = 1.0 / (gamma * max(1.0 - beta * cosAngle, 0.05));
  let beaming = dopplerFactor * dopplerFactor * dopplerFactor;

  var color = blackbody(temperature * dopplerFactor);

  // Per-band annuli
  let radialT = clamp((r - innerRadius) / (outerRadius - innerRadius), 0.0, 0.999);
  let bandIdx = u32(radialT * 8.0);
  let bandEnergy = plasmaBuffer[bandIdx + 1u].x;
  let ringPhase = sin(radialT * 40.0 - time * 2.0 + f32(bandIdx));
  let emissivity = 1.0 + bandEnergy * (1.2 + 0.8 * ringPhase) + clickPulse * 1.5;

  let falloff = smoothstep(outerRadius, innerRadius, r);
  let thermal = pow(rNorm, -1.5);
  return color * beaming * thermal * emissivity * falloff * 0.35;
}

fn gravitationalRedshift(r: f32, mass: f32) -> vec3<f32> {
  let rs = 2.0 * mass;
  let factor = sqrt(max(0.001, 1.0 - rs / max(r, rs)));
  return vec3<f32>(1.0, factor, factor * 0.8);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let id = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) / resolution - 0.5) * 2.0;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, isMouseDown);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
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

  // Bounded click shock rings
  var clickPulse = 0.0;
  var ringGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.6) {
      let rDist = length((vec2<f32>(global_id.xy) / resolution) - rp.xy);
      let front = rDist - age * 0.35;
      let env = exp(-front * front * 160.0) * exp(-age * 1.3);
      clickPulse += env;
      ringGlow += env * env;
    }
  }
  clickPulse = min(clickPulse, 1.5);
  ringGlow = min(ringGlow, 1.2);

  // Exact parameter contracts
  let blackHoleMass = mix(1.0, 5.0, u.zoom_params.x);
  let diskBrightness = mix(0.5, 3.0, u.zoom_params.y);
  let cameraOrbit = u.zoom_params.z * 6.2831853;
  let redshiftIntensity = u.zoom_params.w;

  let blackHolePos = vec3<f32>(0.0, 0.0, 0.0);
  let rs = 2.0 * blackHoleMass;
  let eventHorizon = rs * 1.05;

  let camDist = 20.0;
  let camAngle = time * 0.1 + cameraOrbit + bass * 0.25;
  let ro = vec3<f32>(cos(camAngle) * camDist, sin(camAngle * 0.3) * 5.0, sin(camAngle) * camDist);

  let forward = normalize(blackHolePos - ro);
  let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
  let up = cross(forward, right);
  let rd = normalize(forward + right * uv.x * aspect * 0.5 + up * uv.y * 0.5);

  var rayPos = ro;
  var rayDir = rd;
  var color = vec3<f32>(0.0);
  var depth = 1.0;

  for (var i = 0; i < MAX_STEPS; i = i + 1) {
    let toCenter = rayPos - blackHolePos;
    let r = length(toCenter);

    if (r < eventHorizon) {
      color = vec3<f32>(0.0);
      depth = 0.0;
      break;
    }

    if (r > MAX_DIST) {
      let bgUV = vec2<f32>(atan2(rayDir.z, rayDir.x) / 6.2831853 + 0.5, rayDir.y * 0.5 + 0.5);
      color = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb;

      let redshift = gravitationalRedshift(r, blackHoleMass);
      color = color * mix(vec3<f32>(1.0), redshift, redshiftIntensity);
      depth = 0.5 + r / MAX_DIST * 0.5;
      break;
    }

    let accel = -normalize(toCenter) * blackHoleMass / (r * r);

    let cursorPos3D = vec3<f32>((mouse.x - 0.5) * 6.0 * aspect, (mouse.y - 0.5) * 6.0, 0.0);
    let toCursor = cursorPos3D - rayPos;
    let rCursor = length(toCursor);
    let cursorMass = blackHoleMass * 0.25 * (1.0 + held * 2.0 + mids * 0.6);
    let cursorAccel = -normalize(toCursor) * cursorMass / (rCursor * rCursor + 0.1);

    rayDir = normalize(rayDir + (accel + cursorAccel) * DT);
    rayPos += rayDir * DT * r * 0.5;
  }

  let diskColor = renderAccretionDisk(ro, rd, blackHolePos, blackHoleMass, time, clickPulse) * diskBrightness;
  color += diskColor;

  let closestApproach = length(ro - blackHolePos);
  let einsteinRadius = sqrt(rs * closestApproach);
  let ringScreenR = clamp(einsteinRadius / camDist * 1.6, 0.12, 0.75);
  let toCenter2D = length(uv);
  let einsteinGlow = smoothstep(0.35, 0.0, abs(toCenter2D - ringScreenR)) * 0.5;
  color += vec3<f32>(0.9, 0.8, 0.6) * einsteinGlow * (1.0 + treble * 0.5);

  let cursorScreen = vec2<f32>((mouse.x - 0.5) * 2.0 * aspect, (mouse.y - 0.5) * 2.0);
  let distToCursor = length(uv - cursorScreen);
  let cursorGlow = (1.0 - smoothstep(0.0, 0.8, distToCursor)) * 0.3 * (1.0 + select(0.0, 1.0, isMouseDown));
  color += vec3<f32>(0.6, 0.7, 1.0) * cursorGlow;
  color += vec3<f32>(1.0, 0.85, 0.6) * ringGlow * (0.5 + bass * 0.8);

  // Exact dataTextureC persistence
  let prev = textureLoad(dataTextureC, id, 0);
  color = max(color, prev.rgb * (0.80 + treble * 0.06));

  color = acesFilm(color);

  let emission = clamp(dot(color, vec3<f32>(0.333)) + ringGlow * 0.5, 0.0, 1.0);
  let alpha = clamp(mix(0.15, 1.0, emission) * mix(1.0, 1.15, diskBrightness * 0.3) + held * 0.1, 0.05, 1.0);
  let outColor = vec4<f32>(color, alpha);

  textureStore(writeTexture, id, outColor);
  textureStore(dataTextureA, id, outColor);
  textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
