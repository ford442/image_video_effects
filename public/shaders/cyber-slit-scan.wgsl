// ────────────────────────────────────────────────────────────────────────────────
//  Cyber Slit Scan — Batch 67
//  fp128 conveyor phase, traveling scan heads, phosphor aurora bands,
//  exact C conveyor, capped click injections, held slit bend, ACES.
// ────────────────────────────────────────────────────────────────────────────────
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

const TAU: f32 = 6.28318530718;

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

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
  let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let e = 1.0e-10;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn aurora_runner(y: f32, time: f32, mids: f32) -> f32 {
  let phase = fp128_sum(fp128_mul(fp128(y), fp128(0.012)), fp128_mul(fp128(time), fp128(3.2 + mids)));
  return 0.5 + 0.5 * cos(fp128_val(phase) * TAU * 0.07);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = u.config.zw;
  let width = u32(dims.x);
  let height = u32(dims.y);
  if (gid.x >= width || gid.y >= height) { return; }

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  let bitCrush = u.zoom_params.y;
  let hueShift = u.zoom_params.z;
  let artifactAmt = u.zoom_params.w;

  var slitX = u32(mouse.x * dims.x);
  if (mouse.x < 0.0) { slitX = width / 2u; }
  slitX = clamp(slitX, 0u, width - 1u);

  let scanHead = 0.5 + 0.5 * sin(time * (1.0 + u.zoom_params.x * 5.0) + f32(gid.y) * 0.025);
  let speed = 1u + u32(clamp(u.zoom_params.x + scanHead * 0.12 + bass * 0.1, 0.0, 1.0) * 5.0);

  var outputColor: vec4<f32>;
  if (gid.x >= width - speed) {
    let uvSource = vec2<f32>(f32(slitX) / dims.x, f32(gid.y) / dims.y);
    var color = textureSampleLevel(readTexture, u_sampler, uvSource, 0.0);

    let bits = mix(255.0, 2.0, bitCrush);
    color = floor(color * bits) / bits;

    let scanPhase = fp128_sum(fp128_mul(fp128(time), fp128(10.0)), fp128(f32(gid.y) * 0.01));
    if (fract(fp128_val(scanPhase)) > 0.98) { color *= 1.5; }

    let scanBand = smoothstep(0.04, 0.0, abs(fract(f32(gid.y) * 0.018 - time * (2.4 + bass * 1.5)) - 0.5));
    let oilSlick = vec3<f32>(aurora_runner(f32(gid.y), time, mids));
    color.rgb = color.rgb + oilSlick * scanBand * (0.25 + artifactAmt * 0.35) * (1.0 + treble * 0.3);

    var hsv = rgb2hsv(color.rgb);
    hsv.y = min(hsv.y * 1.2, 1.0);
    hsv.z = min(hsv.z * 1.1, 1.0);
    hsv.x = fract(hsv.x + hueShift + mouse.y * 0.5 + mids * 0.12 + select(0.0, 0.08, held));
    outputColor = vec4<f32>(hsv2rgb(hsv), color.a);
  } else {
    let diagonal = sin((f32(gid.x + gid.y) * 0.035) - time * 5.0) * artifactAmt * (2.0 + treble * 8.0);
    let heldBend = select(0.0, (mouse.x - f32(gid.x) / dims.x) * 18.0 * artifactAmt, held);
    var clickKick = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
      let event = u.ripples[i];
      let age = max(time - event.z, 0.0);
      if (age < 1.4) {
        let d = length(vec2<f32>(gid.xy) / dims - event.xy);
        clickKick += exp(-age * 2.0) * exp(-abs(d - age * 0.4) * 55.0) * 12.0;
      }
    }
    let sourceY = clamp(i32(gid.y) + i32(diagonal + heldBend + clickKick), 0, i32(height) - 1);
    let sourceX = min(gid.x + speed, width - 1u);
    outputColor = textureLoad(dataTextureC, vec2<i32>(i32(sourceX), sourceY), 0);

    let conveyorPhase = fp128_sum(fp128_mul(fp128(f32(gid.x)), fp128(0.04)), fp128_mul(fp128(time), fp128(1.8 + bass)));
    let conveyor = smoothstep(0.06, 0.0, abs(fract(fp128_val(conveyorPhase)) - 0.5));
    outputColor.rgb = outputColor.rgb * (1.0 - conveyor * artifactAmt * 0.12);
  }

  var clickFront = 0.0;
  let rippleCount2 = min(u32(u.config.y), 50u);
  for (var j = 0u; j < rippleCount2; j = j + 1u) {
    let rp = u.ripples[j];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.4) {
      let d = length(vec2<f32>(gid.xy) / dims - rp.xy);
      clickFront = max(clickFront, exp(-d * 120.0) * (1.0 - age / 1.4));
    }
  }
  outputColor.rgb += vec3<f32>(0.2, 0.85, 1.0) * clickFront * (0.5 + bass);

  let rgb = acesToneMap(outputColor.rgb);
  let alpha = clamp(outputColor.a * 0.85 + clickFront * 0.12 + scanHead * 0.05, 0.06, 0.98);

  textureStore(dataTextureA, pixel, vec4<f32>(rgb, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(rgb, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
