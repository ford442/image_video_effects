// ═══════════════════════════════════════════════════════════════════
//  Luminous-Fluid Chladni-Resonator
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: sand grains bounced off antinodes and packed onto nodal lines; Faraday subharmonic surface ripples above a bass drive threshold
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Mode N, .y = Mode M, .z = Fluidity, .w = Glow Intensity
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const PHI: f32 = 1.61803398874989484820;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f * f * (vec2<f32>(3.0) - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var q = p;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < 5; i++) { v += a * noise(q); q = rot * q * 2.0 + vec2<f32>(100.0); a *= 0.5; }
    return v;
}
fn curl2D(p: vec2<f32>) -> vec2<f32> {
    let e = 0.01; let nx = fbm(p + vec2<f32>(0.0, e)) - fbm(p - vec2<f32>(0.0, e)); let ny = fbm(p + vec2<f32>(e, 0.0)) - fbm(p - vec2<f32>(e, 0.0));
    return vec2<f32>(nx, -ny) / (2.0 * e);
}
fn voronoiRidge(p: vec2<f32>) -> f32 {
    let ip = floor(p); let fp = fract(p); var F1 = 1e9; var F2 = 1e9;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let n = vec2<f32>(f32(i), f32(j));
            let d = length(n + vec2<f32>(hash21(ip + n), hash21(ip + n + 17.0)) - fp);
            let updateF1 = step(d, F1);
            let oldF1 = F1;
            F1 = mix(F1, d, updateF1);
            F2 = mix(F2, oldF1, updateF1);
            let updateF2 = step(d, F2) * (1.0 - updateF1);
            F2 = mix(F2, d, updateF2);
        }
    }
    return F2 - F1;
}
fn chladni_multi(uv: vec2<f32>, n: f32, m: f32, t: f32) -> f32 {
    let a1 = sin(n * PI * uv.x) * sin(m * PI * uv.y); let a2 = sin(m * PI * uv.x) * sin(n * PI * uv.y);
    let b1 = sin((n + 1.0) * PI * uv.x) * sin((m + 1.0) * PI * uv.y); let b2 = sin((m + 1.0) * PI * uv.x) * sin((n + 1.0) * PI * uv.y);
    return cos(t) * a1 + sin(t) * a2 + (cos(t * PHI) * b1 + sin(t * PHI) * b2) * 0.4;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) * 0.01;
    var r = select(clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0), 1.0, t <= 66.0);
    var g = select(clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0), clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0), t <= 66.0);
    var b = select(select(clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0), 0.0, t <= 19.0), 1.0, t >= 66.0);
    return vec3<f32>(r, g, b);
}
fn srgb2oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = pow(vec3<f32>(dot(c,vec3<f32>(0.4122,0.5363,0.0514)),dot(c,vec3<f32>(0.2119,0.6807,0.1074)),dot(c,vec3<f32>(0.0883,0.2817,0.6300))),vec3<f32>(1.0/3.0));
    return vec3<f32>(dot(lms,vec3<f32>(0.2105,0.7936,-0.0041)),dot(lms,vec3<f32>(1.9780,-2.4286,0.4506)),dot(lms,vec3<f32>(0.0259,0.7828,-0.8087)));
}
fn oklab2srgb(c: vec3<f32>) -> vec3<f32> {
    let lms = pow(c.x+c.y*vec3<f32>(0.3963,-0.1056,-0.0895)+c.z*vec3<f32>(0.2158,-0.0639,-1.2915),vec3<f32>(3.0));
    return vec3<f32>(dot(lms,vec3<f32>(4.0767,-1.2684,-0.0042)),dot(lms,vec3<f32>(-3.3077,2.6098,-0.7034)),dot(lms,vec3<f32>(0.2310,-0.3413,1.7076)));
}
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab2srgb(mix(srgb2oklab(a), srgb2oklab(b), t));
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Sand on a Chladni plate: grains are thrown off vibrating antinodes and settle
// where displacement vanishes. Returns grain coverage at this pixel.
fn sandGrains(p: vec2<f32>, amp: f32, t: f32, agitation: f32) -> f32 {
    let cellScale = 180.0;
    let cell = floor(p * cellScale);
    let rnd = hash21(cell);
    let rnd2 = hash21(cell + vec2<f32>(31.7, 5.3));
    // Grains survive where the plate is still; antinode grains are airborne (sparse flicker)
    let nodal = exp(-amp * amp * 90.0);
    let packed = step(1.0 - nodal * 0.85, rnd);
    let bounce = step(0.985 - agitation * 0.01, rnd2) * step(0.5, fract(t * 6.0 + rnd * 7.0)) * (1.0 - nodal);
    let grainShape = smoothstep(0.5, 0.15, length(fract(p * cellScale) - 0.5));
    return clamp((packed + bounce * 0.6) * grainShape, 0.0, 1.0);
}

// Faraday instability: a vertically driven liquid layer answers at HALF the drive
// frequency with a square standing-wave lattice once the drive exceeds threshold.
fn faradayRipples(p: vec2<f32>, driveT: f32, k: f32) -> f32 {
    let sub = cos(driveT * 0.5);
    let lattice = cos(k * p.x) + cos(k * p.y);
    return sub * lattice * 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let res = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(coord) / res;
    let t = u.config.x * 0.5;
    let aspect = res.x / max(res.y, 1.0);

    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let param_n = u.zoom_params.x;
    let param_m = u.zoom_params.y;
    let param_fluid = u.zoom_params.z;
    let param_glow = u.zoom_params.w;

    let velocity = curl2D(uv * 5.0 + vec2<f32>(t * 0.3));
    let uv_dist = uv + velocity * param_fluid * 0.05 * (1.0 + bass * 0.5 + mids * 0.3);
    let n = param_n + bass * 2.0 * sin(t);
    let m = param_m + bass * 2.0 * cos(t * PHI);
    var c_val = chladni_multi(uv_dist * 2.0 - vec2<f32>(1.0), n, m, t * 2.0);

    // Click ripples: a tap on the plate injects a decaying circular flexural wave
    let rippleCount = min(u32(u.config.y), 50u);
    for (var k: u32 = 0u; k < rippleCount; k = k + 1u) {
        let rp = u.ripples[k];
        let age = u.config.x - rp.z;
        if (age < 0.0 || age > 3.0) { continue; }
        var dv = uv - rp.xy;
        dv.x = dv.x * aspect;
        let dr = length(dv);
        let front = age * 0.35;
        c_val += sin((dr - front) * 60.0) * exp(-abs(dr - front) * 14.0) * (1.0 - age / 3.0) * 0.6;
    }

    // Faraday subharmonic ripples ride the antinodes once bass drive crosses threshold
    let faradayGain = smoothstep(0.35, 0.8, bass) * (0.4 + param_fluid);
    let faraday = faradayRipples((uv_dist - 0.5) * vec2<f32>(aspect, 1.0), t * 24.0, 70.0 + (n + m) * 3.0);
    let antinode = smoothstep(0.2, 0.8, abs(c_val));
    c_val += faraday * faradayGain * antinode * 0.25;

    let ridge = 1.0 - smoothstep(0.0, 0.18, voronoiRidge(uv * 8.0 + velocity * 0.2));
    let mouse_uv = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let d_mouse = distance(uv, mouse_uv);
    // A held finger presses harder on the plate: wider damped zone
    let pressR = select(0.2, 0.32, u.zoom_config.w > 0.5);
    let damp = smoothstep(0.0, pressR, d_mouse);
    let depthAttn = exp(-d_mouse * 1.5);
    let final_val = abs(c_val) * damp + ridge * 0.35 * depthAttn;

    // Temporal settle from exact previous frame; alpha in A is high on nodal lines,
    // so invert it back into a displacement-like field.
    let prevCoord = clamp(coord, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    let priorA = textureLoad(dataTextureC, prevCoord, 0);
    let prior = (1.0 - priorA.a) * 0.3;
    let settled = mix(prior, final_val, 0.35);
    let intensity = smoothstep(0.18, 0.0, settled) * param_glow * (1.0 + bass * 0.5 + treble * 0.3);

    // Sand accumulation on nodal lines
    let sand = sandGrains(uv * vec2<f32>(aspect, 1.0), abs(c_val) * damp, u.config.x, treble);

    let warm = blackbodyRGB(3500.0 + bass * 3000.0 + sin(t * 0.7) * 1000.0) * intensity * 3.0;
    let cool = blackbodyRGB(8500.0 + cos(t * 0.4) * 2000.0) * (intensity * 0.6 + ridge * 0.8);
    var hdr = mixOkLab(warm, cool, ridge * 0.5 + 0.25) * (1.0 + intensity);
    let sandCol = vec3<f32>(1.0, 0.86, 0.6) * (0.35 + intensity * 0.5) * min(param_glow, 2.5);
    hdr = hdr + sandCol * sand * 0.8;
    hdr = hdr + vec3<f32>(0.4, 0.8, 1.0) * max(faraday, 0.0) * faradayGain * antinode * 0.5 * param_glow;
    let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(intensity * 0.7 + luma * 0.25 + ridge * 0.15 + sand * 0.2, 0.0, 1.0);
    let mapped = aces(hdr) + vec3<f32>((ign(vec2<f32>(coord)) - 0.5) / 255.0);
    let gamma = pow(max(mapped, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
    let finalColor = vec4<f32>(acesToneMap((gamma * alpha) * 1.1), alpha);

    // Depth: plate displacement (nodal lines sit at mid height), grains raise it slightly
    let depth = clamp(0.5 + c_val * 0.25 * damp + sand * 0.05, 0.0, 1.0);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
