// ═══════════════════════════════════════════════════════════════════
//  Diffusion-Limited Aggregation Copper Deposition
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-31
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
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}


fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p;
  let k = vec3<f32>(0.3183099, 0.3678794, 0.4342945);
  pp = fract(pp * k.xy);
  pp += dot(pp, pp.yx + 19.19);
  return fract(vec2<f32>((pp.x + pp.y) * pp.x, (pp.x + pp.y) * pp.y));
}

fn noise2d(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = dot(i, vec2<f32>(127.1, 311.7));
  return mix(mix(fract(sin(n + 0.0) * 43758.5453),
                 fract(sin(n + 1.0) * 43758.5453), u.x),
             mix(fract(sin(n + 127.1) * 43758.5453),
                 fract(sin(n + 128.1) * 43758.5453), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    val += amp * noise2d(p * freq);
    freq *= 2.0;
    amp *= 0.5;
  }
  return val;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;

  // Seed crystal center with ripple nucleation
  var seedPos = vec2<f32>(0.5, 0.5);
  let rippleCount = u32(u.config.y);
  if (rippleCount > 0u) {
    seedPos = u.ripples[0].xy;
  }

  // Domain-warped fBm for walker trails
  var p = uv * (4.0 + p1 * 4.0);
  let warp = vec2<f32>(fbm(p + vec2<f32>(0.0, 1.7), 4),
                       fbm(p + vec2<f32>(5.2, 1.3), 4));
  p += warp * (0.6 + mids * 0.5);

  // Polar coordinates toward seed
  let toSeed = seedPos - uv;
  let polar = vec2<f32>(length(toSeed), atan2(toSeed.y, toSeed.x));

  // Dendrite arms with angular periodicity
  let arms = 5.0 + p2 * 8.0;
  let armMod = sin(polar.y * arms + fbm(p, 3) * 3.14159);
  let radialNoise = fbm(vec2<f32>(polar.x * 5.0, armMod * 2.0), 6);
  let stickProb = 0.35 + mids * 0.35;
  var dendrite = smoothstep(0.45 - stickProb * 0.15, 0.55 + stickProb * 0.1,
                            radialNoise * armMod);

  // Bass spawns denser walker clusters
  let walkers = fbm(p * (1.5 + bass * 2.0) + time * 0.15, 4);
  let cluster = smoothstep(0.55 - bass * 0.2, 0.7, walkers);
  let deposit = max(dendrite, cluster * 0.55);

  // Electrolyte depletion near growth
  let depletion = smoothstep(0.0, 0.35, deposit) * (1.0 - smoothstep(0.2, 0.8, polar.x));

  // Treble spark discharge at tips
  let sparkHash = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  let spark = step(0.88, deposit) * step(0.75, fract(sparkHash + time * 4.0 + treble * 3.0));

  // Metallic copper palette with patina
  let freshCopper = vec3<f32>(0.72, 0.45, 0.2);
  let oxidized = vec3<f32>(0.12, 0.32, 0.28);
  let bronze = vec3<f32>(0.55, 0.35, 0.15);
  let age = smoothstep(0.0, 1.0, polar.x + fbm(p * 2.0, 2) * 0.3);
  var color = mix(freshCopper, bronze, age * 0.5);
  color = mix(color, oxidized, depletion * (0.5 + treble * 0.3));

  // HDR specular on tips + spark
  let highlight = pow(deposit, 4.0) * (0.6 + 0.4 * sin(time * 2.5));
  color += vec3<f32>(0.35, 0.22, 0.08) * highlight;
  color += vec3<f32>(1.0, 0.85, 0.5) * spark * treble * 2.5;

  // ACES tone mapping
  color = color * (2.51 * color + 0.03) / (color * (2.43 * color + 0.59) + 0.14);

  // Alpha: density × (1.0 - depletion)
  let alpha = clamp(deposit * (1.0 - depletion * 0.7) + spark * 0.3, 0.0, 1.0);
  let out = vec4<f32>(color, alpha);

  // Depth: deposited metal sits closer (higher) than depleted electrolyte
  let depth = clamp(deposit * (1.0 - polar.x), 0.0, 1.0);
  textureStore(writeTexture, coord, applyGenerativePrimaryControls(out));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, out);
}
