// ═══════════════════════════════════════════════════════════════════
//  Data Scanner Gabor — Batch 67
//  fp128 scan phase, Gabor orientation bank, vertical packet,
//  capped click bursts, held widens bar, ACES + semantic alpha.
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

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 { return Fp128(x, 0.0); }
fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  return Fp128(t, e - (t - s));
}
fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  return Fp128(t, e - (t - p));
}
fn fp128_val(x: Fp128) -> f32 { return x.base + x.mant; }

fn gaborResponse(uv: vec2<f32>, theta: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> f32 {
  var response = 0.0;
  let maxRadius = min(i32(ceil(sigma * 3.0)), 6);
  let cosTheta = cos(theta);
  let sinTheta = sin(theta);
  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let xTheta = f32(dx) * cosTheta + f32(dy) * sinTheta;
      let yTheta = -f32(dx) * sinTheta + f32(dy) * cosTheta;
      let gaussian = exp(-(xTheta*xTheta + yTheta*yTheta) / (2.0 * sigma * sigma + 0.001));
      let sinusoidal = cos(2.0 * 3.14159265 * freq * xTheta);
      let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(f32(dx), f32(dy)) * pixelSize, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
      response += luma * gaussian * sinusoidal;
    }
  }
  return response;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;
  let aspect = resolution.x / resolution.y;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let freq = mix(0.05, 0.3, u.zoom_params.x);
  let sigma = mix(1.5, 4.0, u.zoom_params.y);
  let responseScale = mix(0.5, 3.0, u.zoom_params.z);
  let scanWidth = mix(0.05, 0.25, u.zoom_params.w) * select(1.0, 1.35, held);

  let mouse = u.zoom_config.yz;
  let scanPhase = fp128_sum(fp128(mouse.x), fp128_mul(fp128(sin(time * (1.5 + bass))), fp128(0.015 * mids)));
  let scan_x = fp128_val(scanPhase);
  let dist = abs(uv.x - scan_x);
  let in_scan = smoothstep(scanWidth, scanWidth - 0.01, dist);

  let packet = pow(max(0.0, 1.0 - abs(uv.y - fract(time * (1.0 + bass * 2.0))) * 16.0), 5.0);

  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  if (in_scan > 0.0) {
    let rot = time * 0.12 + mids * 0.4;
    let r0 = gaborResponse(uv, 0.0 + rot, freq, sigma, pixelSize) * responseScale;
    let r45 = gaborResponse(uv, 0.785398 + rot, freq, sigma, pixelSize) * responseScale;
    let r90 = gaborResponse(uv, 1.570796 + rot, freq, sigma, pixelSize) * responseScale;
    let r135 = gaborResponse(uv, 2.356194 + rot, freq, sigma, pixelSize) * responseScale;

    var analyzed = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67)) * abs(r0);
    analyzed += palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0)) * abs(r45);
    analyzed += palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33)) * abs(r90);
    analyzed += palette(r135 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33)) * abs(r135);
    analyzed = analyzed / (abs(r0) + abs(r45) + abs(r90) + abs(r135) + 0.001) * 1.3;

    let grid = step(0.95, fract(uv * 40.0).x) + step(0.95, fract(uv * 40.0).y);
    analyzed = max(analyzed, vec3<f32>(0.0, 0.5, 0.0) * grid);
    let border = smoothstep(scanWidth - 0.005, scanWidth, dist) * (1.0 - smoothstep(scanWidth, scanWidth + 0.005, dist));
    analyzed += vec3<f32>(1.0) * border * (4.0 + treble);
    analyzed += vec3<f32>(0.2, 0.95, 0.85) * packet * 0.35;

    color = mix(color, analyzed, in_scan * 0.9);
  } else {
    color *= 0.4;
  }

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
  color += vec3<f32>(0.35, 1.0, 0.9) * clickBurst * 0.3;

  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(color, prev.rgb * 0.88, in_scan * 0.1);

  let band = min(u32(uv.x * 8.0), 7u);
  color += vec3<f32>(0.03, 0.08, 0.12) * plasmaBuffer[band + 1u].x * in_scan * 0.12;

  color = acesToneMap(color);
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(mix(0.35 + lum * 0.3, 0.95, in_scan) + clickBurst * 0.1 + packet * 0.08, 0.06, 0.98);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
