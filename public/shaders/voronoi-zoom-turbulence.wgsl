// ═══════════════════════════════════════════════════════════════════
//  Voronoi Zoom Turbulence
//  Category: geometric
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-11, 2026-11-20
//  Ideas: F2−F1 edge neon rim; bass-driven centroid inflation pulse; exact bisector wall distance → chamfer bevel (Worley border, tactic 1); turbulent lattice warp (§12.2E additive domain twist)
//  A packing: ACES display RGBA (cell agitation in alpha)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn satBoost(rgb: vec3<f32>, amount: f32) -> vec3<f32> {
  let luma = dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  return clamp(luma + (rgb - vec3<f32>(luma)) * (1.0 + amount), vec3<f32>(0.0), vec3<f32>(2.5));
}

fn palette(t: f32) -> vec3<f32> {
  return 0.55 + 0.45 * cos(TAU * (vec3<f32>(1.0, 0.82, 0.58) * t + vec3<f32>(0.00, 0.18, 0.42)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[1].x;
  let binB = plasmaBuffer[4].y;
  let binC = plasmaBuffer[7].z;

  var spring = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 10.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-2.5), vec2<f32>(2.5));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
  }

  let density = (3.0 + u.zoom_params.x * 5.0) * (1.0 + bass * 0.25 + binA * 0.08);
  let speed = u.zoom_params.y * (1.0 + mids * 0.45);
  let intensity = u.zoom_params.z * (1.0 + treble * 0.4);
  let mouseInfl = u.zoom_params.w;

  let uvScaled = vec2<f32>(uv.x * aspect, uv.y) * density;

  // Idea 4 — turbulent lattice warp (§12.2E additive domain twist): the lattice coordinate is
  // bent by a slow analytic travelling swirl before the cell lookup, so the walls curve and
  // breathe. Only the cell geometry moves: the image sample below is built from the un-warped
  // uvScaled plus the zoom shift, so the picture itself is not distorted. Rides the existing
  // Turbulence Speed role; amplitude stays under ~0.31 cell.
  let warpT = time * (0.16 + speed * 0.12);
  let warpAmp = 0.22 * (1.0 + mids * 0.4);
  let lat = uvScaled + warpAmp * vec2<f32>(
    sin(uvScaled.y * 0.9 + uvScaled.x * 0.35 + warpT),
    sin(uvScaled.x * 0.77 - uvScaled.y * 0.41 - warpT * 0.8));
  let iSt = floor(lat);
  let fSt = fract(lat);

  var minDist = 8.0;
  var second = 8.0;
  var minPoint = vec2<f32>(0.0);
  var cellId = vec2<f32>(0.0);
  var siteTan = vec2<f32>(1.0, 0.0);
  var third = 8.0;
  var secondVec = vec2<f32>(8.0, 0.0);
  var thirdVec = vec2<f32>(0.0, 8.0);

  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      var point = hash22(iSt + neighbor);
      point = 0.5 + 0.5 * sin(time * (0.45 + speed * 0.35) + TAU * point);
      let diff = neighbor + point - fSt;
      let dist = length(diff);
      let closer = dist < minDist;
      // Idea 3 bookkeeping: keep the 2nd/3rd nearest site vectors (branchless shift cascade).
      let nearer2 = dist < second;
      let nearer3 = dist < third;
      thirdVec = select(select(thirdVec, diff, nearer3), secondVec, nearer2);
      third = select(select(third, dist, nearer3), second, nearer2);
      secondVec = select(select(secondVec, diff, nearer2), minPoint, closer);
      second = select(min(second, dist), minDist, closer);
      minPoint = select(minPoint, diff, closer);
      cellId = select(cellId, iSt + neighbor, closer);
      minDist = min(minDist, dist);
    }
  }

  // Idea 3 — exact bisector wall distance (Worley border, tactic 1): F2−F1 stays as the neon-rim
  // proxy, but its width swells at vertices and with wall angle. The true distance to a bisector,
  // dot(0.5*(a+b), normalize(b−a)), has a constant width and also yields the wall normal (a → b).
  // The nearest wall of a pixel is the bisector against its 2nd or 3rd nearest site, both already
  // found by the loop above (taking the min of the two keeps it continuous at cell vertices).
  let abB = secondVec - minPoint;
  let nB = abB * inverseSqrt(max(dot(abB, abB), 1e-6));
  let wdB = dot(0.5 * (minPoint + secondVec), nB);
  let abC = thirdVec - minPoint;
  let nC = abC * inverseSqrt(max(dot(abC, abC), 1e-6));
  let wdC = dot(0.5 * (minPoint + thirdVec), nC);
  let useC = wdC < wdB;
  let wallDist = max(select(wdB, wdC, useC), 0.0);
  let wallN = select(nB, nC, useC);
  let bevelT = 1.0 - smoothstep(0.0, 0.16, wallDist);
  let bevelAmt = bevelT * bevelT;

  let edgeGap = second - minDist;
  let edge = clamp(edgeGap * 4.2, 0.0, 1.0);
  let neonRim = smoothstep(0.09, 0.0, edgeGap) * (0.4 + bass * 0.55 + treble * 0.15);
  let randVal = hash12(cellId);
  let cellTime = time * (0.85 + speed) + randVal * 10.0;
  var zoomFactor = 1.0 + sin(cellTime) * 0.48 * intensity + cos(cellTime * 0.71) * 0.22 * intensity;

  let distMouse = length((uv - spring) * vec2<f32>(aspect, 1.0));
  let infl = smoothstep(0.55, 0.0, distMouse) * abs(mouseInfl);
  let agitate = sin(time * 9.2 + randVal * TAU) * infl * 1.8;
  let stabilize = infl;
  zoomFactor = select(mix(zoomFactor, 1.0, stabilize), zoomFactor + agitate, mouseInfl > 0.0);
  zoomFactor = clamp(zoomFactor, 0.18, 3.4);

  var pulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 2.4;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    let front = exp(-abs(rd - age * 0.55) * 18.0) * exp(-age * 1.4);
    pulse = pulse + select(0.0, front, alive);
  }
  zoomFactor = zoomFactor + pulse * 0.55;

  let centroidPulse = 1.0 + bass * 0.42 * (0.5 + 0.5 * sin(time * 1.85 + randVal * TAU));
  let inflatedPoint = minPoint * centroidPulse;
  let offsetFromCenter = -inflatedPoint;
  let zoomShift = offsetFromCenter * (1.0 / max(zoomFactor, 0.12) - 1.0);
  let shearDir = vec2<f32>(-minPoint.y, minPoint.x);
  let shearLen = max(length(shearDir), 0.001);
  let conveyor = (shearDir / shearLen) * (1.0 - edge) * (0.08 + mids * 0.04 + binB * 0.03)
    * sin(time * (4.2 + speed * 2.0) + randVal * TAU);
  let holdPull = select(0.0, 0.12, held) * smoothstep(0.4, 0.0, distMouse);

  // Idea 3 (cont.) — convex glass-tile chamfer: toward each wall the sample reaches outward along
  // the wall normal (content compresses at the bevel, like a lenslet edge).
  let bevelShift = wallN * bevelAmt * 0.2;

  let uvScaledNew = uvScaled + zoomShift + conveyor - minPoint * holdPull + bevelShift;
  let uvNew = clamp(vec2<f32>(uvScaledNew.x / aspect, uvScaledNew.y) / max(density, 0.001), vec2<f32>(0.0), vec2<f32>(1.0));

  let src = textureSampleLevel(readTexture, u_sampler, uvNew, 0.0);
  let hist = textureLoad(dataTextureC, coord, 0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvNew, 0.0).r;

  let hueT = randVal + time * 0.07 + binC * 0.12 + minDist * 0.35;
  var hdr = satBoost(src.rgb, 0.28 + treble * 0.2);
  hdr = mix(hdr, hdr * palette(hueT), 0.22 + edge * 0.18);
  hdr = hdr + palette(hueT + 0.33) * pulse * 0.35;
  // Idea 3 (cont.) — the bevel facet catches a fixed key light from the upper left (uv y is down).
  hdr = hdr * (1.0 + bevelAmt * 0.34 * dot(wallN, vec2<f32>(-0.55, -0.83)));
  hdr = mix(hdr, hist.rgb, 0.18 + edge * 0.12);
  hdr = hdr + palette(hueT + 0.62) * neonRim * (1.15 + mids * 0.25);

  let rgb = acesToneMap(hdr * 1.08);
  let agitation = clamp(abs(zoomFactor - 1.0) * 0.85 + (1.0 - edge) * 0.35 + pulse * 0.4, 0.08, 0.98);
  let outCol = vec4<f32>(rgb, mix(src.a, agitation, 0.55));

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
