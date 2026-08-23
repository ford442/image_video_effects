// ═══════════════════════════════════════════════════════════════════
//  Data Slicer Interactive — Batch 67
//  fp128 slice phase, exact C feedback, capped ripples, racing
//  fracture packet, held gravity well, ACES + semantic alpha.
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
const EPS: f32 = 1e-4;

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

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbmLod(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

fn domainWarp(p: vec2<f32>, warpStrength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbmLod(p, octaves), fbmLod(p + vec2<f32>(5.2, 1.3), octaves));
    return p + warpStrength * q;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn fracture_packet(uv: vec2<f32>, time: f32, speed: f32) -> f32 {
  let head = fract(time * (1.6 + speed * 4.0));
  return pow(max(0.0, 1.0 - abs(uv.x - head) * 14.0), 4.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let held = mouseDown > 0.5;

    let bassRaw = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    let prevBass = prev.a;
    let bass = mix(prevBass, bassRaw, select(0.15, 0.8, bassRaw > prevBass));

    let densityParam = u.zoom_params.x;
    let dispParam = u.zoom_params.y;
    let jitterParam = u.zoom_params.z;
    let shockParam = u.zoom_params.w;

    let sliceCount = mix(4.0, 32.0, densityParam) * (1.0 + bass * 0.5);
    let sliceWidth = 0.03;
    let dispMag = mix(0.05, 0.35, dispParam) * (1.0 + mids * 0.8);
    let jitterAmt = jitterParam * 0.25;
    let shockStrength = mix(0.0, 2.0, shockParam);
    let packet = fracture_packet(uv01, time, densityParam);

    let aspect = res.x / max(res.y, 1.0);
    let dMouse = (uv01 - mouse) * vec2<f32>(aspect, 1.0);
    let distMouse = length(dMouse);
    let gravity = (1.0 - smoothstep(0.0, 0.35, distMouse)) * select(1.0, 1.5, held);

    let slicePhase = fp128_mul(fp128(uv01.y), fp128(sliceCount));
    let sliceIndex = floor(fp128_val(slicePhase));
    let invSliceCount = 1.0 / max(sliceCount, EPS);
    let sliceY = sliceIndex * invSliceCount;
    let nextSliceY = (sliceIndex + 1.0) * invSliceCount;

    let lodOct = select(2, 4, distMouse < 0.4);
    let edgeNoise = fbmLod(vec2<f32>(uv01.x * 8.0, sliceY * 4.0 + time * 0.35), lodOct);
    let warpedSliceWidth = sliceWidth + edgeNoise * 0.03;
    let distToSlice = min(abs(uv01.y - sliceY), abs(uv01.y - nextSliceY));
    let strength = 1.0 - smoothstep(0.0, max(warpedSliceWidth, EPS), distToSlice);

    if (strength < 0.005 && gravity < 0.01 && packet < 0.01) {
        let base = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
        let alpha = clamp(luma(base) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3);
        textureStore(writeTexture, pixel, vec4<f32>(base, alpha));
        textureStore(dataTextureA, pixel, vec4<f32>(base, bass));
        textureStore(dataTextureB, pixel, vec4<f32>(0.0, 0.0, 0.0, bass));
        textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }

    var burst = 0.0;
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let rDist = length(uv01 - rp.xy);
        let rAge = time - rp.z;
        let rRadius = rAge * 0.5;
        let rBand = abs(rDist - rRadius);
        let inRing = f32(rBand < 0.04 && rAge >= 0.0 && rAge < 1.2);
        let decay = clamp(1.0 - rAge / 1.2, 0.0, 1.0);
        let rStrength = max(rp.w, 0.2);
        burst += inRing * decay * rStrength * 0.15 * sin(rDist * 50.0 - rAge * 20.0);
        shock += smoothstep(0.04, 0.0, rBand) * decay * rStrength;
    }
    shock *= shockStrength;

    let quant = mix(20.0, 70.0, mids);
    let quantY = floor(uv01.y * quant) / quant;
    let n = valueNoise(vec2<f32>(quantY * 10.0, time * 3.0 * (1.0 + treble)));

    let jitterWarp = domainWarp(vec2<f32>(uv01.x * 6.0, sliceY * 12.0), 0.6, 2);
    let jitterNoise = fbmLod(vec2<f32>(jitterWarp.x, sliceY * 8.0 + time * 0.6), 3);
    let jitter = (jitterNoise - 0.5) * 2.0 * jitterAmt;
    let jitterBlend = clamp(jitterParam * 1.5, 0.0, 1.0);

    var offset = (n - 0.5) * dispMag * strength;
    offset = mix(offset, offset + jitter * strength, jitterBlend);
    offset += burst * strength * (1.0 + shock * 0.5) + packet * 0.02;
    offset *= 1.0 + shock;
    offset *= mix(1.0, select(-1.0, 1.0, fract(sliceIndex * 0.5) < 0.25), 0.8);
    offset += gravity * 0.02 * sin(uv01.x * 20.0 + time);

    var split = 0.02 * strength * (1.0 + bass * 2.0) * (1.0 + shock * 0.75) * (1.0 + depth * 0.5);
    let alphaMod = 1.0 - strength * 0.35;

    let center = vec2<f32>(0.5);
    let delta = uv01 - center;
    let dir = delta * inverseSqrt(max(dot(delta, delta), 0.000001));
    let caStr = (0.003 * (1.0 + bass) + depth * 0.001) * strength;

    let rUv = clamp(uv01 + vec2<f32>(offset + split, 0.0) + dir * caStr, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUv = clamp(uv01 + vec2<f32>(offset - split, 0.0) - dir * caStr * 0.6, vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv01 + vec2<f32>(offset, 0.0), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUv, 0.0).b;

    let feedbackCoord = clamp(vec2<i32>((uv01 + vec2<f32>(offset * 0.3, 0.0)) * res), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    let prevCol = textureLoad(dataTextureC, feedbackCoord, 0);
    let fbAmt = 0.12 * strength + select(0.0, 0.25, held);
    var color = mix(vec3<f32>(r, g, b), prevCol.rgb, fbAmt);

    let edgeT = 1.0 - smoothstep(0.0, max(warpedSliceWidth * 0.25, EPS), distToSlice);
    let edgeGlow = edgeT * strength * (0.25 + treble * 0.4 + shock * 0.3 + packet * 0.2);
    color += vec3<f32>(edgeGlow * 0.9, edgeGlow * 0.55, edgeGlow * 1.1);
    color *= 1.0 + 0.06 * sin(uv01.y * res.y * PI) * strength;
    color += vec3<f32>(treble * strength * 0.25, treble * strength * 0.15, treble * strength * 0.1);
    color += vec3<f32>(shock * strength * 0.15);
    color = mix(color, color * 1.3, depth * strength * 0.5);
    color = acesToneMap(color * (0.9 + mids * 0.2));

    let alpha = clamp(luma(color) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3) * alphaMod + packet * 0.08;
    let trail = mix(prevCol.rgb * 0.92, color, 0.15 + bass * 0.15 + shock * 0.1);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, bass));
    textureStore(dataTextureB, pixel, vec4<f32>(strength, offset, split, bass));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
