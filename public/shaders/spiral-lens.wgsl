// ═══════════════════════════════════════════════════════════════════
//  Spiral Lens v3
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            domain-warp, kaleidoscope, chromatic-dispersion, mobius-lens
//  Complexity: High
//  Upgraded: 2026-06-14
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
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

fn hashf(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453); }
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i: i32 = 0; i < oct; i++) {
        s += a * valueNoise(p * f);
        f *= 2.0; a *= 0.5;
    }
    return s;
}
fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
    return p + strength * q;
}
fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}
fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
    let r = length(uv);
    var a = atan2(uv.y, uv.x);
    let seg = TAU / max(segs, 1.0);
    a = abs(((a % seg) + seg) % seg - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}
fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = dot(b, b);
    return vec2<f32>(dot(a, b), a.y * b.x - a.x * b.y) / max(d, 1e-6);
}
fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
    return cdiv(cmul(a, z) + b, cmul(c, z) + d);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let aspect = res.x / res.y;
    let uv = (uv01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseNdc = (mouse - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);

    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let depth = clamp(textureLoad(readDepthTexture, pixel, 0).r, 0.0, 1.0);

    let spiralTightness = p1 * 4.0 + 1.0;
    let lensStrength = (p2 * 3.0 + 0.1) * (1.0 + bass * 0.5);
    let chromatic = p3 * 0.06 * (1.0 + mids);
    let rotationSpeed = p4 * 2.5 * (1.0 + treble * 0.6);

    let dvecRaw = uv - mouseNdc;
    let mz = mobius(dvecRaw * 2.0,
                    vec2<f32>(cos(time * 0.2), sin(time * 0.2)),
                    vec2<f32>(0.0, 0.05 + bass * 0.08),
                    vec2<f32>(0.0, 0.05 + mids * 0.05),
                    vec2<f32>(1.0, 0.0));
    let segs = 3.0 + treble * 5.0;
    let dvec = kaleido(mz, segs + bass * 2.0);
    let dist = length(dvec);
    let angle = atan2(dvec.y, dvec.x);

    let warpUv = dvec * 3.0 + vec2<f32>(time * 0.2, -time * 0.15);
    let warp = domainWarp(warpUv, 0.25 + mids * 0.2, 3);
    let warpedDist = dist + fbm(warp + time * 0.3, 4) * 0.08 * (1.0 + bass);

    let logSpiral = spiralTightness * log(max(warpedDist, 0.0001)) + time * rotationSpeed;
    let archSpiral = spiralTightness * angle + time * rotationSpeed;
    let spiralBlend = smoothstep(0.0, 0.5, bass);
    let spiralAngle = mix(archSpiral, logSpiral, spiralBlend);
    let spiralDist = spiralTightness * spiralAngle * 0.1;
    let spiralUV = clamp(mouse + vec2<f32>(cos(spiralAngle) * spiralDist / aspect, sin(spiralAngle) * spiralDist), vec2<f32>(0.0), vec2<f32>(1.0));

    let barrel = dist * dist * lensStrength * 0.4;
    let pincushion = -dist * lensStrength * 0.15;
    let lensWarp = mix(barrel, pincushion, smoothstep(0.0, 1.0, p2));
    let lensMask = smoothstep(0.5, 0.0, dist);
    let lensFactor = mix(1.0, 1.0 / max(lensStrength * 0.5 + 0.1, 0.1), lensMask);

    let dir = select(vec2<f32>(0.0), dvec / max(dist, 0.0001), dist > 0.0001);
    let ndcDir = dir / vec2<f32>(aspect, 1.0);
    let lensedNdc = mouseNdc + dvec * lensFactor + dir * lensWarp * lensMask;
    let lensedUV = lensedNdc / vec2<f32>(aspect, 1.0) + vec2<f32>(0.5);
    let sampleUV = mix(lensedUV, spiralUV, lensMask * 0.25);

    let caScale = chromatic * (1.0 + dist * 2.5);
    let rUV = clamp(sampleUV + ndcDir * caScale, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(sampleUV + ndcDir * caScale * 0.3 * dist, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(sampleUV - ndcDir * caScale * (1.0 + dist * 0.8), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var col = vec3<f32>(r, g, b);

    let edgePhase = dist * 6.0 - time * 0.3 + fbm(dvec * 8.0 + time * 0.5, 3);
    let rainbowEdge = smoothstep(0.35, 0.05, abs(fract(edgePhase) - 0.5)) * lensMask;
    let rainbow = vec3<f32>(1.0 - dist, 0.5 + sin(dist * 12.0) * 0.5, dist) * rainbowEdge * mids;

    let caustic = fbm(vec2<f32>(warpedDist * 20.0, angle * 5.0 + time * 3.0), 3) * lensMask * bass;
    let causticLight = vec3<f32>(0.9, 0.95, 1.0) * caustic * 0.35;

    let bloomCenter = exp(-dist * dist * 8.0) * lensStrength * 0.25;
    let bloom = vec3<f32>(1.0, 0.92, 0.78) * bloomCenter * (0.5 + treble * 0.5);

    let focalLength = mix(0.02, 0.15, depth);
    let dof = smoothstep(focalLength, focalLength * 3.0, abs(dist - lensMask * 0.25));
    col = mix(col, col * 0.75, dof);

    let armPhase = spiralAngle * 0.5;
    let armGlow = smoothstep(0.08, 0.0, abs(fract(armPhase) - 0.5)) * lensMask * mids * 0.3;
    let armDetail = sin(armPhase * TAU + dist * 20.0) * 0.5 + 0.5;
    let armColor = vec3<f32>(0.7 + armDetail * 0.2, 0.9, 1.0 - armDetail * 0.15) * armGlow;

    let finalColor = acesToneMap(col + rainbow + causticLight + bloom + armColor);

    let edgeIntensity = rainbowEdge + caustic + armGlow;
    let alpha = clamp(lensStrength * edgeIntensity * depth + lensMask * 0.12 + bloomCenter * 0.1, 0.08, 1.0);
    let outDepth = clamp(depth + lensMask * 0.04 - dof * 0.06, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(lensStrength, edgeIntensity, lensMask, alpha));
}
