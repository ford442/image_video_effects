// ═══════════════════════════════════════════════════════════════════
//  Magnetic Chroma v2
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: magnetic-chroma
//  Upgraded: 2026-05-30
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = mix(
    mix(hash22(i + vec2<f32>(0.0, 0.0)).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
    mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
    u.y
  );
  return n;
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let v = max(c.r, max(c.g, c.b));
  let minc = min(c.r, min(c.g, c.b));
  let s = select(0.0, (v - minc) / v, v > 0.0);
  let d = v - minc;
  var h = 0.0;
  if (c.r == v) {
    h = (c.g - c.b) / d;
  } else if (c.g == v) {
    h = (c.b - c.r) / d + 2.0;
  } else {
    h = (c.r - c.g) / d + 4.0;
  }
  return vec3<f32>(fract(h / 6.0), s, v);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let h = c.x * 6.0;
  let i = floor(h);
  let f = h - i;
  let p = c.z * (1.0 - c.y);
  let q = c.z * (1.0 - f * c.y);
  let t = c.z * (1.0 - (1.0 - f) * c.y);
  if (i == 0.0) { return vec3<f32>(c.z, t, p); }
  if (i == 1.0) { return vec3<f32>(q, c.z, p); }
  if (i == 2.0) { return vec3<f32>(p, c.z, t); }
  if (i == 3.0) { return vec3<f32>(p, q, c.z); }
  if (i == 4.0) { return vec3<f32>(t, p, c.z); }
  return vec3<f32>(c.z, p, q);
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn magnetic_field(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32, strength: f32) -> vec2<f32> {
  let d = uv - mouse;
  let da = vec2<f32>(d.x * aspect, d.y);
  let dist = length(da);
  let safe = max(dist, 0.0001);
  let radial = da / safe;
  let tangent = vec2<f32>(-radial.y, radial.x);
  let field = radial * (1.0 / (dist * dist + 0.01)) * strength;
  let dipole = tangent * exp(-dist * 3.0) * strength * 0.5;
  return vec2<f32>(field.x / aspect, field.y) + vec2<f32>(dipole.x / aspect, dipole.y);
}

fn rk2_advect(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32, strength: f32, dt: f32) -> vec2<f32> {
  let k1 = magnetic_field(uv, mouse, aspect, strength);
  let k2 = magnetic_field(uv + k1 * dt * 0.5, mouse, aspect, strength);
  return uv + k2 * dt;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, 0.0, 1.0);

  let fieldStrength = u.zoom_params.x * (1.0 + bass * 0.6);
  let radius = u.zoom_params.y * 0.5 + 0.02;
  let chromatic = u.zoom_params.z * 0.04;
  let falloff = clamp(u.zoom_params.w, 0.0, 0.99);

  let d = uv - mouse;
  let da = vec2<f32>(d.x * aspect, d.y);
  let dist = length(da);
  let influence = 1.0 - smoothstep(radius * (1.0 - falloff), radius, dist);
  let highField = smoothstep(0.3, 0.0, dist) * fieldStrength;

  let dt = 0.003 * (1.0 + treble * 0.5);
  let sepR = chromatic * (1.0 + depth * 0.5);
  let sepG = chromatic * 0.5;
  let sepB = -chromatic * (1.0 + mids * 0.3);

  let uvR = clamp(rk2_advect(uv + vec2<f32>(sepR, 0.0), mouse, aspect, fieldStrength, dt), vec2<f32>(0.001), vec2<f32>(0.999));
  let uvG = clamp(rk2_advect(uv + vec2<f32>(sepG, 0.0), mouse, aspect, fieldStrength, dt), vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB = clamp(rk2_advect(uv + vec2<f32>(sepB, 0.0), mouse, aspect, fieldStrength, dt), vec2<f32>(0.001), vec2<f32>(0.999));

  let colR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
  let colG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
  let colB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
  var baseColor = vec3<f32>(colR, colG, colB);

  let hsv = rgb2hsv(baseColor);
  let hueWarp = hsv.x + influence * fieldStrength * 0.25 + bass * 0.08;
  let satBoost = hsv.y * (1.0 + highField * 0.4);
  baseColor = hsv2rgb(vec3<f32>(fract(hueWarp), clamp(satBoost, 0.0, 1.0), hsv.z));

  let neon = vec3<f32>(0.15, 0.85 + treble * 0.15, 1.0) * highField * (0.25 + bass * 0.12);
  let bloom = vec3<f32>(1.0, 0.3 + mids * 0.2, 0.7) * influence * fieldStrength * 0.18;
  let finalColor = aces_tone_map(baseColor + neon + bloom);

  let chromaticSep = abs(sepR) + abs(sepB);
  let alpha = clamp(fieldStrength * chromaticSep * depth + influence * 0.12 + highField * 0.08, 0.08, 1.0);
  let outDepth = clamp(depth + influence * 0.04 + highField * 0.03, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(fieldStrength, influence, chromaticSep, alpha));
}
