// ----------------------------------------------------------------
// Bioluminescent Neural-Lattice Weaver — Batch 63
// Category: generative
// Octahedral lattice woven through an organic neural field, spun up
// to speed: psychedelic emission spectra, hollow-shell greeble detail,
// spring-cursor gravity well, held pull, capped click synapse bursts.
// Contract: 13 bindings, ACES, semantic alpha, dataTextureA writeback only,
//           exact textureLoad from dataTextureC, plasmaBuffer three-band audio,
//           bounded extraBuffer[133..138] state.
// ----------------------------------------------------------------

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
  zoom_params: vec4<f32>,  // x=Synapse Density, y=Growth Speed, z=Lattice Hardness, w=Bioluminescence
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

const SPRING_X: i32 = 133;
const SPRING_Y: i32 = 134;
const SPRING_VX: i32 = 135;
const SPRING_VY: i32 = 136;
const SPRING_T: i32 = 137;
const SPRING_INIT: i32 = 138;

var<private> g_bass: f32;
var<private> g_mids: f32;
var<private> g_treble: f32;
var<private> g_mouseWorld: vec3<f32>;
var<private> g_held: f32;
var<private> g_burst: f32;

fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic bio-emission spectrum
fn bioPalette(t: f32, drive: f32) -> vec3<f32> {
  let phase = vec3<f32>(0.35, 2.1 + drive * 1.2, 4.3 - drive * 0.9);
  return 0.5 + 0.5 * cos(TAU * t + phase);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
  let p2 = vec3<f32>(
    dot(p, vec3<f32>(127.1, 311.7, 74.7)),
    dot(p, vec3<f32>(269.5, 183.3, 246.1)),
    dot(p, vec3<f32>(113.5, 271.9, 124.6))
  );
  return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn simplex3d(p: vec3<f32>) -> f32 {
  let K1 = 0.333333333;
  let K2 = 0.166666667;

  let i = floor(p + vec3<f32>((p.x + p.y + p.z) * K1));
  let d0 = p - (i - (i.x + i.y + i.z) * K2);

  var e = step(vec3<f32>(0.0), d0 - d0.yzx);
  var i1 = e * (vec3<f32>(1.0) - e.zxy);
  var i2 = vec3<f32>(1.0) - e.zxy * (1.0 - e);

  let d1 = d0 - (i1 - 1.0 * K2);
  let d2 = d0 - (i2 - 2.0 * K2);
  let d3 = d0 - (1.0 - 3.0 * K2);

  var h0 = hash33(i);
  var h1 = hash33(i + i1);
  var h2 = hash33(i + i2);
  var h3 = hash33(i + 1.0);

  var n0 = max(0.6 - dot(d0, d0), 0.0);
  var n1 = max(0.6 - dot(d1, d1), 0.0);
  var n2 = max(0.6 - dot(d2, d2), 0.0);
  var n3 = max(0.6 - dot(d3, d3), 0.0);

  n0 = n0 * n0 * n0 * n0;
  n1 = n1 * n1 * n1 * n1;
  n2 = n2 * n2 * n2 * n2;
  n3 = n3 * n3 * n3 * n3;

  return dot(vec4<f32>(n0 * dot(h0, d0), n1 * dot(h1, d1), n2 * dot(h2, d2), n3 * dot(h3, d3)), vec4<f32>(31.316));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  let p2 = abs(p);
  return (p2.x + p2.y + p2.z - s) * 0.57735027;
}

struct MapResult {
  d: f32,
  mat_id: i32,     // 0 = lattice, 1 = neural
  energy: f32,
}

fn map(p: vec3<f32>) -> MapResult {
  var res: MapResult;

  let time = u.config.x;
  // Fast motion: growth speed is throttled by bass and by holding the button
  let growth_speed = u.zoom_params.y * (2.6 + g_bass * 2.2 + g_held * 1.5);
  let t = time * growth_speed * 0.5;

  let synapse_density = u.zoom_params.x;
  let lattice_hardness = u.zoom_params.z;

  // -- Gravity well at the smoothed cursor --
  var p_distorted = p;
  let dist_to_mouse = length(p - g_mouseWorld);
  let gravity_strength = 0.5 + g_held * 1.6 + g_burst * 1.2;
  let pull = (1.0 / (dist_to_mouse + 0.5)) * gravity_strength;
  p_distorted -= normalize(p - g_mouseWorld + vec3<f32>(1e-4)) * pull;

  // -- Crystalline lattice --
  var p_lattice = p_distorted;
  let lattice_spacing = 2.0;
  let cell_id = floor((p_lattice + lattice_spacing * 0.5) / lattice_spacing);
  p_lattice = fract((p_lattice + lattice_spacing * 0.5) / lattice_spacing) * lattice_spacing - lattice_spacing * 0.5;

  let rot_angle = (cell_id.x + cell_id.y + cell_id.z) * 0.5 + t;
  var p_lattice_xy = p_lattice.xy;
  p_lattice_xy = rot(rot_angle) * p_lattice_xy;
  p_lattice = vec3<f32>(p_lattice_xy, p_lattice.z);

  let lattice_size = 0.4 * lattice_hardness;
  var d_lattice = sdOctahedron(p_lattice, lattice_size);
  d_lattice = max(d_lattice, -sdOctahedron(p_lattice, lattice_size * 0.8)); // hollow shell

  // Greeble: strut lattice carved across the shell faces (geometric detail)
  let strut = abs(sin(p_lattice.x * 22.0) * sin(p_lattice.y * 22.0) * sin(p_lattice.z * 22.0));
  d_lattice += (0.5 - strut) * 0.012;

  // -- Organic neural network --
  let p_neural = p_distorted;
  let noise_freq = 0.5 * synapse_density;
  let n1 = simplex3d(p_neural * noise_freq + vec3<f32>(t, 0.0, 0.0));
  let n2 = simplex3d(p_neural * noise_freq * 2.0 - vec3<f32>(0.0, t * 1.2, 0.0));
  let n3 = simplex3d(p_neural * noise_freq * 4.0 + vec3<f32>(0.0, 0.0, t * 1.7)) * 0.25;
  let n = n1 * 0.55 + n2 * 0.35 + n3;

  var d_neural = abs(n) * 1.5 - (0.1 + g_mids * 0.05);

  let blend_k = 0.5;
  let d_combined = smin(d_lattice, d_neural, blend_k);

  var energy = 0.0;

  // Pulses race the pathways — treble drives the firing rate
  let pulse_freq = 3.0;
  let pulse_speed = 6.0 + g_treble * 8.0;
  let pulse = sin((p_neural.x + p_neural.y + p_neural.z) * pulse_freq - t * pulse_speed) * 0.5 + 0.5;

  let intersection_mask = 1.0 - smoothstep(0.0, 0.2, abs(d_lattice - d_neural));
  energy += intersection_mask * pulse;

  energy += (1.0 - smoothstep(0.0, 2.0 + g_held, dist_to_mouse)) * (1.5 + g_held * 1.5);

  // Real three-band audio drives the lattice charge
  energy += (g_bass * 1.2 + g_mids * 0.8 + g_treble * 1.4) * 0.6 + g_burst * 1.5;

  res.energy = energy;
  res.d = d_combined;
  res.mat_id = select(1, 0, d_lattice < d_neural);

  return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
  return normalize(
    e.xyy * map(p + e.xyy).d +
    e.yyx * map(p + e.yyx).d +
    e.yxy * map(p + e.yxy).d +
    e.xxx * map(p + e.xxx).d
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let coords = vec2<i32>(id.xy);
  let resolution = vec2<f32>(u.config.z, u.config.w);
  if (f32(coords.x) >= resolution.x || f32(coords.y) >= resolution.y) {
    return;
  }

  let uv01 = vec2<f32>(coords) / resolution;
  let uv = (vec2<f32>(coords) - 0.5 * resolution) / resolution.y;
  let aspect = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;

  g_bass = plasmaBuffer[0].x;
  g_mids = plasmaBuffer[0].y;
  g_treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  g_held = select(0.0, 1.0, held);

  // ── spring cursor (extraBuffer[133..138] only) ─────────────────────────
  var smoothMouse = rawMouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[SPRING_INIT] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[SPRING_X], extraBuffer[SPRING_Y]);
  }
  if (hasSpring && id.x == 0u && id.y == 0u) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]);
    if (extraBuffer[SPRING_INIT] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[SPRING_T], 0.001, 0.05);
      let omega = 10.0;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[SPRING_X] = springPos.x;
    extraBuffer[SPRING_Y] = springPos.y;
    extraBuffer[SPRING_VX] = springVel.x;
    extraBuffer[SPRING_VY] = springVel.y;
    extraBuffer[SPRING_T] = time;
    extraBuffer[SPRING_INIT] = 1.0;
    smoothMouse = springPos;
  }
  // Mouse Y is top-down; the world well flips it once to point up-screen
  g_mouseWorld = vec3<f32>((smoothMouse.x - 0.5) * 5.0, -(smoothMouse.y - 0.5) * 5.0, 0.0);

  // ── click synapse bursts (capped, bounded) ────────────────────────────
  var burst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let front = abs(length((uv01 - rp.xy) * aspect) - age * 0.9);
      burst = max(burst, exp(-front * 30.0) * (1.0 - age / 1.2));
    }
  }
  burst = min(burst, 1.0);
  g_burst = burst;

  let biolum_intensity = u.zoom_params.w;

  // -- Camera: fast orbit, bass-kicked, cursor tilts the elevation --
  let cam_radius = 5.0 - g_held * 0.8;
  let cam_angle = time * (0.75 + g_bass * 1.1) + (smoothMouse.x - 0.5) * 2.0;
  let ro = vec3<f32>(
    sin(cam_angle) * cam_radius,
    sin(time * 0.6) * 1.0 - (smoothMouse.y - 0.5) * 2.5,
    cos(cam_angle) * cam_radius
  );
  let ta = vec3<f32>(0.0, 0.0, 0.0);

  let cw = normalize(ta - ro);
  let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
  let cv = normalize(cross(cu, cw));
  let rd = normalize(uv.x * cu + uv.y * cv + 1.2 * cw);

  // -- Raymarching --
  var t = 0.0;
  let max_t = 20.0;
  var hit = false;
  var res: MapResult;
  var accumulated_energy = 0.0;

  for(var i = 0; i < 100; i++) {
    let p = ro + rd * t;
    res = map(p);

    accumulated_energy += max(0.0, res.energy * 0.02 * (1.0 / (1.0 + abs(res.d) * 10.0)));

    if(abs(res.d) < 0.001) {
      hit = true;
      break;
    }
    if(t > max_t) {
      break;
    }
    t += res.d * 0.7;
  }

  // -- Shading --
  var col = vec3<f32>(0.02, 0.05, 0.1);
  col -= vec3<f32>(length(uv) * 0.05);
  var rim_power = 0.0;

  if (hit) {
    let p = ro + rd * t;
    let n = calcNormal(p);
    let v = -rd;

    let l1 = normalize(vec3<f32>(1.0, 1.0, -1.0));
    let dif1 = max(0.0, dot(n, l1));

    // Hue races with treble and the click bursts
    let hue = fract(length(p) * 0.14 + time * (0.3 + g_treble * 0.9) + burst * 0.4);

    if (res.mat_id == 0) {
      // Crystalline lattice: metallic, specular, spectrally graded
      let albedo = bioPalette(hue, g_mids) * 0.45;
      let refl = reflect(rd, n);
      let spec = pow(max(0.0, dot(refl, l1)), 32.0);
      col = albedo * (dif1 * 0.8 + 0.2) + bioPalette(hue + 0.3, g_treble) * spec;
      // Strut banding — surfaces the carved greeble
      let band = 0.5 + 0.5 * sin(dot(p, vec3<f32>(22.0)) - time * 4.0);
      col *= 0.8 + band * 0.4;
    } else {
      // Neural pathways: SSS approximation with a soft spectral rim
      let albedo = bioPalette(hue + 0.5, g_bass) * 0.2;
      let rim = 1.0 - max(0.0, dot(n, v));
      rim_power = pow(rim, 3.0);
      let sss = max(0.0, dot(n, l1)) * 0.5 + 0.5;
      col = albedo * (dif1 * 0.5 + sss * 0.5) + bioPalette(hue + 0.15, g_mids) * rim_power;
    }

    col += bioPalette(hue + res.energy * 0.2, 1.0 + g_bass) * res.energy * biolum_intensity;

    let fog = exp(-t * 0.1);
    col = mix(vec3<f32>(0.01, 0.03, 0.08), col, fog);
  }

  // Volumetric energy glow in the void
  col += bioPalette(time * 0.25 + accumulated_energy * 0.4, g_treble * 1.3) * accumulated_energy * biolum_intensity * 2.0;

  // Cursor well halo + burst flash
  let cursorDist = length((uv01 - smoothMouse) * aspect);
  col += bioPalette(time * 0.6, g_bass) * exp(-cursorDist * 7.0) * (0.15 + g_held * 0.5);
  col += bioPalette(time * 1.1, 1.0) * burst * 1.2;

  // ── temporal feedback — exact load, no filtering ──────────────────────
  let prev = textureLoad(dataTextureC, coords, 0);
  col = mix(col, prev.rgb * 0.93, 0.08 + g_bass * 0.05);

  col = acesToneMap(col * (1.0 + g_mids * 0.25));

  // Semantic alpha: structure presence + emitted energy
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(
    select(0.0, 0.4 + rim_power * 0.3, hit)
    + luma * 0.45 + min(accumulated_energy, 1.5) * 0.3 + burst * 0.25,
    0.0, 1.0);

  let out_color = vec4<f32>(col, alpha);
  textureStore(writeTexture, coords, out_color);
  textureStore(dataTextureA, coords, out_color);

  let depth = select(1.0, clamp(t / max_t, 0.0, 0.995), hit);
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
