// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Neural-Lattice Weaver
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: charged cage-core lanterns fed by the membrane; click spin cascade through the cage
//  A packing: HDR linear RGB (pre-ACES, post-feedback) + semantic alpha
// ═══════════════════════════════════════════════════════════════════
// Octahedral lattice woven through an organic neural field: hollow-shell
// greeble, cursor gravity well (held deepens it), click synapse bursts.

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
const HALF_PI: f32 = 1.57079632679;

// Click spin cascade: world-space wave speed, per-cell spin time, wave life.
const CASCADE_SPEED: f32 = 3.2;
const CASCADE_SPIN: f32 = 0.55;
const CASCADE_LIFE: f32 = 2.6;
// Cells beyond this radius never turn, so no cage is mid-turn when a wave
// expires: 6.0 < CASCADE_SPEED * (CASCADE_LIFE - CASCADE_SPIN) = 6.56.
const CASCADE_RADIUS: f32 = 6.0;
const MAX_CASCADES: u32 = 4u;

var<private> g_bass: f32;
var<private> g_mids: f32;
var<private> g_treble: f32;
var<private> g_mouseWorld: vec3<f32>;
var<private> g_held: f32;
var<private> g_burst: f32;
// Up to 4 live click cascades: world origin + age (time - ripple.z; never ripple.w).
var<private> g_cascadeOrigin: array<vec3<f32>, 4>;
var<private> g_cascadeAge: array<f32, 4>;
var<private> g_cascadeCount: u32;

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

// Growth phase: slider-scaled time only. Audio used to multiply time here,
// so at large time a bass change jumped the phase by hundreds of radians;
// bass now adds a bounded nudge instead.
fn growthPhase() -> f32 {
  return u.config.x * u.zoom_params.y * 1.3 + g_bass * 0.3;
}

// Gravity well at the cursor (held deepens it, click bursts kick it).
fn wellDistort(p: vec3<f32>) -> vec3<f32> {
  let dist_to_mouse = length(p - g_mouseWorld);
  let gravity_strength = 0.5 + g_held * 1.6 + g_burst * 1.2;
  let pull = (1.0 / (dist_to_mouse + 0.5)) * gravity_strength;
  return p - normalize(p - g_mouseWorld + vec3<f32>(1e-4)) * pull;
}

// Idea 2: Click spin cascade — each click launches a 3D wave from the point
// under the cursor (projected through the camera as it was at click time).
// When the front reaches a cell, that octahedral cage turns a quarter turn
// about its axis (a symmetry of the octahedron, so it lands seamlessly) and
// flares while turning. Delay = cell distance / CASCADE_SPEED. Stateless.
// Returns (extra spin angle, flare 0..1).
fn cascadeSpin(cell_id: vec3<f32>) -> vec2<f32> {
  let centre = cell_id * 2.0;
  var angle = 0.0;
  var flare = 0.0;
  for (var i = 0u; i < g_cascadeCount; i = i + 1u) {
    let dist = length(centre - g_cascadeOrigin[i]);
    if (dist > CASCADE_RADIUS) { continue; }
    let local_age = g_cascadeAge[i] - dist / CASCADE_SPEED;
    let s = clamp(local_age / CASCADE_SPIN, 0.0, 1.0);
    angle += HALF_PI * s * s * (3.0 - 2.0 * s);
    flare = max(flare, sin(3.14159265 * s));
  }
  return vec2<f32>(angle, flare);
}

// Idea 1: Charged cage cores — the charge of a cell's core is the membrane
// field (dominant n1 layer of map()) sampled at the cell centre: cores whose
// cell a membrane sheet is passing through light up, others go dark.
fn coreCharge(cell_id: vec3<f32>, t: f32, noise_freq: f32, flare: f32) -> f32 {
  let n_c = simplex3d(cell_id * 2.0 * noise_freq + vec3<f32>(t, 0.0, 0.0));
  return 1.0 - smoothstep(0.0, 0.32, abs(n_c)) + flare * 0.8;
}

fn map(p: vec3<f32>) -> MapResult {
  var res: MapResult;

  let t = growthPhase();

  let synapse_density = u.zoom_params.x;
  let lattice_hardness = u.zoom_params.z;

  // -- Gravity well at the cursor --
  let dist_to_mouse = length(p - g_mouseWorld);
  let p_distorted = wellDistort(p);

  // -- Crystalline lattice --
  var p_lattice = p_distorted;
  let lattice_spacing = 2.0;
  let cell_id = floor((p_lattice + lattice_spacing * 0.5) / lattice_spacing);
  p_lattice = fract((p_lattice + lattice_spacing * 0.5) / lattice_spacing) * lattice_spacing - lattice_spacing * 0.5;

  let cascade = cascadeSpin(cell_id);
  let rot_angle = (cell_id.x + cell_id.y + cell_id.z) * 0.5 + t + cascade.x;
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

  // Pulses race the pathways — fixed rate (treble used to scale the phase);
  // treble now brightens the pulses instead.
  let pulse_freq = 3.0;
  let pulse_speed = 6.0;
  let pulse = sin((p_neural.x + p_neural.y + p_neural.z) * pulse_freq - t * pulse_speed) * 0.5 + 0.5;

  let intersection_mask = 1.0 - smoothstep(0.0, 0.2, abs(d_lattice - d_neural));
  energy += intersection_mask * pulse * (1.0 + g_treble * 0.8);

  // Idea 2: a turning cage flares near its shell while the cascade passes
  energy += cascade.y * 1.4 * (1.0 - smoothstep(0.0, 0.3, d_lattice));

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

// Camera orbit origin (fast orbit; cursor tilts the elevation, bass gives a
// bounded kick — it used to multiply time, which jumped the orbit with music).
fn cameraOrigin(tm: f32, mouse: vec2<f32>, bass: f32, held: f32) -> vec3<f32> {
  let cam_radius = 5.0 - held * 0.8;
  let cam_angle = tm * 0.75 + bass * 0.25 + (mouse.x - 0.5) * 2.0;
  return vec3<f32>(
    sin(cam_angle) * cam_radius,
    sin(tm * 0.6) * 1.0 - (mouse.y - 0.5) * 2.5,
    cos(cam_angle) * cam_radius
  );
}

fn cameraRay(ro: vec3<f32>, uv: vec2<f32>) -> vec3<f32> {
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let cw = normalize(ta - ro);
  let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
  let cv = normalize(cross(cu, cw));
  return normalize(uv.x * cu + uv.y * cv + 1.2 * cw);
}

fn cellHue(cell_id: vec3<f32>) -> f32 {
  return fract(sin(dot(cell_id, vec3<f32>(12.9898, 78.233, 37.719))) * 43758.5453);
}

// Idea 1: Charged cage-core lanterns. The march stops on the nearest surface
// (median hit distance is ~0.2 units at default sliders — the camera sits
// inside the membrane web), so core light cannot be gathered by the march
// itself; instead each hit surface is back-lit by the charged cores of the
// next cells along the view ray, as translucent lantern paper. Shell faces
// light up where the core sits right behind them; membranes glow with the
// cages beyond. Walks up to 4 cells (unit steps), attenuating with distance.
fn cageLanterns(p_hit: vec3<f32>, rd: vec3<f32>, t: f32, noise_freq: f32, lattice_size: f32) -> vec3<f32> {
  var acc = vec3<f32>(0.0);
  var last = vec3<f32>(1e5);
  let sigma2 = max(lattice_size * lattice_size * 0.35, 1e-3);
  for (var k = 0; k < 4; k = k + 1) {
    let s = f32(k);
    let q = wellDistort(p_hit + rd * s);
    let cid = floor((q + 1.0) * 0.5);
    if (all(cid == last)) { continue; }
    last = cid;
    let rel = cid * 2.0 - q;
    let along = dot(rel, rd);
    if (along < -lattice_size) { continue; }
    let perp2 = max(dot(rel, rel) - along * along, 0.0);
    let flare = cascadeSpin(cid).y;
    let charge = coreCharge(cid, t, noise_freq, flare);
    let glow = exp(-perp2 / sigma2) * exp(-(s + max(along, 0.0)) * 0.35);
    acc += bioPalette(cellHue(cid) * 0.35 + 0.55 + flare * 0.2, 0.6) * charge * glow;
  }
  return acc;
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

  // Raw cursor. (HEAD ran a "spring" in extraBuffer[133..138]; that range is
  // zeroed every frame, so it never persisted and its thread-0 writes raced
  // other tiles' reads — removed.)
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  g_held = select(0.0, 1.0, held);

  // Mouse Y is top-down; the world well flips it once to point up-screen
  g_mouseWorld = vec3<f32>((mouse.x - 0.5) * 5.0, -(mouse.y - 0.5) * 5.0, 0.0);

  // ── click synapse bursts (capped, bounded) + Idea 2 cascade origins ────
  var burst = 0.0;
  g_cascadeCount = 0u;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let front = abs(length((uv01 - rp.xy) * aspect) - age * 0.9);
      burst = max(burst, exp(-front * 30.0) * (1.0 - age / 1.2));
    }
    if (age >= 0.0 && age < CASCADE_LIFE) {
      // Origin: the click ray through the camera as it stood at click time,
      // one unit into the web — fixed in world space while the camera orbits.
      let ro_c = cameraOrigin(rp.z, mouse, 0.0, 0.0);
      let uv_c = (rp.xy * resolution - 0.5 * resolution) / resolution.y;
      let origin = ro_c + cameraRay(ro_c, uv_c) * 1.0;
      if (g_cascadeCount < MAX_CASCADES) {
        g_cascadeOrigin[g_cascadeCount] = origin;
        g_cascadeAge[g_cascadeCount] = age;
        g_cascadeCount = g_cascadeCount + 1u;
      } else {
        // keep the youngest four
        var oldest = 0u;
        for (var j = 1u; j < MAX_CASCADES; j = j + 1u) {
          if (g_cascadeAge[j] > g_cascadeAge[oldest]) { oldest = j; }
        }
        if (age < g_cascadeAge[oldest]) {
          g_cascadeOrigin[oldest] = origin;
          g_cascadeAge[oldest] = age;
        }
      }
    }
  }
  burst = min(burst, 1.0);
  g_burst = burst;

  let biolum_intensity = u.zoom_params.w;
  let synapse_density = u.zoom_params.x;
  let lattice_size = 0.4 * u.zoom_params.z;

  // -- Camera: fast orbit, bass-kicked, cursor tilts the elevation --
  let ro = cameraOrigin(time, mouse, g_bass, g_held);
  let rd = cameraRay(ro, uv);

  // -- Raymarching --
  // Step factor follows the membrane gradient (|grad d| ~ 0.6 + 2.2 * density,
  // measured on a numpy port): 0.7 at low density, 0.5 at default, 0.3 at max.
  // If the camera starts inside a membrane, first walk out forward, and never
  // step back behind that exit point (HEAD could march to t < 0 and shade
  // surfaces behind the camera).
  let step_k = clamp(1.4 / (0.6 + 2.2 * synapse_density), 0.3, 0.7);
  var t = 0.0;
  var t_floor = 0.0;
  var exiting = false;
  let max_t = 20.0;
  var hit = false;
  var res: MapResult;
  var accumulated_energy = 0.0;

  for (var i = 0; i < 110; i++) {
    let p = ro + rd * t;
    res = map(p);

    accumulated_energy += max(0.0, res.energy * 0.02 * (1.0 / (1.0 + abs(res.d) * 10.0)));

    if (i == 0 && res.d < 0.0) { exiting = true; }
    if (exiting) {
      if (res.d < 0.0) {
        t += max(-res.d * step_k, 0.02);
        continue;
      }
      exiting = false;
      t_floor = t;
    }

    if (abs(res.d) < 0.001) {
      hit = true;
      break;
    }
    if (t > max_t) {
      break;
    }
    t = max(t + res.d * step_k, t_floor);
  }

  // -- Shading --
  var col = vec3<f32>(0.02, 0.05, 0.1);
  col = max(col - vec3<f32>(length(uv) * 0.05), vec3<f32>(0.0));
  var rim_power = 0.0;
  var lantern = vec3<f32>(0.0);

  if (hit) {
    let p = ro + rd * t;
    let n = calcNormal(p);
    let v = -rd;

    let l1 = normalize(vec3<f32>(1.0, 1.0, -1.0));
    let dif1 = max(0.0, dot(n, l1));

    // Hue drifts with time; treble and click bursts add bounded offsets
    // (treble used to multiply time here, so the hue strobed with music).
    let hue = fract(length(p) * 0.14 + time * 0.3 + g_treble * 0.25 + burst * 0.4);

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
      rim_power = pow(max(rim, 0.0), 3.0);
      let sss = max(0.0, dot(n, l1)) * 0.5 + 0.5;
      col = albedo * (dif1 * 0.5 + sss * 0.5) + bioPalette(hue + 0.15, g_mids) * rim_power;
    }

    col += bioPalette(hue + res.energy * 0.2, 1.0 + g_bass) * res.energy * biolum_intensity;

    // Idea 1: lantern back-light through shell faces and membranes
    // (shell paper is thinner than membrane tissue, so it passes more light).
    lantern = cageLanterns(p, rd, growthPhase(), 0.5 * synapse_density, lattice_size);
    col += lantern * biolum_intensity * select(1.1, 1.8, res.mat_id == 0);

    let fog = exp(-t * 0.1);
    col = mix(vec3<f32>(0.01, 0.03, 0.08), col, fog);
  }

  // Volumetric energy glow in the void
  col += bioPalette(time * 0.25 + accumulated_energy * 0.4, g_treble * 1.3) * accumulated_energy * biolum_intensity * 2.0;

  // Cursor well halo + burst flash
  let cursorDist = length((uv01 - mouse) * aspect);
  col += bioPalette(time * 0.6, g_bass) * exp(-cursorDist * 7.0) * (0.15 + g_held * 0.5);
  col += bioPalette(time * 1.1, 1.0) * burst * 1.2;

  // ── temporal feedback — exact load, no filtering ──────────────────────
  // A/C hold HDR (pre-ACES) colour, so the trail is blended in the same
  // space and tone-mapped once (HEAD stored ACES output and re-mapped it).
  let prev = textureLoad(dataTextureC, coords, 0);
  col = mix(col, prev.rgb * 0.93, 0.08 + g_bass * 0.05);
  let hdr = col;

  let display = acesToneMap(hdr * (1.0 + g_mids * 0.25));

  // Semantic alpha: structure presence + emitted energy (+ lit lanterns)
  let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(
    select(0.0, 0.4 + rim_power * 0.3, hit)
    + luma * 0.45 + min(accumulated_energy, 1.5) * 0.3 + burst * 0.25
    + min(dot(lantern, vec3<f32>(0.333)), 1.0) * 0.15,
    0.0, 1.0);

  textureStore(writeTexture, coords, vec4<f32>(display, alpha));
  textureStore(dataTextureA, coords, vec4<f32>(hdr, alpha));

  // Depth: near = 1, miss = 0
  let depth = select(0.0, clamp(1.0 - t / max_t, 0.005, 1.0), hit);
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
