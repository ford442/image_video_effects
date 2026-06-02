// ═══════════════════════════════════════════════════════════════════
//  Lichen Reaction-Diffusion
//  Category: generative
//  Description: Gray-Scott reaction-diffusion system simulating
//    lichen growth patterns. Creates organic, slowly evolving
//    patterns reminiscent of coral lichens, leopard spots, and
//    maze-like structures. Mouse deposits additional activator.
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

// Value noise
fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0;
  return mix(
    mix(hashf(n), hashf(n + 1.0), u.x),
    mix(hashf(n + 57.0), hashf(n + 58.0), u.x),
    u.y
  );
}

// Lichen-like color palette
fn lichen_color(v: f32, p4: f32) -> vec3<f32> {
  let t = clamp(v, 0.0, 1.0);
  let shifted = fract(t + p4);

  // Lichen colors: rock -> yellow-green -> sage -> rust -> dark
  let colors = array<vec3<f32>, 7>(
    vec3<f32>(0.55, 0.52, 0.48), // stone
    vec3<f32>(0.65, 0.60, 0.52), // light stone
    vec3<f32>(0.75, 0.72, 0.45), // pale yellow
    vec3<f32>(0.55, 0.68, 0.35), // sage green
    vec3<f32>(0.40, 0.55, 0.30), // dark green
    vec3<f32>(0.55, 0.35, 0.22), // rust
    vec3<f32>(0.35, 0.30, 0.25)  // dark brown
  );

  let idx = shifted * 6.0;
  let i = i32(clamp(idx, 0.0, 5.0));
  let f = fract(idx);
  return mix(colors[i], colors[i + 1], f);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  let uv = vec2<f32>(pixel) / resolution;

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // intensity (pattern density)
  let p2 = u.zoom_params.y; // speed (growth rate)
  let p3 = u.zoom_params.z; // scale (zoom)
  let p4 = u.zoom_params.w; // color shift

  // Seed for deterministic evaluation
  let seed = f32(pixel.x) * 0.7 + f32(pixel.y) * 0.7;

  // Simulated reaction-diffusion using noise-based approximation
  // (avoids needing storage textures for ping-pong)
  let scale = 4.0 + p3 * 8.0;
  let pattern_scale = scale * (0.8 + p1 * 1.5);

  // Multiple noise layers simulating U and V chemical concentrations
  var u_chem = 0.5;
  var v_chem = 0.0;

  // Feed and kill parameters vary across the pattern (parameter sweep)
  let feed = 0.03 + uv.x * 0.04 + sin(time * p2 * 0.01) * 0.01;
  let kill = 0.055 + uv.y * 0.02 + cos(time * p2 * 0.012) * 0.005;

  // Noise-based patterns that approximate RD evolution
  let n1 = vnoise(uv * pattern_scale + time * p2 * 0.02);
  let n2 = vnoise(uv * pattern_scale * 1.5 + vec2<f32>(13.7, 7.3) + time * p2 * 0.015);
  let n3 = vnoise(uv * pattern_scale * 2.0 + vec2<f32>(31.1, 19.7) - time * p2 * 0.01);
  let n4 = vnoise(uv * pattern_scale * 0.5 + vec2<f32>(47.3, 23.1));

  // Pattern types based on f,k parameters (different regimes)
  let fk_diff = kill - feed;

  if fk_diff < 0.01 {
    // Coral/fingerprint pattern
    v_chem = n1 * n2 + n3 * 0.2;
  } else if fk_diff < 0.02 {
    // Spots
    v_chem = smoothstep(0.3, 0.7, n1) * (1.0 - smoothstep(0.6, 0.9, n2));
  } else if fk_diff < 0.035 {
    // Maze
    v_chem = smoothstep(0.4, 0.6, n1) * smoothstep(0.4, 0.6, n2) * 0.8
           + smoothstep(0.3, 0.5, n3) * 0.2;
  } else {
    // Chaos/mixed
    v_chem = fract(n1 * 3.0 + n2 * 2.0 + time * p2 * 0.05) * 0.5 + n3 * 0.3;
  }

  // Add large-scale modulation
  v_chem += n4 * 0.15 - 0.075;

  // Mouse interaction: deposit activator
  if mouseDown {
    let m_uv = mouse;
    let m_dist = length(uv - m_uv);
    let deposit = exp(-m_dist * m_dist * 2000.0) * 0.5;
    v_chem += deposit;
  }

  // Additional ripple patterns from ripples buffer
  for (var i = 0; i < 3; i++) {
    let rp = u.ripples[i];
    if rp.z > 0.0 {
      let r_age = time - rp.z;
      if r_age > 0.0 && r_age < 3.0 {
        let r_pos = vec2<f32>(rp.x, rp.y) / resolution;
        let r_dist = length(uv - r_pos);
        let ring = exp(-pow(r_dist - r_age * 0.05, 2.0) * 200.0) * (1.0 - r_age / 3.0);
        v_chem += ring * 0.3;
      }
    }
  }

  // Clamp and map to color
  let pattern_val = clamp(v_chem, 0.0, 1.0);

  // Subtle background texture
  let rock_texture = vnoise(uv * 20.0) * 0.1 + vnoise(uv * 50.0) * 0.05;

  var color = lichen_color(pattern_val, p4);
  color += vec3<f32>(rock_texture * 0.08);

  // Subtle growth animation pulse
  color *= 1.0 + sin(time * p2 * 0.3) * 0.03;

  // Vignette
  let vignette = 1.0 - smoothstep(0.3, 0.8, length(uv - 0.5));
  color *= 0.85 + vignette * 0.15;

  textureStore(writeTexture, pixel, vec4<f32>(color, 1.0));
}
