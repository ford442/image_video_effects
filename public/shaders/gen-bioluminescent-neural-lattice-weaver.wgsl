// ----------------------------------------------------------------
// Bioluminescent Neural-Lattice Weaver
// Category: generative
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
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Rotates a 2D vector
fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

// 3D hash
fn hash33(p: vec3<f32>) -> vec3<f32> {
  let p2 = vec3<f32>(
    dot(p, vec3<f32>(127.1, 311.7, 74.7)),
    dot(p, vec3<f32>(269.5, 183.3, 246.1)),
    dot(p, vec3<f32>(113.5, 271.9, 124.6))
  );
  return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

// 3D Simplex noise
fn simplex3d(p: vec3<f32>) -> f32 {
  let K1 = 0.333333333;
  let K2 = 0.166666667;

  let i = floor(p + (p.x + p.y + p.z) * K1);
  let d0 = p - (i - (i.x + i.y + i.z) * K2);

  var e = step(vec3<f32>(0.0), d0 - d0.yzx);
  var i1 = e * (1.0 - e.zxy);
  var i2 = 1.0 - e.zxy * (1.0 - e);

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

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// Octahedron SDF
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  var p2 = abs(p);
  return (p2.x + p2.y + p2.z - s) * 0.57735027; // 1/sqrt(3)
}

struct MapResult {
  d: f32,
  mat_id: i32,     // 0 = lattice, 1 = neural
  energy: f32,
}

// Map function
fn map(p: vec3<f32>) -> MapResult {
  var res: MapResult;

  let time = u.config.x;
  let growth_speed = u.zoom_params.y;
  let t = time * growth_speed * 0.5;

  let synapse_density = u.zoom_params.x;
  let lattice_hardness = u.zoom_params.z;

  // -- Mouse interaction (Gravity well) --
  let mouse_uv = u.zoom_config.yz; // (y=0 top)
  let mouse_pos_world = vec3<f32>((mouse_uv.x - 0.5) * 5.0, -(mouse_uv.y - 0.5) * 5.0, 0.0);

  var p_distorted = p;
  let dist_to_mouse = length(p - mouse_pos_world);
  if (u.zoom_config.w > 0.5) { // if mouse is down
    let gravity_strength = 0.5;
    let pull = (1.0 / (dist_to_mouse + 0.5)) * gravity_strength;
    p_distorted -= normalize(p - mouse_pos_world) * pull;
  }

  // -- Crystalline Lattice --
  var p_lattice = p_distorted;
  // Domain repetition
  let lattice_spacing = 2.0;
  let cell_id = floor((p_lattice + lattice_spacing * 0.5) / lattice_spacing);
  p_lattice = fract((p_lattice + lattice_spacing * 0.5) / lattice_spacing) * lattice_spacing - lattice_spacing * 0.5;

  // Rotate lattice cells based on position for variation
  let rot_angle = (cell_id.x + cell_id.y + cell_id.z) * 0.5 + t;
  var p_lattice_xy = p_lattice.xy;
  p_lattice_xy = rot(rot_angle) * p_lattice_xy;
  p_lattice = vec3<f32>(p_lattice_xy, p_lattice.z);

  let lattice_size = 0.4 * lattice_hardness;
  var d_lattice = sdOctahedron(p_lattice, lattice_size);
  // Add some detail to lattice
  d_lattice = max(d_lattice, -sdOctahedron(p_lattice, lattice_size * 0.8)); // hollow it out

  // -- Organic Neural Network --
  var p_neural = p_distorted;
  // Base noise
  let noise_freq = 0.5 * synapse_density;
  let n1 = simplex3d(p_neural * noise_freq + vec3<f32>(t, 0.0, 0.0));
  let n2 = simplex3d(p_neural * noise_freq * 2.0 - vec3<f32>(0.0, t*1.2, 0.0));
  let n = n1 * 0.6 + n2 * 0.4;

  // Create branches by inflating noise where it crosses zero
  var d_neural = abs(n) * 1.5 - 0.1;

  // -- Interaction / Combination --
  // Use smin for organic blending, but mix with lattice
  let blend_k = 0.5;
  let d_combined = smin(d_lattice, d_neural, blend_k);

  // Energy calculation: high where neural structures intersect lattice or are near mouse
  var energy = 0.0;

  // Pulse traveling along neural pathways
  let pulse_freq = 3.0;
  let pulse_speed = 2.0;
  let pulse = sin(p_neural.x * pulse_freq + p_neural.y * pulse_freq + p_neural.z * pulse_freq - t * pulse_speed) * 0.5 + 0.5;

  // Increase energy near lattice intersections
  let intersection_mask = 1.0 - smoothstep(0.0, 0.2, abs(d_lattice - d_neural));
  energy += intersection_mask * pulse;


  // Increase energy near mouse
  energy += (1.0 - smoothstep(0.0, 2.0, dist_to_mouse)) * 1.5;

  // Audio reactivity
  let audio_sample = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(abs(d_neural) * 0.5, 0.5), 0.0).r;
  energy += audio_sample * 2.0;

  res.energy = energy;

  if (d_lattice < d_neural) {
    res.d = d_combined;
    res.mat_id = 0; // Lattice dominant
  } else {
    res.d = d_combined;
    res.mat_id = 1; // Neural dominant
  }

  return res;
}

// Normal calculation
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

  var uv = (vec2<f32>(coords) - 0.5 * resolution) / resolution.y;
  let time = u.config.x;

  let biolum_intensity = u.zoom_params.w;

  // -- Camera setup --
  let cam_radius = 5.0;
  let cam_angle = time * 0.1;
  let ro = vec3<f32>(sin(cam_angle) * cam_radius, sin(time * 0.05) * 1.0, cos(cam_angle) * cam_radius);
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

    // Accumulate energy for volumetric bloom effect
    accumulated_energy += max(0.0, res.energy * 0.02 * (1.0 / (1.0 + abs(res.d) * 10.0)));

    if(abs(res.d) < 0.001) {
      hit = true;
      break;
    }
    if(t > max_t) {
      break;
    }
    t += res.d * 0.7; // Step size multiplier to prevent overshooting with noise/smin
  }

  // -- Shading --
  var col = vec3<f32>(0.02, 0.05, 0.1); // Deep background (cyan/magenta mix base)
  col -= length(uv) * 0.05; // vignette

  if (hit) {
    let p = ro + rd * t;
    let n = calcNormal(p);
    let v = -rd;

    // Lighting setup
    let l1 = normalize(vec3<f32>(1.0, 1.0, -1.0));
    let l2 = normalize(vec3<f32>(-1.0, -0.5, 1.0));

    let dif1 = max(0.0, dot(n, l1));
    let dif2 = max(0.0, dot(n, l2));

    var albedo = vec3<f32>(0.0);

    if (res.mat_id == 0) {
      // Crystalline Lattice: metallic, specular
      albedo = vec3<f32>(0.1, 0.3, 0.4);
      let refl = reflect(rd, n);
      let spec = pow(max(0.0, dot(refl, l1)), 32.0);
      col = albedo * (dif1 * 0.8 + 0.2) + vec3<f32>(1.0) * spec;
    } else {
      // Neural Pathways: subsurface scattering approx, organic
      albedo = vec3<f32>(0.05, 0.1, 0.2);
      // Soft rim lighting
      let rim = 1.0 - max(0.0, dot(n, v));
      let rim_power = pow(rim, 3.0);

      // SSS approx (light bleeding through)
      let sss = max(0.0, dot(n, l1)) * 0.5 + 0.5;

      col = albedo * (dif1 * 0.5 + sss * 0.5) + vec3<f32>(0.0, 0.5, 0.8) * rim_power;
    }

    // Add surface energy emission
    let emission_color = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.5, 0.0), res.energy); // Electric blue to bright orange
    col += emission_color * res.energy * biolum_intensity;

    // Fog
    let fog = exp(-t * 0.1);
    col = mix(vec3<f32>(0.01, 0.03, 0.08), col, fog);
  }

  // Add volumetric accumulated energy (glow in the void)
  let vol_color = mix(vec3<f32>(0.0, 0.5, 1.0), vec3<f32>(1.0, 0.4, 0.0), accumulated_energy * 0.5);
  col += vol_color * accumulated_energy * biolum_intensity * 2.0;

  // Tone mapping (ACES approx)
  col = (col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14);

  let out_color = vec4<f32>(col, 1.0);
  textureStore(writeTexture, coords, out_color);
}
