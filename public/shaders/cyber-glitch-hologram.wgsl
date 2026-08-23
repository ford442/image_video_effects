// ═══════════════════════════════════════════════════════════════════
//  Cyber Glitch Hologram — Batch 66
//  fp128 fringe phase, structure-tensor datamosh, dual-layer parallax,
//  C smear trails, racing scan carriers, capped click bursts, held widens
//  glitch halo, ACES + semantic alpha.
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

const TAU: f32 = 6.28318530718;

// 128-bit path: value = base + mantissa (Knuth two-sum / Dekker expansion)
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

struct Fp128Vec2 {
  base: vec2<f32>,
  mant: vec2<f32>,
}

fn fp128v2_add(a: Fp128Vec2, b: Fp128Vec2) -> Fp128Vec2 {
  return Fp128Vec2(a.base + b.base, a.mant + b.mant);
}

fn fp128v2_val(v: Fp128Vec2) -> vec2<f32> {
  return v.base + v.mant;
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(41.0, 289.0))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(41.0, 289.0)));
  return fract(vec2<f32>(n, n * 1.618) * 43758.5453);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn structure_tensor(uv: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
  let e = vec2<f32>(1.0) / res;
  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-e.x, 0.0), 0.0).r;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(e.x, 0.0), 0.0).r;
  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, e.y), 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -e.y), 0.0).r;
  return vec2<f32>(r - l, t - b);
}

// Closed-form racing scan packet (fast motion family #1)
fn racing_scan_carrier(uv: vec2<f32>, time: f32, speed: f32, bass: f32) -> f32 {
  let head = fract(time * (2.4 + speed * 6.0 + bass * 3.0));
  let dist = abs(uv.y - head);
  return pow(max(0.0, 1.0 - dist * 18.0), 6.0);
}

// fp128-integrated interference phase (fast motion family #2)
fn hologram_fringe(uv: vec2<f32>, time: f32, mids: f32, scanSpeed: f32) -> f32 {
  let rate = fp128_mul(fp128(4.0 + mids * 6.0), fp128(scanSpeed + 0.15));
  let spatial = fp128_mul(fp128(uv.x + uv.y * 0.7), fp128(180.0 + mids * 60.0));
  let phase = fp128_sum(fp128_sum(spatial, fp128_mul(rate, fp128(time))), fp128_mul(fp128(TAU), fp128(sin(time * 0.37) * 0.5)));
  return cos(fp128_val(phase)) * 0.5 + 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(global_id.xy);

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let aspect = resolution.x / resolution.y;
  let holoIntensity = u.zoom_params.x;
  let glitchAmount = u.zoom_params.y;
  let scanSpeed = u.zoom_params.z;
  let blockScale = mix(16.0, 96.0, u.zoom_params.w);

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  let mouseDist = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
  let mouseInfluence = smoothstep(0.35, 0.0, mouseDist) * holoIntensity * select(1.0, 1.35, held);
  let deadZone = smoothstep(0.12, 0.0, mouseDist) * 0.7;

  // Continuous block hash — no floor(time) strobing
  let blockPhase = time * (3.0 + bass * 2.0);
  let blockUV = floor(uv * blockScale) / blockScale;
  let blockHash = hash12(blockUV * 13.37 + vec2<f32>(sin(blockPhase), cos(blockPhase * 1.37)));
  let swapTrigger = step(0.88 - bass * 0.22, blockHash);
  let swapDir = hash22(blockUV * 7.91 + vec2<f32>(blockPhase * 0.7, blockPhase * 0.4)) - 0.5;
  let swapOffset = swapDir * swapTrigger * glitchAmount * 0.07;

  let motion = structure_tensor(uv, resolution);
  let datamosh = motion * glitchAmount * 0.04 * (0.5 + bass * 0.5);

  // fp128 UV advection for long-run stability
  var uv128 = Fp128Vec2(uv, vec2<f32>(0.0));
  uv128 = fp128v2_add(uv128, Fp128Vec2(swapOffset + datamosh, vec2<f32>(0.0)));
  let baseUV = clamp(fp128v2_val(uv128), vec2<f32>(0.001), vec2<f32>(0.999));

  let parallax = depth * 0.025 * vec2<f32>(sin(time * 1.4), cos(time * 1.1));
  let layer1 = clamp(baseUV + parallax, vec2<f32>(0.001), vec2<f32>(0.999));
  let layer2 = clamp(baseUV - parallax * 0.5, vec2<f32>(0.001), vec2<f32>(0.999));

  let chroma = vec2<f32>(0.005 + treble * 0.012, 0.0) * mouseInfluence;
  let uvR1 = clamp(layer1 + chroma * 1.5, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB1 = clamp(layer1 - chroma * 1.2, vec2<f32>(0.001), vec2<f32>(0.999));
  let col1 = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR1, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, layer1, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB1, 0.0).b
  );

  let uvR2 = clamp(layer2 + chroma * 0.8, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB2 = clamp(layer2 - chroma * 0.6, vec2<f32>(0.001), vec2<f32>(0.999));
  let col2 = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR2, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, layer2, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB2, 0.0).b
  );

  let baseColor = mix(col1, col2, depth * 0.5 + 0.25);

  let fringe = hologram_fringe(uv, time, mids, scanSpeed);
  let hologram = vec3<f32>(0.0, 0.85, 1.0) * fringe * mouseInfluence * 0.25 +
                 vec3<f32>(1.0, 0.0, 0.75) * (1.0 - fringe) * mouseInfluence * 0.18;

  let scanline = sin((uv.y + time * scanSpeed * (1.0 + treble * 0.4)) * resolution.y * 0.22) * 0.5 + 0.5;
  let banding = step(0.35, scanline) * 0.12 * mouseInfluence;
  let racer = racing_scan_carrier(uv, time, scanSpeed, bass);

  let prev = textureLoad(dataTextureC, pixel, 0);
  let smear = mix(prev.rgb * 0.88, baseColor, 0.12);

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.4) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickBurst += smoothstep(0.035, 0.0, abs(rDist - age * 0.38)) * exp(-age * 1.6);
    }
  }

  let glitchCorruption = swapTrigger * glitchAmount * 0.45 + deadZone * 0.25;
  let noise = hash12(uv * 200.0 + time * 50.0);
  let deadZoneMask = deadZone * noise * 0.3;

  var hdr = mix(baseColor, smear, racer * 0.22) * (0.8 + mouseInfluence * 0.3) + hologram + banding;
  hdr = hdr + vec3<f32>(0.2, 0.95, 1.0) * racer * mouseInfluence * (0.15 + treble * 0.2);
  hdr = hdr * (1.0 - deadZoneMask) + vec3<f32>(0.05, 0.12, 0.15) * deadZoneMask;
  hdr = hdr + vec3<f32>(0.35, 0.9, 1.0) * clickBurst * (0.4 + bass * 0.3);

  let band = min(u32(uv.x * 8.0), 7u);
  hdr = hdr + vec3<f32>(0.04, 0.1, 0.14) * plasmaBuffer[band + 1u].x * mouseInfluence * 0.12;

  let tonemapped = aces_tonemap(hdr);
  let confidence = mouseInfluence * (1.0 - deadZone * 0.6);
  let alpha = clamp(confidence * (1.0 - glitchCorruption) * 0.85 + banding * 0.3 + bass * 0.04 + clickBurst * 0.15, 0.06, 0.92);
  let outDepth = clamp(depth + mouseInfluence * 0.06, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(tonemapped, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(smear, alpha));
}
