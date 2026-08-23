// ═══════════════════════════════════════════════════════════════════
//  Data Scanner — Batch 66
//  fp128 scan phase, triple racing scan fronts, C smear residue,
//  voronoi data blocks, capped click bursts, held widens band,
//  ACES + semantic alpha.
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

const PHI: f32 = 1.61803398874989484820;
const TAU: f32 = 6.28318530718;

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 {
  return Fp128(x, 0.0);
}

fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  let f = e - (t - s);
  return Fp128(t, f);
}

fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  let f = e - (t - p);
  return Fp128(t, f);
}

fn fp128_val(x: Fp128) -> f32 {
  return x.base + x.mant;
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453123);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
             mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var a = 0.5; var s = 0.0; var q = p;
  for (var i = 0; i < 4; i = i + 1) { s = s + a * vnoise(q); q = q * PHI; a = a * 0.5; }
  return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
  return fbm(p + 4.0 * q);
}

fn voronoiF2F1(p: vec2<f32>) -> f32 {
  var F1 = 1e9; var F2 = 1e9; let ip = floor(p);
  for (var i = -1; i <= 1; i = i + 1) {
    for (var j = -1; j <= 1; j = j + 1) {
      let d = length(p - ip - vec2<f32>(f32(i), f32(j)) - hash22(ip + vec2<f32>(f32(i), f32(j))));
      F2 = select(select(F2, d, d < F2), F1, d < F1);
      F1 = select(F1, d, d < F1);
    }
  }
  return F2 - F1;
}

fn get_luminance(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn sobel(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
  let t = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let l = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  return sqrt(length(r - l) * length(r - l) + length(b - t) * length(b - t));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// fp128-integrated scan position (fast motion #1)
fn scan_front_x(time: f32, mouseX: f32, speed: f32, layer: f32) -> f32 {
  let phase = fp128_sum(fp128_mul(fp128(time), fp128(speed * layer)), fp128(mouseX));
  return fract(fp128_val(phase));
}

// Racing vertical packet (fast motion #2)
fn vertical_packet(uv: vec2<f32>, time: f32, bass: f32) -> f32 {
  let head = fract(time * (1.2 + bass * 2.5));
  let d = abs(uv.y - head);
  return pow(max(0.0, 1.0 - d * 14.0), 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coords = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = 1.0 / resolution;
  let aspect = resolution.x / resolution.y;

  let param1 = u.zoom_params.x;
  let param2 = u.zoom_params.y;
  let param3 = u.zoom_params.z;
  let param4 = u.zoom_params.w;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let held = u.zoom_config.w > 0.5;

  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let warp = vec2<f32>(warpedFBM(uv * 3.0 + mouse.x, time * 0.35),
                       warpedFBM(uv * 3.0 + mouse.x + 10.0, time * 0.35)) * (0.03 * param4);
  let wuv = clamp(uv + warp, vec2<f32>(0.0), vec2<f32>(1.0));

  let scanSpeed = 0.12 + param1 * 0.55 + bass * 0.2;
  let scan1 = scan_front_x(time, mouse.x, scanSpeed, 1.0);
  let scan2 = scan_front_x(time, mouse.x + 0.33, scanSpeed * 1.618, 1.0);
  let scan3 = scan_front_x(time, mouse.x + 0.67, scanSpeed * 0.618, 1.0);

  let scan_width = 0.15 * (1.0 + (param3 - 0.5) * 0.5) * select(1.0, 1.4, held);
  let dist1 = abs(wuv.x - scan1);
  let dist2 = abs(wuv.x - scan2) * 0.7;
  let dist3 = abs(wuv.x - scan3) * 0.5;
  let in_scan = max(smoothstep(scan_width, scan_width - 0.01, dist1),
                    max(smoothstep(scan_width, scan_width - 0.01, dist2),
                        smoothstep(scan_width, scan_width - 0.01, dist3)));

  let vpacket = vertical_packet(uv, time, bass);

  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureLoad(readDepthTexture, coords, 0).r;
  let edge = sobel(uv, texel) * (1.0 + (param4 - 0.5) * 2.0);
  let lum = get_luminance(color);

  let prev = textureLoad(dataTextureC, coords, 0);
  let smear = mix(prev.rgb * 0.86, color, 0.14 * in_scan);

  let dataBlock = smoothstep(0.05, 0.15, voronoiF2F1(wuv * (20.0 * (1.0 + (param3 - 0.5) * 1.0)) + time * 0.25));

  let grid_uv = fract(wuv * (40.0 * (1.0 + (param3 - 0.5) * 1.0)) + warp * 10.0);
  let grid = step(0.95, grid_uv.x) + step(0.95, grid_uv.y);

  let scan_color = vec3<f32>(0.0, lum * 0.5, lum * 0.8);
  let edge_color = vec3<f32>(0.0, 1.0, 0.8);
  let grid_color = vec3<f32>(0.0, 0.5, 0.0);
  let block_color = vec3<f32>(0.0, 0.8, 1.0) * dataBlock;

  var analyzed = mix(scan_color, edge_color, clamp(edge * 4.0, 0.0, 1.0));
  analyzed = max(analyzed, grid_color * grid);
  analyzed = mix(analyzed, analyzed + block_color, in_scan * param4);
  analyzed = analyzed + vec3<f32>(0.1, 0.95, 0.85) * vpacket * (0.2 + treble * 0.3);

  let audioPulse = 1.0 + bass * param2 * 4.0 + mids * param2 * 2.0;
  let borderGlow = 0.005 * (1.0 + bass * param2 * 0.5 + treble * 0.2);
  let border_line = smoothstep(scan_width - borderGlow, scan_width, dist1) *
                    (1.0 - smoothstep(scan_width, scan_width + borderGlow, dist1));
  analyzed = analyzed + vec3<f32>(1.0, 1.0, 1.0) * border_line * 4.0 * audioPulse;

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.3) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickBurst += smoothstep(0.025, 0.0, abs(rDist - age * 0.36)) * exp(-age * 1.7);
    }
  }
  analyzed = analyzed + vec3<f32>(0.4, 1.0, 0.9) * clickBurst * param2;

  let intensity = 0.9 * (0.5 + param1);
  let dimAmount = 0.4 * (1.0 + (param1 - 0.5) * 0.4);
  color = mix(color * dimAmount, mix(analyzed, smear, 0.25), in_scan * intensity);

  let band = min(u32(uv.x * 8.0), 7u);
  color = color + vec3<f32>(0.03, 0.08, 0.12) * plasmaBuffer[band + 1u].x * in_scan * 0.15;

  color = acesToneMap(color);
  let alpha = clamp(mix(0.4 + lum * 0.4, 0.95, in_scan * (0.5 + edge * 2.0) * (1.0 + bass * param2 * 0.5 + mids * 0.1)) + clickBurst * 0.1, 0.06, 0.98);

  textureStore(writeTexture, coords, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coords, vec4<f32>(smear, alpha));
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
