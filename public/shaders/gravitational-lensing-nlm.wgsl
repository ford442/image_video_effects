// ═══════════════════════════════════════════════════════════════════
//  Gravitational Lensing NLM — Relativistic Geodesics + Non-Local Means
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            schwarzschild-metric, non-local-means, semantic-alpha, ACES
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
  zoom_params: vec4<f32>,  // x=BlackHoleMass, y=DiskBrightness, z=CameraOrbit, w=Redshift
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 96;
const MAX_DIST: f32 = 45.0;
const DT: f32 = 0.055;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn renderAccretionDisk(rayPos: vec3<f32>, rayDir: vec3<f32>, blackHolePos: vec3<f32>, mass: f32) -> vec3<f32> {
  let rs = 2.0 * mass;
  let innerRadius = rs * 2.8;
  let outerRadius = rs * 14.0;
  let toCenter = blackHolePos - rayPos;
  if (abs(rayDir.y) < 1e-4) { return vec3<f32>(0.0); }
  let t = toCenter.y / rayDir.y;
  if (t > 0.0) {
    let hitPos = rayPos + rayDir * t;
    let distFromCenter = length(hitPos.xz - blackHolePos.xz);
    if (distFromCenter > innerRadius && distFromCenter < outerRadius) {
      let temp = 1.0 - (distFromCenter - innerRadius) / (outerRadius - innerRadius);
      let orbitalVel = normalize(vec3<f32>(-(hitPos.z - blackHolePos.z), 0.0, hitPos.x - blackHolePos.x));
      let doppler = dot(rayDir, orbitalVel);
      let beaming = pow(max(1.0 + doppler, 0.1), 3.0);
      var color = vec3<f32>(0.0);
      if (temp > 0.8) { color = vec3<f32>(1.0, 0.92, 0.75); }
      else if (temp > 0.5) { color = vec3<f32>(1.0, 0.55, 0.22); }
      else { color = vec3<f32>(0.85, 0.25, 0.12); }
      color = color * beaming * temp * temp;
      return color * smoothstep(outerRadius, innerRadius, distFromCenter);
    }
  }
  return vec3<f32>(0.0);
}

fn gravitationalRedshift(r: f32, mass: f32) -> vec3<f32> {
  let rs = 2.0 * mass;
  let factor = sqrt(max(0.001, 1.0 - rs / max(r, rs)));
  return vec3<f32>(1.0, factor, factor * 0.8);
}

fn patchDistance(uv1: vec2<f32>, uv2: vec2<f32>, pixelSize: vec2<f32>) -> f32 {
  var dist = 0.0;
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let p1 = textureSampleLevel(readTexture, u_sampler, clamp(uv1 + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
      let p2 = textureSampleLevel(readTexture, u_sampler, clamp(uv2 + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
      let diff = p1 - p2;
      dist += dot(diff, diff);
    }
  }
  return dist;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let id = vec2<i32>(global_id.xy);
  let uvRaw = (vec2<f32>(global_id.xy) / resolution - 0.5) * 2.0;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

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
  let blackHoleMass = mix(1.0, 5.0, u.zoom_params.x) * (1.0 + bass * 0.2);
  let diskBrightness = mix(0.5, 3.0, u.zoom_params.y) * (1.0 + mids * 0.25);
  let cameraOrbit = u.zoom_params.z * 6.2831853;
  let redshiftIntensity = u.zoom_params.w;

  let blackHolePos = vec3<f32>(0.0, 0.0, 0.0);
  let rs = 2.0 * blackHoleMass;
  let eventHorizon = rs * 1.05;

  let camDist = 20.0;
  let camAngle = time * 0.1 + cameraOrbit + bass * 0.2;
  let ro = vec3<f32>(cos(camAngle) * camDist, sin(camAngle * 0.3) * 5.0, sin(camAngle) * camDist);

  let forward = normalize(blackHolePos - ro);
  let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
  let up = cross(forward, right);
  let rd = normalize(forward + right * uvRaw.x * aspect * 0.5 + up * uvRaw.y * 0.5);

  var rayPos = ro;
  var rayDir = rd;
  var color = vec3<f32>(0.0);
  var depth = 1.0;

  for (var i: i32 = 0; i < MAX_STEPS; i = i + 1) {
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
    let cursorMass = blackHoleMass * 0.25 * (1.0 + held * 2.0 + mids * 0.5);
    let cursorAccel = -normalize(toCursor) * cursorMass / (rCursor * rCursor + 0.1);

    rayDir = normalize(rayDir + (accel + cursorAccel) * DT);
    rayPos += rayDir * DT * r * 0.5;
  }

  let diskColor = renderAccretionDisk(ro, rd, blackHolePos, blackHoleMass) * diskBrightness;
  color += diskColor;

  let closestApproach = length(ro - blackHolePos);
  let einsteinRadius = sqrt(rs * closestApproach);
  let ringScreenR = clamp(einsteinRadius / camDist * 1.6, 0.12, 0.75);
  let toCenter2D = length(uvRaw);
  let ringGlow = smoothstep(0.35, 0.0, abs(toCenter2D - ringScreenR)) * 0.5;
  color += vec3<f32>(0.9, 0.8, 0.6) * ringGlow * (1.0 + treble * 0.5);

  let lensingColor = color;

  // Non-Local Means patch filtering
  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let hParam = 0.015;

  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  var similaritySum = 0.0;

  for (var dy = -2; dy <= 2; dy = dy + 1) {
    for (var dx = -2; dx <= 2; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighborUV = clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999));
      let pd = patchDistance(uv, neighborUV, pixelSize);
      let weight = exp(-pd / hParam);

      let neighborColor = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0).rgb;
      accumColor += neighborColor * weight;
      accumWeight += weight;
      similaritySum += weight;
    }
  }

  accumColor += lensingColor;
  accumWeight += 1.0;
  similaritySum += 1.0;

  var result = accumColor / max(accumWeight, 0.0001);
  let avgSimilarity = similaritySum / 25.0;
  result = mix(result, lensingColor, 0.65 + held * 0.25);

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, id, 0).rgb;
  result = mix(result, prevC, 0.07);

  let finalRGB = aces(result);
  let importance = clamp(1.0 - avgSimilarity + ringGlow * 0.4 + held * 0.15, 0.1, 1.0);
  let finalPixel = vec4<f32>(finalRGB, importance);

  textureStore(writeTexture, id, finalPixel);
  textureStore(dataTextureA, id, finalPixel);
  textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
