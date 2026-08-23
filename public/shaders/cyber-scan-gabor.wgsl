// ═══════════════════════════════════════════════════════════════════
//  Cyber Scan Gabor — Batch 67
//  fp128 scan phase, Gabor bank, racing horizontal packet, C smear,
//  capped click bursts, held widens band, ACES + semantic alpha.
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
      let x = f32(dx);
      let y = f32(dy);
      let xTheta = x * cosTheta + y * sinTheta;
      let yTheta = -x * sinTheta + y * cosTheta;
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

fn scan_packet(uv: vec2<f32>, time: f32, bass: f32) -> f32 {
  let head = fract(time * (1.0 + bass * 2.0));
  return pow(max(0.0, 1.0 - abs(uv.y - head) * 18.0), 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixelSize = 1.0 / resolution;
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;
  let aspect = resolution.x / resolution.y;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let mousePos = u.zoom_config.yz;
  let scanWidth = (u.zoom_params.x * 0.4 + 0.05) * select(1.0, 1.35, held);
  let gridIntensity = u.zoom_params.y;
  let colorSpeed = u.zoom_params.z * 5.0;
  let freq = mix(0.05, 0.3, u.zoom_params.w);
  let sigma = mix(1.5, 4.0, 0.4);
  let responseScale = mix(0.5, 3.0, 0.5);

  let scanPhase = fp128_sum(fp128(mousePos.y), fp128_mul(fp128(sin(time * (2.0 + bass))), fp128(0.02)));
  let distY = abs(uv.y - fp128_val(scanPhase));
  let scanMask = 1.0 - smoothstep(scanWidth * 0.5, scanWidth, distY);
  let packet = scan_packet(uv, time, bass);

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var finalColor = baseColor.rgb;

  if (scanMask > 0.01) {
    let mouseAngle = atan2(mousePos.y - 0.5, mousePos.x - 0.5);
    let rotationOffset = mouseAngle * 0.5 + time * 0.15 + mids * 0.3;

    let r0 = gaborResponse(uv, 0.0 + rotationOffset, freq, sigma, pixelSize) * responseScale;
    let r45 = gaborResponse(uv, 0.785398 + rotationOffset, freq, sigma, pixelSize) * responseScale;
    let r90 = gaborResponse(uv, 1.570796 + rotationOffset, freq, sigma, pixelSize) * responseScale;
    let r135 = gaborResponse(uv, 2.356194 + rotationOffset, freq, sigma, pixelSize) * responseScale;

    let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));
    let pal135 = palette(r135 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33));

    var gaborColor = pal0 * abs(r0) + pal45 * abs(r45) + pal90 * abs(r90) + pal135 * abs(r135);
    let totalResponse = abs(r0) + abs(r45) + abs(r90) + abs(r135) + 0.001;
    gaborColor = gaborColor / totalResponse * 1.3;

    let stepX = pixelSize.x;
    let stepY = pixelSize.y;
    let edgeVal = length(vec2<f32>(
      length(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(stepX, 0.0), 0.0).rgb - textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(stepX, 0.0), 0.0).rgb),
      length(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, stepY), 0.0).rgb - textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, stepY), 0.0).rgb)
    ));

    let gridVal = smoothstep(0.95, 1.0, max(abs(sin(uv.x * 50.0 * 3.14159)), abs(sin(uv.y * 50.0 * 3.14159))));
    let hue = time * colorSpeed;
    let cyberColor = vec3<f32>(0.5 + 0.5 * sin(hue), 0.5 + 0.5 * sin(hue + 2.09), 0.5 + 0.5 * sin(hue + 4.18));
    var processed = mix(gaborColor, cyberColor, gridVal * gridIntensity) + cyberColor * edgeVal * 3.0;
    processed += vec3<f32>(0.2, 0.95, 1.0) * packet * (0.2 + treble * 0.3);
    processed += sin(uv.y * resolution.y * 0.5) * 0.1;
    finalColor = mix(baseColor.rgb, processed, scanMask);
  } else {
    finalColor = baseColor.rgb * 0.85;
  }

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.3) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickBurst += smoothstep(0.025, 0.0, abs(rDist - age * 0.36)) * exp(-age * 1.6);
    }
  }
  finalColor += vec3<f32>(0.3, 0.9, 1.0) * clickBurst * 0.4;

  let prev = textureLoad(dataTextureC, pixel, 0);
  finalColor = mix(finalColor, prev.rgb * 0.9, scanMask * 0.12);

  let band = min(u32(uv.x * 8.0), 7u);
  finalColor += vec3<f32>(0.03, 0.08, 0.12) * plasmaBuffer[band + 1u].x * scanMask * 0.12;

  finalColor = acesToneMap(finalColor);
  let alpha = clamp(baseColor.a * mix(0.5, 0.95, scanMask) + clickBurst * 0.1 + packet * 0.08, 0.06, 0.98);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
