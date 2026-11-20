// ═══════════════════════════════════════════════════════════════════
//  Gravitational Lensing NLM — Relativistic Geodesics + Non-Local Means
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            schwarzschild-metric, non-local-means, semantic-alpha, ACES
//  Complexity: Very High
//  Upgraded: 2026-11-20
//  Ideas: Buades-form NLM weights (Gaussian patch + noise-bias subtraction, cached centre patch; §12.2 NLM kernel deepening); disk g-factor (gravitational redshift dims and reddens the disk by the Redshift slider); photon ring from closest approach
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=BlackHoleMass, y=DiskBrightness, z=CameraOrbit, w=Redshift

const MAX_STEPS: i32 = 96;
const MAX_DIST: f32 = 45.0;
const DT: f32 = 0.055;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn renderAccretionDisk(rayPos: vec3<f32>, rayDir: vec3<f32>, blackHolePos: vec3<f32>, mass: f32, redshiftAmount: f32) -> vec3<f32> {
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
      // ── Idea 2: disk g-factor ─────────────────────────────────────────
      // Beaming above is only the Doppler half of the g-factor. Emission from
      // deep in the well is also gravitationally redshifted: dimmer (I ∝ g³)
      // and shifted red, strongest at the inner edge. gravitationalRedshift()
      // was only ever applied to the far background; the Redshift slider (0 =
      // HEAD disk) now acts on the disk too.
      let gGrav = sqrt(max(1.0 - 2.0 * mass / max(distFromCenter, 2.0 * mass), 0.0));
      color = color * mix(vec3<f32>(1.0), gravitationalRedshift(distFromCenter, mass) * (gGrav * gGrav * gGrav), redshiftAmount);
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

// ── Idea 1: Buades-form NLM patch distance (§12.2 NLM kernel deepening) ──
// HEAD summed a flat 3×3 SSD and re-sampled the centre patch for every
// neighbour. Here the centre patch is fetched once by the caller, each tap is
// weighted by a Gaussian (sigma 1 px, scaled so the nine weights sum to 9 and
// hParam keeps its HEAD meaning), and the neighbour patch's centre tap comes
// back with the distance so the caller does not load it again.
fn patchDistance(centre: array<vec3<f32>, 9>, uv2: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
  var dist = 0.0;
  var nbCentre = vec3<f32>(0.0);
  for (var k = 0; k < 9; k = k + 1) {
    let dx = k % 3 - 1;
    let dy = k / 3 - 1;
    let d2 = dx * dx + dy * dy;
    let wk = 1.8377 * select(select(1.0, 0.6065, d2 == 1), 0.3679, d2 == 2);
    let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
    let p2 = textureSampleLevel(readTexture, u_sampler, clamp(uv2 + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let diff = centre[k] - p2;
    dist += dot(diff, diff) * wk;
    nbCentre = select(nbCentre, p2, k == 4);
  }
  return vec4<f32>(nbCentre, dist);
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

  // Rescue: HEAD built `right` as cross(up, forward) (that is LEFT) and added
  // `up * uvRaw.y` with uvRaw.y growing downward — a 180° roll, so the disk
  // "floor" rendered overhead. True right/up now, screen-y pointing down.
  let forward = normalize(blackHolePos - ro);
  let right = normalize(cross(forward, vec3<f32>(0.0, 1.0, 0.0)));
  let up = cross(right, forward);
  let rd = normalize(forward + right * uvRaw.x * aspect * 0.5 - up * uvRaw.y * 0.5);

  var rayPos = ro;
  var rayDir = rd;
  var color = vec3<f32>(0.0);
  var depth = 1.0;
  var rMin = 1e9;                       // Idea 3: periapsis of the bent ray

  for (var i: i32 = 0; i < MAX_STEPS; i = i + 1) {
    let toCenter = rayPos - blackHolePos;
    let r = length(toCenter);
    rMin = min(rMin, r);
    if (r < eventHorizon) {
      color = vec3<f32>(0.0);
      depth = 0.0;
      break;
    }
    if (r > MAX_DIST) {
      // Rescue companion: the 180° un-roll must not move the photo, so look the
      // panorama up along the direction HEAD's rolled camera would have used
      // (rotate the escaped direction 180° about the view axis).
      let bgDir = 2.0 * dot(rayDir, forward) * forward - rayDir;
      let bgUV = vec2<f32>(atan2(bgDir.z, bgDir.x) / 6.2831853 + 0.5, bgDir.y * 0.5 + 0.5);
      color = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb;
      let redshift = gravitationalRedshift(r, blackHoleMass);
      color = color * mix(vec3<f32>(1.0), redshift, redshiftIntensity);
      depth = 0.5 + r / MAX_DIST * 0.5;
      break;
    }

    let accel = -normalize(toCenter) * blackHoleMass / (r * r);

    let cursorPos3D = vec3<f32>((mouse.x - 0.5) * 6.0 * aspect, (0.5 - mouse.y) * 6.0, 0.0);
    let toCursor = cursorPos3D - rayPos;
    let rCursor = length(toCursor);
    let cursorMass = blackHoleMass * 0.25 * (1.0 + held * 2.0 + mids * 0.5);
    let cursorAccel = -normalize(toCursor) * cursorMass / (rCursor * rCursor + 0.1);

    rayDir = normalize(rayDir + (accel + cursorAccel) * DT);
    rayPos += rayDir * DT * r * 0.5;
  }

  let diskColor = renderAccretionDisk(ro, rd, blackHolePos, blackHoleMass, redshiftIntensity) * diskBrightness;
  color += diskColor;

  // ── Idea 3: photon ring from closest approach ───────────────────────
  // `r` is computed every step and discarded; its minimum is the periapsis.
  // Rays that escaped after grazing the horizon pile up on the photon sphere
  // and give the shadow a thin hot rim. Absorbed rays (rMin < horizon) get 0.
  let grazing = exp(-max(rMin / eventHorizon - 1.0, 0.0) / 0.05) * step(eventHorizon, rMin);
  color += vec3<f32>(1.0, 0.82, 0.55) * grazing * 1.0 * (1.0 + treble * 0.5);

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

  // Idea 1: centre patch fetched once (HEAD re-sampled it for all 24 neighbours)
  var centrePatch: array<vec3<f32>, 9>;
  for (var k = 0; k < 9; k = k + 1) {
    let o = vec2<f32>(f32(k % 3 - 1), f32(k / 3 - 1)) * pixelSize;
    centrePatch[k] = textureSampleLevel(readTexture, u_sampler, clamp(uv + o, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  }
  // Noise-bias term of the Buades weight: max(d² − 2σ², 0). Near-identical
  // patches reach weight 1 instead of 0.8–0.9, so flat sky smooths fully.
  let nlmBias = hParam * 0.22;

  for (var dy = -2; dy <= 2; dy = dy + 1) {
    for (var dx = -2; dx <= 2; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighborUV = clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999));
      let pdn = patchDistance(centrePatch, neighborUV, pixelSize);
      let weight = exp(-max(pdn.w - nlmBias, 0.0) / hParam);

      let neighborColor = pdn.xyz;
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
  let importance = clamp(1.0 - avgSimilarity + ringGlow * 0.4 + grazing * 0.25 + held * 0.15, 0.1, 1.0);
  let finalPixel = vec4<f32>(finalRGB, importance);

  textureStore(writeTexture, id, finalPixel);
  textureStore(dataTextureA, id, finalPixel);
  textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
