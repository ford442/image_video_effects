// ═══════════════════════════════════════════════════════════════════
//  Glitch Slice Mirror — Batch 62
//  fp128 seam integration, spring mass [133..138], racing horizontal
//  fracture packet, capped click bands, held widens glitch halo,
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

fn fp128_val(x: Fp128) -> f32 {
  return x.base + x.mant;
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn fracture_packet(uv: vec2<f32>, time: f32, speed: f32) -> f32 {
  let head = fract(time * (1.8 + speed * 5.0));
  let d = abs(uv.x - head);
  return pow(max(0.0, 1.0 - d * 16.0), 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    let aspect = u.config.z / max(u.config.w, 0.001);
    let held = u.zoom_config.w > 0.5;
    let rawMouse = u.zoom_config.yz;

    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mouse = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
      mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
      var springPos = mouse;
      var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
      if (extraBuffer[138] <= 0.5) {
        springPos = rawMouse;
        springVel = vec2<f32>(0.0);
      } else {
        let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
        let omega = 11.0;
        let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
        springVel += accel * dt;
        springPos += springVel * dt;
      }
      extraBuffer[133] = springPos.x;
      extraBuffer[134] = springPos.y;
      extraBuffer[135] = springVel.x;
      extraBuffer[136] = springVel.y;
      extraBuffer[137] = time;
      extraBuffer[138] = 1.0;
    }

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let paramIntensity = u.zoom_params.x;
    let paramSpeed = u.zoom_params.y;
    let paramScale = u.zoom_params.z;
    let paramDetail = u.zoom_params.w;

    let audioBoost = (1.0 + bass * 0.5 + mids * 0.25) * (1.0 + select(0.0, 0.2, held));

    var clickShift = 0.0;
    var clickDamage = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
      let rp = u.ripples[i];
      let age = time - rp.z;
      let safeAge = max(age, 0.0);
      let live = step(0.0, age) * (1.0 - step(1.4, age));
      let yBand = 1.0 - smoothstep(0.012, 0.085, abs(uv.y - rp.y));
      let xWindow = 1.0 - smoothstep(0.12, 0.75, abs(uv.x - rp.x) * aspect);
      let damage = yBand * (0.3 + xWindow * 0.7) * exp(-safeAge * 2.0) * live;
      let direction = select(-1.0, 1.0, fract(rp.x * 29.0 + rp.y * 13.0) > 0.5);
      clickShift += damage * direction * (0.035 + paramIntensity * 0.05);
      clickDamage = max(clickDamage, damage);
    }

    let seamPhase = fp128_sum(fp128(mouse.x), fp128(clickShift));
    let seamX = clamp(fp128_val(seamPhase), 0.0, 1.0);
    let packet = fracture_packet(uv, time, paramSpeed);

    let mirrorActive = uv.x > seamX;
    var target_uv = uv;
    target_uv.x = select(target_uv.x, seamX - (uv.x - seamX), mirrorActive);

    let glitch_width = 0.1 * max(paramIntensity * 2.0, 0.001) * select(1.0, 1.3, held);
    let dist_to_seam = abs(uv.x - seamX);
    let inGlitch = dist_to_seam < glitch_width || clickDamage > 0.02 || packet > 0.05;

    let seamIntensity = clamp(1.0 - dist_to_seam / max(glitch_width, 0.001), 0.0, 1.0) * audioBoost;
    let intensity = max(seamIntensity, clickDamage * audioBoost) * f32(inGlitch);

    let block_size = vec2<f32>(
        0.02 + paramScale * 0.06,
        0.01 + paramScale * 0.02
    );
    let seed = floor(uv / max(block_size, vec2<f32>(0.001))) + time * (0.15 + paramSpeed * 2.5);
    let blockBin = (u32(abs(floor(seed.x)) + abs(floor(seed.y))) % 8u) + 1u;
    let fftBlock = plasmaBuffer[blockBin].x;
    let noise = fract(hash(fract(seed)) + fftBlock * 0.17 + treble * clickDamage * 0.25);

    let bigNoise = noise > 0.8;
    target_uv.x = select(target_uv.x, target_uv.x + (noise - 0.5) * 0.1 * intensity, bigNoise);
    target_uv = clamp(target_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    let split = (0.005 + paramDetail * 0.03) * (intensity + clickDamage * 0.8 + packet * 0.5) * noise;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(target_uv + vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(target_uv - vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    let lum = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
    var glitchColor = vec4<f32>(acesToneMap(vec3<f32>(r, g, b)), clamp(lum, 0.3, 1.0));

    let scanline = sin(uv.y * (50.0 + paramDetail * 300.0));
    let inScanline = scanline > 0.9;
    glitchColor = select(glitchColor, vec4<f32>(glitchColor.rgb * 0.5, glitchColor.a), inScanline);

    let baseColor = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0);
    var finalColor = mix(baseColor, glitchColor, f32(inGlitch));

    let prev = textureLoad(dataTextureC, coords, 0);
    finalColor = mix(finalColor, prev, packet * 0.12);

    finalColor.rgb = acesToneMap(finalColor.rgb * (0.96 + mids * 0.04));
    let finalLum = dot(finalColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    finalColor.a = clamp(0.5 + intensity * 0.3 + finalLum * 0.2 + packet * 0.1, 0.06, 0.98);

    let depth = textureLoad(readDepthTexture, coords, 0).r;

    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, coords, finalColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
