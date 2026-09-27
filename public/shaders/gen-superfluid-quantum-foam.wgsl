// ═══════════════════════════════════════════════════════════════════
//  Superfluid Quantum-Foam
//  Category: generative
//  Features: mouse-driven, audio-reactive, raymarched, temporal, chromatic, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: coalescing bubble necks (8-neighbour smooth-min); film-drainage black-film pop (burst shells); Kelvin-wave vortex filament (hollow core + 1/r swirl)
//  A packing: ACES display RGBA, premultiplied (col*alpha, alpha) - unchanged; C read back as colour history
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash13(p3: vec3<f32>) -> f32 {
  var p = fract(p3 * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
  var p = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.xxy + p.yxx) * p.zyx);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Smooth two-octave vector potential for the current. (Bug fix 2026-09-27: HEAD differenced
// hash33 white noise, which gave a discontinuous random warp of up to ~6 units that shattered
// the bubbles into shards; its z term was not a curl either.)
fn flowPotential(q: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(
    sin(q.y * 1.3 + cos(q.z * 0.9) * 1.1),
    sin(q.z * 1.1 + cos(q.x * 1.2) * 1.1),
    sin(q.x * 1.2 + cos(q.y * 0.8) * 1.1)) * 0.65;
  return a + sin(q.zxy * 2.3 + q.yzx * 0.7 + 1.7) * 0.25;
}

fn curlNoise(p: vec3<f32>) -> vec3<f32> {
  let e = vec3<f32>(0.05, 0.0, 0.0);
  let n1 = flowPotential(p + e);
  let n2 = flowPotential(p - e);
  let n3 = flowPotential(p + e.zxy);
  let n4 = flowPotential(p - e.zxy);
  let n5 = flowPotential(p + e.yzx);
  let n6 = flowPotential(p - e.yzx);
  // central-difference curl: (dPz/dy - dPy/dz, dPx/dz - dPz/dx, dPy/dx - dPx/dy)
  return vec3<f32>(n3.z - n4.z - n5.y + n6.y, n5.x - n6.x - n1.z + n2.z, n1.y - n2.y - n3.x + n4.x) * 10.0;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

// ═══ Idea 3: Kelvin-wave vortex filament ═══
// Quantized vortex line through the vortex centre (vertical, world y), carrying a travelling
// helical Kelvin wave. Returns the core's xz position at height y.
fn kelvinCore(y: f32, m: vec3<f32>, tf: f32, amp: f32) -> vec2<f32> {
  let ph = (y - m.y) * 1.4 - tf * 3.0;
  return m.xz + vec2<f32>(cos(ph), sin(ph)) * amp;
}

// x = foam distance, y = life phase of nearest bubble, z = burst-shell radiance, w = unused
fn map(p: vec3<f32>) -> vec4<f32> {
  let t = u.config.x * (0.15 + u.zoom_params.w * 0.35);
  let bass = plasmaBuffer[0].x;
  let env = 1.0 + bass * 2.0;
  var pos = p + curlNoise(p * 0.5 + t * 0.1) * 0.3 * env;
  
  let mouse = select(clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0)), vec2<f32>(extraBuffer[133], extraBuffer[134]), extraBuffer[137] > 0.5);
  let m = vec3<f32>((mouse.x * 2.0 - 1.0) * 10.0, (mouse.y * 2.0 - 1.0) * 5.0, 0.0);
  let dm = length(p - m);
  let vr = u.zoom_params.y;
  if (dm < vr) {
    pos += (m - p) / max(dm, 0.001) * (vr - dm) * 0.5;
    let s = sin(dm);
    let c = cos(dm);
    let xz = pos.xz * mat2x2<f32>(c, -s, s, c);
    pos.x = xz.x;
    pos.z = xz.y;
  }

  // ═══ Idea 3: irrotational 1/r swirl around the moving Kelvin core ═══
  if (vr > 0.0) {
    let core = kelvinCore(p.y, m, t, 0.35 * (1.0 + plasmaBuffer[0].z * 0.6));
    let rel = pos.xz - core;
    let dl = length(rel);
    let ay = (p.y - m.y) / (vr * 1.2);
    let fall = (1.0 - smoothstep(0.0, vr * 1.5, dl)) * exp(-ay * ay);
    let gamma = 0.9 * min(vr * 0.25, 1.5);            // circulation quanta grow with Vortex Radius
    let ang = gamma / (dl + 0.4) * fall;
    let cs = cos(ang);
    let sn = sin(ang);
    let relR = vec2<f32>(rel.x * cs - rel.y * sn, rel.x * sn + rel.y * cs);
    pos.x = core.x + relR.x;
    pos.z = core.y + relR.y;
  }

  // Same sphere lattice as HEAD (centres at k*sp, radius (0.6+h*0.6)*env + boil). Bug fix: HEAD took
  // the cell ID from floor() but the centre from round(), so each bubble was 8 mismatched octants.
  let sp = 3.0 / env;
  let base = floor(pos / sp);
  let wave = sin(t * 3.0 + bass * 10.0);
  let kNeck = 0.75 / env;
  var d = 1e5;
  var bestD = 1e5;
  var bestPh = 0.0;
  var burst = 0.0;
  for (var i = 0u; i < 8u; i = i + 1u) {
    let cell = base + vec3<f32>(f32(i & 1u), f32((i >> 1u) & 1u), f32((i >> 2u) & 1u));
    let q = pos - cell * sp;
    let boil = hash13(cell) * wave * u.zoom_params.x;
    let r0 = (0.6 + hash13(cell + 1.0) * 0.6) * env + boil;

    // ═══ Idea 2: film-drainage life cycle -> pop ═══
    let h2 = hash13(cell + 2.0);
    let ph = fract(t * (0.35 + 0.3 * h2) + h2 * 7.0);
    let grow = smoothstep(0.0, 0.12, ph);
    let popK = smoothstep(0.9, 0.95, ph);
    let r = r0 * grow * (1.0 - popK);
    let lq = length(q);
    let di = lq - r;
    // burst shell thrown out as the black film ruptures
    let bk = clamp((ph - 0.9) * 10.0, 0.0, 1.0);
    let shellR = max(r0, 0.2) * (0.8 + 1.8 * bk);
    burst = max(burst, step(0.9, ph) * (1.0 - bk) * exp(-abs(lq - shellR) * 6.0));
    if (di < bestD) { bestD = di; bestPh = ph; }

    // ═══ Idea 1: coalescing bubble necks (smooth union of neighbouring bubbles) ═══
    d = smin(d, di, kNeck);
  }
  return vec4<f32>(d, bestPh, burst, 0.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
  return normalize(e.xyy * map(p + e.xyy).x + e.yyx * map(p + e.yyx).x + e.yxy * map(p + e.yxy).x + e.xxx * map(p + e.xxx).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let coords = vec2<i32>(global_id.xy);
  let dims = textureDimensions(writeTexture);
  if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }
  
  let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let env = 1.0 + bass * 2.0;
  
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  if (extraBuffer[137] < 0.5) { mouse = rawMouse; mouseVelocity = vec2<f32>(0.0); }
  let springDt = select(0.016, clamp(t - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
  let springOmega = 8.0;
  mouseVelocity += ((rawMouse - mouse) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
  mouse += mouseVelocity * springDt;
  if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
    extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
    extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
    extraBuffer[137] = 1.0; extraBuffer[138] = t;
  }

  let cameraDrift = (mouse - vec2<f32>(0.5)) * vec2<f32>(0.35, 0.2);
  let ro = vec3<f32>(0.0, 0.0, -8.0);
  let rd = normalize(vec3<f32>(uv + cameraDrift, 1.0));
  var dist = 0.0;
  var glow = 0.0;
  var burstGlow = 0.0;
  var hitPh = 0.0;
  // Bug fix: with a coherent flow the camera can sit inside a (now intact) bubble; HEAD then "hit" at
  // dist 0 and blanked the frame. Rays that start inside march to the inner film instead (films are two-sided).
  let camSide = select(1.0, -1.0, map(ro).x < 0.0);
  
  for (var i = 0; i < 72; i++) {
    let p = ro + rd * dist;
    let res = map(p);
    let sd = res.x * camSide;
    if (sd < 0.5) { glow += (0.5 - sd) * 0.08 * u.zoom_params.z; }
    burstGlow += res.z * 0.05;   // Idea 2: pop radiance
    hitPh = res.y;
    if (sd < 0.001 || dist > 30.0) { break; }
    dist += max(sd * 0.55, 0.002);
  }
  
  var col = vec3<f32>(0.02, 0.0, 0.05);
  var alpha = 0.0;
  
  if (dist < 30.0) {
    let p = ro + rd * dist;
    let n = calcNormal(p) * camSide;
    let v = -rd;
    let ndotv = clamp(dot(n, v), 0.0, 1.0);

    // ═══ Chromatic dispersion: per-channel iridescence offsets ═══
    let ndotvR = clamp(ndotv + bass * 0.05, 0.0, 1.0);
    let ndotvG = clamp(ndotv + mids * 0.05, 0.0, 1.0);
    let ndotvB = clamp(ndotv + treble * 0.05, 0.0, 1.0);

    // ═══ Idea 2: film drainage — thickness sets the interference order ═══
    // The film thins with age (hitPh) and is thicker at the bottom (gravity drainage, world +y = down).
    let drain = clamp(1.0 - hitPh * 1.05, 0.0, 1.0);
    let filmOrder = drain * (1.0 + 0.35 * n.y) * 1.4;
    let blackFilm = smoothstep(0.72, 0.9, hitPh);

    let irid = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (ndotvR + 0.0 + filmOrder)),
      0.5 + 0.5 * cos(6.28318 * (ndotvG + 0.33 + filmOrder)),
      0.5 + 0.5 * cos(6.28318 * (ndotvB + 0.67 + filmOrder))
    );

    let dif = clamp(dot(n, normalize(vec3<f32>(0.8, 0.7, -0.6))), 0.0, 1.0);
    col = mix(vec3<f32>(0.1, 0.1, 0.2), irid, 0.6) * dif;
    col *= 1.0 - 0.8 * blackFilm;   // black film just before rupture
    col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.02 * dist * dist));
    alpha = clamp(1.0 - exp(-0.05 * dist), 0.0, 1.0) * (0.4 + 0.6 * dif);
  }
  
  var clickCavitation = 0.0;
  let aspect = f32(dims.x) / f32(dims.y);
  let uv01 = (vec2<f32>(coords) + vec2<f32>(0.5)) / vec2<f32>(dims);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = t - ripple.z;
    if (age >= 0.0 && age < 1.8) {
      let delta = (uv01 - ripple.xy) * vec2<f32>(aspect, 1.0);
      let radius = length(delta);
      let shell = exp(-abs(radius - age * 0.24) * 70.0) * exp(-age * 1.4);
      clickCavitation = max(clickCavitation, shell);
    }
  }

  // ═══ Idea 3: Kelvin-wave vortex filament (analytic ray / vortex-line closest approach) ═══
  let vrM = u.zoom_params.y;
  var sheath = 0.0;
  var hollow = 0.0;
  if (vrM > 0.0) {
    let tf = t * (0.15 + u.zoom_params.w * 0.35);
    let mW = vec3<f32>((mouse.x * 2.0 - 1.0) * 10.0, (mouse.y * 2.0 - 1.0) * 5.0, 0.0);
    let rdxz = rd.xz;
    let s = dot(mW.xz - ro.xz, rdxz) / max(dot(rdxz, rdxz), 1e-4);
    let yS = ro.y + rd.y * s;
    let core = kelvinCore(yS, mW, tf, 0.35 * (1.0 + treble * 0.6));
    let dl = length(ro.xz + rdxz * s - core);
    let along = (yS - mW.y) / (vrM * 1.2);
    let occluded = dist < 30.0 && s > dist;
    let vis = exp(-along * along) * smoothstep(0.0, 1.0, vrM) * select(1.0, 0.0, occluded || s < 0.0);
    let sx = (dl - 0.09) / 0.045;
    let hx = dl / 0.07;
    sheath = exp(-sx * sx) * vis;
    hollow = exp(-hx * hx) * vis;
  }

  let flash = vec3<f32>(0.8, 0.1, 1.0) * glow * env;
  col += flash;
  col += vec3<f32>(0.25, 0.75, 1.4) * clickCavitation * (0.7 + treble * 0.4);
  let burstC = clamp(burstGlow, 0.0, 2.0) * (0.35 + 0.65 * u.zoom_params.z);
  col += vec3<f32>(1.0, 0.78, 0.45) * burstC;
  col = col * (1.0 - 0.85 * hollow) + vec3<f32>(0.35, 0.85, 1.3) * sheath * 0.9;
  alpha = max(alpha, glow * 0.5 + clickCavitation * 0.45 + burstC * 0.5 + sheath * 0.7);
  
  let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  col = max(col, vec3<f32>(0.0));
  col = max(col, lum * vec3<f32>(0.3, 0.2, 0.4));

  // ═══ Temporal feedback ═══
  let prev = textureLoad(dataTextureC, coords, 0);
  col = mix(col, prev.rgb * 0.9, clamp(0.03 + bass * 0.01, 0.0, 0.08));
  col = acesToneMap(col * (1.0 + mids * 0.12));
  alpha = clamp(alpha, 0.0, 0.96);
  let hit = dist < 30.0;
  let depth = select(0.0, clamp(1.0 - dist / 30.0, 0.0, 1.0), hit);
  
  textureStore(writeTexture, coords, vec4<f32>(col * alpha, alpha));
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coords, vec4<f32>(col * alpha, alpha));
}
