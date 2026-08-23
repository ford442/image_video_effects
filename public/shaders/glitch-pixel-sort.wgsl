// ═══════════════════════════════════════════════════════════════
//  Glitch Pixel Sort — Batch 66
//  fp128 sort displacement, exact C temporal melt, racing bright
//  streak packets, capped click ripples, held deepens melt, ACES +
//  semantic alpha.
// ═══════════════════════════════════════════════════════════════

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

struct Fp128Vec2 {
  base: vec2<f32>,
  mant: vec2<f32>,
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

fn fp128v2_add(a: Fp128Vec2, b: Fp128Vec2) -> Fp128Vec2 {
  return Fp128Vec2(a.base + b.base, a.mant + b.mant);
}

fn fp128v2_val(v: Fp128Vec2) -> vec2<f32> {
  return v.base + v.mant;
}

fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(5.3983, 5.4427));
    p2 = p2 + dot(p2.yx, p2.xy + vec2<f32>(21.5351, 14.3137));
    return fract(p2.x * p2.y * 95.4337);
}

fn hash3(p: vec3<f32>) -> f32 {
    var p2 = fract(p * vec3<f32>(5.3983, 5.4427, 5.3987));
    p2 = p2 + dot(p2.yzx, p2.xyz + vec3<f32>(21.5351, 14.3137, 23.5123));
    return fract(p2.x * p2.y * p2.z * 95.4337);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i + vec2<f32>(0.0, 0.0)), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn streak_packet(uv: vec2<f32>, dir: vec2<f32>, time: f32, bass: f32) -> f32 {
  let along = dot(uv, normalize(dir + vec2<f32>(0.0001)));
  let head = fract(time * (0.8 + bass * 1.6) + along * 2.0);
  let d = abs(fract(along * 3.0) - head);
  return pow(max(0.0, 1.0 - d * 8.0), 4.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let coord = vec2<i32>(global_id.xy);
    let held = u.zoom_config.w > 0.5;
    let aspect = resolution.x / resolution.y;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let threshold = clamp(u.zoom_params.x - bass * 0.2, 0.0, 1.0);
    let sortMode = u.zoom_params.y;
    let glitchAmount = clamp(u.zoom_params.z + mids * 0.3, 0.0, 1.0) * select(1.0, 1.25, held);

    var baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let baseLuma = getLuminance(baseColor.rgb);

    var sortDir: vec2<f32>;
    if (sortMode < 0.5) {
        sortDir = vec2<f32>(1.0, 0.0);
    } else if (sortMode < 1.5) {
        sortDir = vec2<f32>(0.0, 1.0);
    } else {
        let angle = time * 0.25 + noise(uv * 20.0) * 3.14159;
        sortDir = vec2<f32>(cos(angle), sin(angle));
    }

    let maxSortDist = 0.05 + bass * 0.15;
    let thresholdMask = smoothstep(threshold - 0.1, threshold + 0.1, baseLuma);

    let disp = fp128_mul(fp128_mul(fp128(baseLuma), fp128(maxSortDist)), fp128(thresholdMask));
    var sortUV128 = Fp128Vec2(uv, vec2<f32>(0.0));
    sortUV128 = fp128v2_add(sortUV128, Fp128Vec2(-sortDir * fp128_val(disp), vec2<f32>(0.0)));
    var sortUV = clamp(fp128v2_val(sortUV128), vec2<f32>(0.0), vec2<f32>(1.0));

    if (hash3(vec3<f32>(uv.x * 50.0, uv.y * 50.0, time)) < glitchAmount * 0.2) {
        sortUV = sortUV + sortDir * (hash2(uv) * 0.1);
    }

    var finalColor = textureSampleLevel(readTexture, u_sampler, sortUV, 0.0);

    let meltRate = fp128_sum(fp128(0.005 + bass * 0.01), fp128(0.003 * select(0.0, 1.0, held)));
    let prevCoord = vec2<i32>(clamp(vec2<i32>((uv - sortDir * fp128_val(meltRate)) * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1)));
    let prevColor = textureLoad(dataTextureC, prevCoord, 0);
    let prevLuma = getLuminance(prevColor.rgb);
    let currLuma = getLuminance(finalColor.rgb);

    let packet = streak_packet(uv, sortDir, time, bass);
    if (prevLuma > currLuma + 0.05 && prevLuma > threshold) {
        finalColor = mix(finalColor, prevColor, 0.85 + packet * 0.1);
    }

    if (glitchAmount > 0.3 && hash2(uv + time) < 0.1) {
        let r = textureSampleLevel(readTexture, u_sampler, uv + sortDir * 0.01, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, uv - sortDir * 0.01, 0.0).b;
        finalColor = vec4<f32>(r, finalColor.g, b, finalColor.a);
    }

    var clickBurst = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age >= 0.0 && age < 1.4) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            clickBurst += smoothstep(0.02, 0.0, abs(rDist - age * 0.35)) * exp(-age * 1.5);
        }
    }

    var rgb = acesToneMap(finalColor.rgb + vec3<f32>(packet * 0.2 + clickBurst * 0.25));
    let alpha = clamp(finalColor.a * 0.85 + packet * 0.1 + clickBurst * 0.12 + treble * 0.05, 0.06, 0.98);

    textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(rgb, alpha));

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
