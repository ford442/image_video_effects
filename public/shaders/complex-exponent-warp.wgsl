// ═══════════════════════════════════════════════════════════════════
//  Complex Exponent Warp  (RETRY expanded upgrade)
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba,
//            complex-math, domain-warp, depth-aware, aces-tone-map,
//            julia-orbit-trap, sdf-cardioid, newton-fractal
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
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn fbmWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    var q = vec2<f32>(fbm(p + vec2<f32>(0.0, 0.0), 3),
                      fbm(p + vec2<f32>(5.2, 1.3), 3));
    q += t * 0.1;
    var r = vec2<f32>(fbm(p + 3.0 * q + vec2<f32>(1.7, 9.2), 3),
                      fbm(p + 3.0 * q + vec2<f32>(8.3, 2.8), 3));
    return r;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}
fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = max(b.x * b.x + b.y * b.y, 0.0001);
    return vec2<f32>((a.x * b.x + a.y * b.y) / d, (a.y * b.x - a.x * b.y) / d);
}
fn complex_pow(z: vec2<f32>, w: vec2<f32>) -> vec2<f32> {
    let r = max(length(z), 0.0001);
    let angle = atan2(z.y, z.x);
    let ln_z = vec2<f32>(log(r), angle);
    let exponent = cmul(w, ln_z);
    let mag = exp(exponent.x);
    return vec2<f32>(mag * cos(exponent.y), mag * sin(exponent.y));
}
fn juliaOrbit(z: vec2<f32>, c: vec2<f32>) -> vec2<f32> {
    var zz = z;
    var trap = 1000.0;
    var iter = 0.0;
    for (var i = 0; i < 24; i = i + 1) {
        zz = cmul(zz, zz) + c;
        let d = length(zz - vec2<f32>(0.5, 0.0));
        trap = min(trap, d);
        if (length(zz) > 2.0) { iter = f32(i); break; }
    }
    return vec2<f32>(trap, iter);
}
fn newtonColor(z: vec2<f32>, t: f32) -> vec3<f32> {
    var zz = z;
    for (var i = 0; i < 8; i = i + 1) {
        let z2 = cmul(zz, zz);
        let z3 = cmul(z2, zz);
        let num = z3 - vec2<f32>(1.0, 0.0);
        let denom = z2 * 3.0;
        zz = zz - cdiv(num, denom);
    }
    let r1 = length(zz - vec2<f32>(1.0, 0.0));
    let r2 = length(zz - vec2<f32>(-0.5, 0.866));
    let r3 = length(zz - vec2<f32>(-0.5, -0.866));
    let minR = min(min(r1, r2), r3);
    var hue = 0.0;
    if (minR == r1) { hue = 0.0; }
    else if (minR == r2) { hue = 0.33; }
    else { hue = 0.66; }
    let sat = 1.0 - smoothstep(0.0, 0.3, minR);
    let v = 0.5 + 0.5 * sin(t + length(z));
    let c = v * sat;
    let h = hue * 6.0;
    let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if      (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else              { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}
fn sdfCardioid(p: vec2<f32>, t: f32) -> f32 {
    let a = atan2(p.y, p.x);
    let r = length(p);
    let cardioidR = 0.35 * (1.0 - cos(a + t * 0.2));
    return r - cardioidR;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(gid.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }

    let uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let aspect = resolution.x / max(resolution.y, 0.001);

    var z = (uv - 0.5) * 2.0;
    z.x *= aspect;
    z *= mix(1.0, 5.0, p1);

    let warp = fbmWarp(z * 2.0 + time * 0.2, time) * mix(0.05, 0.5, p4);
    z += warp;

    let mouse = u.zoom_config.yz;
    let w_real = (mouse.x - 0.5) * mix(1.0, 10.0, p3) + 1.0;
    let w_imag = (mouse.y - 0.5) * 6.0 + mids * sin(time) * 0.5;
    let w = vec2<f32>(w_real, w_imag);

    var result_z = complex_pow(z, w);

    // Julia orbit-trap overlay.
    let juliaC = vec2<f32>(0.355 + 0.05 * sin(time * 0.3), 0.355 + 0.05 * cos(time * 0.2));
    let orbit = juliaOrbit(z * 0.5, juliaC);

    let spiral = p2 * PI + bass * 0.3;
    let rotation = vec2<f32>(cos(spiral), sin(spiral));
    result_z = cmul(result_z, rotation);

    result_z.x /= aspect;
    var final_uv = result_z * mix(0.1, 1.0, p4) + 0.5;
    final_uv = fract(final_uv);
    let final_uv_c = clamp(final_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let ca = (final_uv - 0.5) * 0.02 * p4 * (1.0 + treble);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(final_uv_c + ca, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, final_uv_c, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(final_uv_c - ca * 0.7, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var col = vec3<f32>(r, g, b);

    // Newton fractal color overlay.
    let newton = newtonColor(z * mix(0.5, 2.0, p3), time);
    col = mix(col, newton, 0.25 * p4 * (0.6 + 0.4 * bass));

    // SDF cardioid mask adds dark organic silhouette.
    let card = sdfCardioid(uv - 0.5, time);
    let cardMask = 1.0 - smoothstep(0.0, 0.15, card);
    col = mix(col, col * 0.4, cardMask * 0.4 * p2);

    let uvDist = length(result_z);
    let fog = exp(-uvDist * 0.2 * (1.0 - p1)) * (0.6 + 0.4 * depth);
    col *= fog;

    // Orbit-trap glow.
    let orbitGlow = exp(-orbit.x * 4.0) * (0.5 + 0.5 * sin(time * 2.0));
    col += vec3<f32>(0.9, 0.7, 0.5) * orbitGlow * 0.2 * p4;

    col = acesToneMap(col * (1.1 + mids * 0.2));

    let distAlpha = clamp(1.0 - uvDist * 0.15, 0.0, 1.0);
    let alpha = clamp(distAlpha * (0.7 + bass * 0.3) + depth * 0.2 + orbit.y * 0.01, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
