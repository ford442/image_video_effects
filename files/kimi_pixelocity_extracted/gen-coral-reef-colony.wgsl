// ═══════════════════════════════════════════════════════════════════
//  Coral Reef Colony
//  Category: generative
//  Description: Procedurally generated coral colony growth using
//    branching L-system-like recursion. Creates organic coral forms
//    with polyp details, color gradients from depth, and swaying
//    animation simulating underwater current. Mouse plants new coral.
//  Complexity: High
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn hash2f(n: f32) -> vec2<f32> {
  return vec2<f32>(hashf(n), hashf(n + 73.156));
}

fn hash3f(n: f32) -> vec3<f32> {
  return vec3<f32>(hashf(n), hashf(n + 53.7), hashf(n + 91.3));
}

// Signed distance to a line segment
fn sd_segment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// Coral color based on depth and type
fn coral_color(depth: f32, coral_type: f32, p4: f32) -> vec3<f32> {
  let t = fract(coral_type + p4);
  var base: vec3<f32>;
  if t < 0.2 {
    base = vec3<f32>(0.95, 0.55, 0.35); // orange
  } else if t < 0.4 {
    base = vec3<f32>(0.85, 0.30, 0.45); // pink
  } else if t < 0.6 {
    base = vec3<f32>(0.55, 0.25, 0.50); // purple
  } else if t < 0.8 {
    base = vec3<f32>(0.90, 0.70, 0.25); // gold
  } else {
    base = vec3<f32>(0.35, 0.65, 0.60); // teal
  }

  // Darken with depth
  let depth_factor = 1.0 - depth * 0.15;
  return base * depth_factor;
}

// Evaluate a coral branch and return SDF + color info
fn coral_sdf(p: vec2<f32>, root: vec2<f32>, seed: f32, time: f32, p2: f32) -> vec4<f32> {
  var min_dist = 1000.0;
  var branch_color = vec3<f32>(0.0);
  var max_depth = 0.0;

  // Recursive branching parameters
  let branch_angle = 0.45 + hashf(seed) * 0.3;
  let branch_shrink = 0.65 + hashf(seed + 1.0) * 0.1;
  let num_branches = 2 + i32(hashf(seed + 2.0) * 2.0);
  let max_generations = 5;

  // Stack for branch positions
  var pos_stack: array<vec2<f32>, 8>;
  var angle_stack: array<f32, 8>;
  var width_stack: array<f32, 8>;
  var gen_stack: array<i32, 8>;
  var stack_ptr = 0;

  // Initialize root
  pos_stack[0] = root;
  angle_stack[0] = -PI * 0.5 + (hashf(seed + 3.0) - 0.5) * 0.2;
  width_stack[0] = 0.03 + hashf(seed + 4.0) * 0.02;
  gen_stack[0] = 0;

  while stack_ptr >= 0 && stack_ptr < 7 {
    let pos = pos_stack[stack_ptr];
    let angle = angle_stack[stack_ptr];
    let width = width_stack[stack_ptr];
    let gen = gen_stack[stack_ptr];
    stack_ptr--;

    if gen >= max_generations { continue; }

    // Current sway from water current
    let sway = sin(time * p2 * 0.5 + f32(gen) * 0.7 + seed) * 0.02 * f32(gen);

    // Branch length
    let length = 0.08 + hashf(seed + f32(gen) * 13.0) * 0.06;

    // End point of this branch
    let end_pos = pos + vec2<f32>(
      cos(angle + sway) * length,
      sin(angle + sway) * length
    );

    // SDF for this segment
    let seg_dist = sd_segment(p, pos, end_pos);
    let dist = seg_dist - width * (1.0 - f32(gen) * 0.1);

    if dist < min_dist {
      min_dist = dist;
      branch_color = coral_color(f32(gen), hashf(seed + 5.0), 0.0);
      max_depth = f32(gen);
    }

    // Polyp dots at branch ends
    if gen == max_generations - 1 {
      let polyp_dist = length(p - end_pos) - width * 0.5;
      if polyp_dist < min_dist {
        min_dist = polyp_dist;
        branch_color = coral_color(f32(gen), hashf(seed + 6.0), 0.0) * 1.3;
      }
    }

    // Push child branches
    for (var b = 0; b < num_branches && stack_ptr < 7; b++) {
      stack_ptr++;
      pos_stack[stack_ptr] = end_pos;
      let offset = (f32(b) - f32(num_branches - 1) * 0.5) * branch_angle;
      angle_stack[stack_ptr] = angle + offset + sin(time * p2 * 0.3 + f32(b)) * 0.05;
      width_stack[stack_ptr] = width * branch_shrink;
      gen_stack[stack_ptr] = gen + 1;
    }
  }

  return vec4<f32>(min_dist, branch_color, max_depth);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // intensity (colony count)
  let p2 = u.zoom_params.y; // speed (sway speed)
  let p3 = u.zoom_params.z; // scale (zoom)
  let p4 = u.zoom_params.w; // color shift

  let seed = f32(pixel.x) * 157.0 + f32(pixel.y) * 293.0;
  let num_colonies = i32(1.0 + p1 * 5.0);

  // Water background
  let water_grad = uv.y * 0.5 + 0.5;
  var color = mix(
    vec3<f32>(0.03, 0.15, 0.25),
    vec3<f32>(0.08, 0.30, 0.40),
    clamp(water_grad, 0.0, 1.0)
  );

  // Light rays from surface
  let light_rays = sin(uv.x * 8.0 + time * p2 * 0.2) * 0.5 + 0.5;
  color += vec3<f32>(0.05, 0.12, 0.10) * light_rays * exp(uv.y * 2.0) * 0.3;

  // Evaluate all coral colonies
  var min_sdf = 1000.0;
  var coral_col = vec3<f32>(0.0);

  for (var c = 0; c < num_colonies; c++) {
    let c_seed = seed + f32(c) * 317.0;
    let root_x = (hashf(c_seed) - 0.5) * 1.6;
    let root_y = 0.4 + hashf(c_seed + 1.0) * 0.2;

    // Mouse plants coral at clicked position
    var root = vec2<f32>(root_x, root_y);
    if mouseDown && c == 0 {
      root = (mouse - 0.5) * 2.0;
      root.y = max(root.y, -0.3);
    }

    // Scale with parameter
    let zoom = 0.5 + p3 * 1.5;
    let local_uv = uv / zoom;
    let local_root = root / zoom;

    let result = coral_sdf(local_uv, local_root, c_seed, time, p2);
    let dist = result.x;

    if dist < min_sdf {
      min_sdf = dist;
      coral_col = result.yzw;
      coral_col = coral_color(result.w, hashf(c_seed + 5.0), p4);
    }
  }

  // Render SDF
  if min_sdf < 1000.0 {
    let smooth_width = 0.003;
    let mask = 1.0 - smoothstep(-smooth_width, smooth_width, min_sdf);

    // Inner shading
    let inner = smoothstep(0.0, 0.01, -min_sdf);
    let shade = mix(0.6, 1.0, inner);

    // Edge glow
    let edge_glow = exp(-abs(min_sdf) * 60.0) * 0.3;

    color = mix(color, coral_col * shade + vec3<f32>(0.3, 0.5, 0.4) * edge_glow, mask);
  }

  // Caustics (underwater light patterns)
  let caustic_uv = uv * 3.0 + vec2<f32>(time * p2 * 0.1, time * p2 * 0.07);
  let caustic = sin(caustic_uv.x) * sin(caustic_uv.y) * 0.5 + 0.5;
  caustic *= sin(caustic_uv.x * 1.7 + caustic_uv.y * 0.8) * 0.5 + 0.5;
  color += vec3<f32>(0.08, 0.15, 0.12) * caustic * exp(uv.y) * 0.15;

  // Vignette for underwater feel
  let vignette = 1.0 - smoothstep(0.4, 1.0, length(uv));
  color *= 0.7 + vignette * 0.3;

  textureStore(writeTexture, pixel, vec4<f32>(color, 1.0));
}
