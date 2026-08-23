// ═══════════════════════════════════════════════════════════════════
//  distortion-gravitational-prismatic — Gravitational Lensing & Cauchy Dispersion
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            gravitational-lensing, spectral-dispersion, semantic-alpha, ACES
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=LensStrength, y=MassCount, z=DiskIntensity, w=CauchyDispersion
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

struct Mass {
  pos: vec2<f32>,
  mass: f32,
  radius: f32,
};

fn deflectionAngle(rayPos: vec2<f32>, mass: Mass) -> vec2<f32> {
  let delta = rayPos - mass.pos;
  let dist2 = dot(delta, delta);
  let dist = sqrt(dist2);
  if (dist < mass.radius * 0.1) {
    return vec2<f32>(0.0);
  }
  let deflectionMagnitude = mass.mass * mass.radius / (dist + 0.001);
  return -normalize(delta) * deflectionMagnitude;
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

fn accretionDiskColor(radius: f32, innerRadius: f32) -> vec3<f32> {
  let temp = pow(innerRadius / radius, 0.75);
  var color: vec3<f32>;
  if (temp > 0.8) {
    color = vec3<f32>(1.0, 0.9, 0.8);
  } else if (temp > 0.6) {
    color = vec3<f32>(1.0, 0.6, 0.3);
  } else if (temp > 0.4) {
    color = vec3<f32>(0.8, 0.2, 0.1);
  } else {
    color = vec3<f32>(0.3, 0.05, 0.05);
  }
  return color * temp * temp;
}

fn einsteinRadius(mass: f32, distance: f32) -> f32 {
  return sqrt(mass) * distance * 0.1;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
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

  // Exact parameter contracts
  let lensStrength = (0.5 + u.zoom_params.x) * (1.0 + bass * 0.3);
  let numMasses = i32(u.zoom_params.y * 4.0) + 1;
  let diskIntensity = u.zoom_params.z * (1.0 + mids * 0.25);
  let cauchyB = mix(0.01, 0.08, u.zoom_params.w) * (1.0 + treble * 0.35);

  var masses: array<Mass, 5>;
  masses[0] = Mass(mouse, 2.0 + held * 1.5, 0.02 * lensStrength);
  for (var i: i32 = 1; i < 5; i = i + 1) {
    if (i < numMasses) {
      let fi = f32(i);
      let angle = time * 0.2 + fi * (2.0 * PI / f32(numMasses - 1));
      let radius = 0.2 + fi * 0.1;
      masses[i] = Mass(
        vec2<f32>(mouse.x + cos(angle) * radius, mouse.y + sin(angle) * radius),
        0.5,
        0.01 * lensStrength
      );
    }
  }

  var rayPos = uv;
  var totalDeflection = vec2<f32>(0.0);
  for (var i: i32 = 0; i < numMasses; i = i + 1) {
    totalDeflection += deflectionAngle(rayPos, masses[i]);
  }

  // Click ripples create extra deflection waves
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let delta = uv - r.xy;
      let rDist = length(delta * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.6) * 30.0) * exp(-rDist * 5.0) * exp(-age * 1.5);
      totalDeflection += normalize(delta + vec2<f32>(1e-5)) * wave * 0.04;
    }
  }

  // Prismatic dispersion
  let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
  var finalColor = vec3<f32>(0.0);

  for (var w: i32 = 0; w < 4; w = w + 1) {
    let ior = cauchyIOR(WAVELENGTHS[w], 1.5, cauchyB);
    let deflectScale = 1.0 + (ior - 1.5) * 2.0;
    let sourcePos = clamp(rayPos - totalDeflection * 0.5 * deflectScale, vec2<f32>(0.001), vec2<f32>(0.999));
    let sample = textureSampleLevel(readTexture, u_sampler, sourcePos, 0.0);
    let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[w]));
    finalColor += wavelengthToRGB(WAVELENGTHS[w]) * bandIntensity;
  }

  // Accretion disk
  let toPrimary = uv - masses[0].pos;
  let distPrimary = length(toPrimary * vec2<f32>(aspect, 1.0));
  let innerDisk = masses[0].radius * 3.0;
  let outerDisk = masses[0].radius * 15.0;
  if (distPrimary > innerDisk && distPrimary < outerDisk) {
    let diskTemp = accretionDiskColor(distPrimary, innerDisk);
    let diskPattern = sin(atan2(toPrimary.y, toPrimary.x) * 20.0 + time * 2.0);
    let diskGlow = smoothstep(outerDisk, innerDisk, distPrimary) * (0.7 + diskPattern * 0.3);
    let diskColor = diskTemp * diskGlow * diskIntensity * (1.0 + bass * 0.4);
    finalColor += diskColor;
  }

  // Einstein ring
  let einsteinR = einsteinRadius(masses[0].mass, distPrimary);
  let ringDist = abs(distPrimary - einsteinR);
  let ringGlow = smoothstep(0.02, 0.0, ringDist) * lensStrength;
  let ringSpectrum = wavelengthToRGB(550.0 + sin(time * 2.0) * 100.0);
  finalColor += ringSpectrum * ringGlow * 0.55;

  // Gravitational redshift
  let redshift = smoothstep(masses[0].radius * 10.0, masses[0].radius, distPrimary);
  finalColor = vec3<f32>(finalColor.r * (1.0 + redshift * 0.3), finalColor.g, finalColor.b * max(1.0 - redshift * 0.2, 0.0));

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, coord, 0).rgb;
  finalColor = mix(finalColor, prevC, 0.08);

  let finalRGB = aces(finalColor);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(0.35 + length(totalDeflection) * 12.0 + ringGlow * 0.3 + held * 0.15, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(dataTextureA, coord, finalPixel);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
