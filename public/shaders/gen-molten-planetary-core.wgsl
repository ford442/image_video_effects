// ═══════════════════════════════════════════════════════════════════
//  Molten Planetary Core
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Busse columnar convection with thermal-wind differential rotation and tangent-cylinder polar vortex; plume-head coronae with radial dike swarms and annular troughs
//  A packing: ACES display RGBA in A
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
  zoom_params: vec4<f32>,  // x=Convection, y=Plume Intensity, z=Crust Thickness, w=Glow
  ripples: array<vec4<f32>, 50>, // xy=pos, z=start time
};

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash31(p3i: vec3<f32>) -> f32 {
  var p3 = fract(p3i * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm3(p: vec2<f32>) -> f32 {
  var v = 0.0; var amp = 0.5; var pp = p;
  for (var i = 0u; i < 6u; i++) {
    v += amp * noise2(pp); pp *= 2.1; amp *= 0.48;
  }
  return v;
}

// Convection cell pattern: slow Benard rolls
fn convectionCell(p: vec2<f32>, t: f32, speed: f32) -> f32 {
  let q = vec2<f32>(
    p.x + fbm3(p + vec2<f32>(0.0, t * speed * 0.07)) * 0.6,
    p.y + fbm3(p + vec2<f32>(5.2, t * speed * 0.05)) * 0.6
  );
  return fbm3(q + vec2<f32>(t * speed * 0.03, 0.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Idea 1: Busse columnar convection (rotating outer core) ─────────
// Rapid rotation (Taylor–Proudman) organises convection into columns
// parallel to the spin axis, a "cartridge belt" of alternating cyclones /
// anticyclones outside the tangent cylinder (the cylinder circumscribing the
// solid inner core). Thermal wind shears them: prograde near the equator,
// retrograde closer in. Inside the tangent cylinder a polar vortex spirals.
// n = unit sphere normal, spin axis = screen Y.
fn busseColumns(n: vec3<f32>, t: f32, speed: f32, m: f32, drift: f32) -> vec3<f32> {
  let s = length(n.xz);                        // cylindrical radius from spin axis
  let phi = atan2(n.x, n.z);                   // longitude
  let tangentR = 0.35;                         // inner-core / outer-core radius ratio
  let omega = speed * (0.18 * s * s - 0.06) * (1.0 + drift);  // thermal-wind rotation
  let wobble = noise2(vec2<f32>(phi * 2.0, n.y * 4.0 + t * 0.05)) * 1.4;
  let belt = cos(m * (phi - omega * t) + wobble);
  let beltEnv = smoothstep(tangentR, tangentR + 0.12, s) * (0.55 + 0.45 * s);
  let polarAng = atan2(n.z, n.x);
  let polarSpiral = sin(3.0 * polarAng + s * 22.0 - t * speed * 0.9);
  let polarEnv = 1.0 - smoothstep(tangentR - 0.06, tangentR + 0.02, s);
  // x = temperature perturbation, y = column shear-line brightness, z = polar mask
  let shear = 1.0 - smoothstep(0.0, 0.12, abs(belt));
  return vec3<f32>(belt * beltEnv * 0.16 + polarSpiral * polarEnv * 0.08, shear * beltEnv, polarEnv);
}

// ── Idea 2: plume-head coronae ─────────────────────────────────────
// A mantle-plume head impinging on the lid domes it up, splits it with a
// radial dike swarm, then relaxes into an annular trough ringed by
// concentric fractures (Venus-style coronae). Coordinates are stereographic
// (conformal) so coronae stay circular across the sphere.
// Returns x = dike/fracture emission, y = dome heat, z = annular trough (dark lid)
fn coronae(q: vec2<f32>, t: f32, plumeAmt: f32, bass: f32) -> vec3<f32> {
  var dike = 0.0; var dome = 0.0; var trough = 0.0;
  let cell = floor(q);
  for (var oy = -1; oy <= 1; oy++) {
    for (var ox = -1; ox <= 1; ox++) {
      let c = cell + vec2<f32>(f32(ox), f32(oy));
      let h1 = hash21(c);
      let h2 = hash21(c + vec2<f32>(17.3, 5.1));
      let centre = c + vec2<f32>(0.2 + 0.6 * h1, 0.2 + 0.6 * h2);
      // life cycle: rise → dome + dikes → annular trough → quiet
      let life = fract(t * (0.025 + 0.02 * h1) + h2);
      let alive = smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.75, 1.0, life));
      let strength = alive * step(0.45 - plumeAmt * 0.3, h1 * h2 + 0.3) * (1.0 + bass * 0.5);
      let dv = q - centre;
      let d = length(dv);
      let R = (0.18 + 0.22 * h2) * (0.6 + 0.6 * smoothstep(0.1, 0.7, life));
      let ang = atan2(dv.y, dv.x);
      let nDikes = 7.0 + floor(h1 * 9.0);
      let radial = 1.0 - smoothstep(0.0, 0.08 + 0.1 * d, abs(sin(ang * nDikes * 0.5 + h2 * 6.2831)));
      let inR = 1.0 - smoothstep(R * 0.3, R * 1.05, d);
      let ringW = 0.035 + 0.02 * h1;
      let ring = exp(-pow((d - R) / ringW, 2.0));
      let concentric = exp(-pow((d - R * 1.18) / (ringW * 0.5), 2.0));
      dike   += strength * (radial * inR * (1.0 - smoothstep(0.4, 0.8, life)) + concentric * smoothstep(0.35, 0.6, life));
      dome   += strength * exp(-d * d / max(R * R * 0.25, 1e-4)) * (1.0 - smoothstep(0.3, 0.6, life));
      trough += strength * ring * smoothstep(0.3, 0.65, life);
    }
  }
  return vec3<f32>(min(dike, 1.5), min(dome, 1.5), min(trough, 1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let t = u.config.x;

  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let convSpeed  = mix(0.1, 1.5, u.zoom_params.x) * (1.0 + bass * 0.4);
  let plumeAmt   = mix(0.0, 1.0, u.zoom_params.y) * (1.0 + bass * 0.6);
  let crustThick = mix(0.05, 0.3, u.zoom_params.z);
  let glowPow    = mix(0.5, 2.5, u.zoom_params.w) * (1.0 + mids * 0.2);

  // Mouse tilts the 3-D view axis (while held)
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p -= mouse * 0.2 * u.zoom_config.w;

  let r = length(p);

  // Sphere mask
  let sphereR = 0.9;
  let onSphere = smoothstep(sphereR + 0.02, sphereR - 0.02, r);

  // Sphere normal from position
  let nz = sqrt(max(0.0, sphereR * sphereR - r * r)) / sphereR;
  let normal = vec3<f32>(p / sphereR, nz);

  // Spherical UV (for noise sampling)
  let sUV = vec2<f32>(atan2(normal.y, normal.x) / 6.28318, acos(clamp(normal.z, -1.0, 1.0)) / 3.14159);

  // Convection field
  let conv = convectionCell(sUV * 3.0, t, convSpeed);

  // Busse columns: column count rises with Convection (higher Rayleigh number)
  let mCols = floor(mix(6.0, 16.0, u.zoom_params.x));
  let busse = busseColumns(normalize(normal + vec3<f32>(0.0, 0.0, 1e-4)), t, convSpeed, mCols, mids * 0.5);

  // Temperature map (core = hot white, surface cooler)
  let temp = (conv + busse.x) * (1.0 - r * 0.6);

  // Colour: blackbody ramp from black→red→orange→yellow→white
  let t0 = clamp(temp * 2.0, 0.0, 1.0);
  let t1 = clamp(temp * 2.0 - 1.0, 0.0, 1.0);
  var moltenCol = vec3<f32>(
    t0,                              // red builds first
    t0 * t0 * 0.7 + t1 * 0.3,       // orange-yellow
    t1 * t1 * 0.5                    // white-hot core
  ) * glowPow;

  // Column shear lines glow where cyclone meets anticyclone; polar vortex tint
  moltenCol += vec3<f32>(1.0, 0.42, 0.08) * busse.y * 0.18 * glowPow * (0.6 + mids * 0.6);
  moltenCol *= 1.0 + busse.z * 0.15;

  // Mantle plumes: hot upwellings triggered by bass
  let plumeField = noise2(sUV * 6.0 + vec2<f32>(t * 0.04, 0.0));
  let plume = smoothstep(0.6, 1.0, plumeField) * plumeAmt;
  moltenCol += vec3<f32>(1.0, 0.5, 0.1) * plume * (1.0 + bass * 0.8);

  // Seismic P-waves from clicks: expanding shock rings shake the lid open
  var quake = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let rp = u.ripples[i];
    let age = t - rp.z;
    if (age > 0.0 && age < 3.0) {
      let rc = (rp.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0) - mouse * 0.2 * u.zoom_config.w;
      let d = length(p - rc);
      let front = age * 0.7;
      quake += exp(-pow((d - front) / (0.03 + age * 0.02), 2.0)) * exp(-age * 1.3);
    }
  }
  quake = min(quake, 1.5);

  // Crust cracks on treble (and seismic shaking)
  let crackNoise = noise2(sUV * 20.0 + vec2<f32>(0.0, t * 0.02));
  let crack = smoothstep(crustThick, 0.0, crackNoise) * (1.0 - smoothstep(0.0, 0.05, plume));
  let crackGlow = crack * (treble + quake) * vec3<f32>(1.0, 0.3, 0.05) * 2.0;
  moltenCol = mix(moltenCol, moltenCol + crackGlow, crack * 0.5);

  // Coronae over plume heads (stereographic coords → circular features)
  let stereo = normal.xy / (1.0 + max(normal.z, 0.0)) * 3.2 + vec2<f32>(t * 0.01 * convSpeed, 0.0);
  let cor = coronae(stereo, t, u.zoom_params.y, bass);
  moltenCol += vec3<f32>(1.0, 0.55, 0.15) * cor.y * 0.35 * plumeAmt * glowPow;
  moltenCol += vec3<f32>(1.0, 0.72, 0.3) * cor.x * (0.35 + treble * 0.5 + quake * 0.5) * glowPow;

  // Dark crust where not cracking; annular coronae troughs thicken the lid
  let crustMask = clamp(smoothstep(0.0, crustThick * 2.0, crackNoise) * (1.0 - plume) + cor.z * 0.6 * (0.5 + u.zoom_params.z), 0.0, 1.0) * (1.0 - quake * 0.4);
  let crustCol  = vec3<f32>(0.05, 0.04, 0.03) * crustMask;
  moltenCol = mix(moltenCol, crustCol, crustMask * 0.4);

  // Apply sphere mask (outside = space black)
  var col = moltenCol * onSphere;

  // Atmospheric rim glow
  let rim = smoothstep(sphereR - 0.05, sphereR + 0.0, r) * smoothstep(sphereR + 0.12, sphereR - 0.0, r);
  col += vec3<f32>(0.9, 0.3, 0.1) * rim * (1.0 + bass * 0.4);

  let depth = clamp(nz * onSphere + cor.y * 0.03 * onSphere, 0.0, 1.0);

  // Limb dispersion: slight red lift / blue loss toward the limb (pre-tonemap)
  let caStr = 0.03 * (1.0 + bass) * (1.0 - nz) * onSphere;
  col = vec3<f32>(col.r * (1.0 + caStr), col.g, col.b * (1.0 - caStr * 0.5));

  // Single ACES pass on display colour
  col = acesToneMap(col * 1.1);
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  // Alpha = sphere coverage weighted by incandescence, plus limb glow halo
  let alpha = clamp(onSphere * (0.7 + 0.3 * luma) + rim * luma * 0.8, 0.0, 1.0);

  let finalColor = vec4<f32>(col, alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
