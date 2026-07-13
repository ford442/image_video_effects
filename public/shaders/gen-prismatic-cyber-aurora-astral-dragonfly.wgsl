// ----------------------------------------------------------------
// Prismatic Cyber-Aurora Astral-Dragonfly (upgraded)
// Category: generative
// ----------------------------------------------------------------
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};
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

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + 7.13));
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

fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + 0.3 * q;
}

// Smooth Voronoi/Worley layer returning F1 distance and cell id
fn voronoi(p: vec2<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var md = 8.0;
    var cell = 0.0;
    for (var j = -1; j <= 1; j = j + 1) {
        for (var i = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash22(n + g);
            let r = g + o - f;
            let d = dot(r, r);
            let closer = d < md;
            md = select(md, d, closer);
            cell = select(cell, hash21(n + g), closer);
        }
    }
    return vec2<f32>(sqrt(md), cell);
}

// Curl noise from the gradient of FBM
fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.01;
    let n0 = fbm(p + vec2<f32>(e, 0.0) + t, 4);
    let n1 = fbm(p - vec2<f32>(e, 0.0) + t, 4);
    let n2 = fbm(p + vec2<f32>(0.0, e) + t, 4);
    let n3 = fbm(p - vec2<f32>(0.0, e) + t, 4);
    return vec2<f32>(n3 - n2, n0 - n1) / (2.0 * e);
}

// Layered Worley/Voronoi sparkle field
fn worleyLayers(p: vec2<f32>, t: f32) -> f32 {
    var w = 0.0;
    var a = 0.5;
    var f = 1.0;
    var rotAcc = rot(t * 0.1);
    for (var i = 0; i < 4; i = i + 1) {
        let v = voronoi(rotAcc * p * f + vec2<f32>(t * 0.05 * f32(i + 1)));
        w += a * (1.0 - smoothstep(0.0, 0.25, v.x));
        f *= 2.0;
        a *= 0.5;
        rotAcc = rot(0.4 + t * 0.05);
    }
    return w;
}

fn sdEllipse(p: vec2<f32>, ab: vec2<f32>) -> f32 {
    let k0 = length(p / ab);
    let k1 = length(p / (ab * ab));
    return k0 * (k0 - 1.0) / (k1 + 0.0001);
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// SDF for the biomechanical dragonfly: body, four mirrored wings and tail
fn sdDragonfly(p: vec2<f32>, wingspan: f32, flap1: f32, flap2: f32) -> f32 {
    let body = sdEllipse(vec2<f32>(p.x * 5.0, p.y), vec2<f32>(0.12, 0.55));
    let head = length(p - vec2<f32>(0.0, 0.62)) - 0.09;

    let w1uv = rot(flap1) * vec2<f32>(abs(p.x) - 0.08, p.y - 0.12);
    let w1 = sdEllipse(vec2<f32>(w1uv.x * 0.45 / wingspan, w1uv.y * 3.0), vec2<f32>(0.55, 0.12));

    let w2uv = rot(flap2 + 0.4) * vec2<f32>(abs(p.x) - 0.08, p.y + 0.12);
    let w2 = sdEllipse(vec2<f32>(w2uv.x * 0.4 / wingspan, w2uv.y * 3.0), vec2<f32>(0.45, 0.1));

    let tail = sdSegment(p, vec2<f32>(0.0, -0.55), vec2<f32>(0.0, -1.25)) - 0.03;
    return min(min(min(body, head), w1), min(w2, tail));
}

// Strange-attractor crystal particles
fn attractorParticles(p: vec2<f32>, t: f32, audio: f32) -> f32 {
    var z = p * 3.0;
    var density = 0.0;
    let a = 1.7 + 0.2 * sin(t * 0.15);
    let b = 0.6 + audio * 0.3;
    for (var i = 0; i < 18; i = i + 1) {
        let nx = sin(a * z.y) - cos(b * z.x);
        let ny = sin(a * z.x) + cos(b * z.y);
        z = vec2<f32>(nx, ny);
        density += exp(-length(z - p) * 8.0);
    }
    return clamp(density * 0.15, 0.0, 1.0);
}

// Radial chromatic aberration for shattered-crystal optics
fn chromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let d = uv - vec2<f32>(0.5);
    let angle = atan2(d.y, d.x) + time * 0.3;
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(color.r * (1.0 + shift.x), color.g, color.b * (1.0 - shift.y));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let res = vec2<f32>(dims);
    let uv01 = vec2<f32>(id.xy) / res;
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / min(res.x, res.y);

    let time = u.config.x;
    let audio = u.config.y;
    let mouse = u.zoom_config.yz;
    let wingspan = clamp(u.zoom_params.x, 0.05, 0.5);
    let plasma = u.zoom_params.y;

    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
    let inDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv01, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);

    // Domain-warped aurora background with curl advection
    let warp = domainWarp(uv * 2.5 + vec2<f32>(0.0, time * 0.04), time * 0.06);
    let curl = curlNoise(uv * 3.0, time * 0.1);
    let bgNoise = fbm(warp + curl * 0.15, 5);
    let worley = worleyLayers(uv * 4.0, time);
    let aurora = vec3<f32>(0.1, 0.35, 0.5) * bgNoise * (1.0 + audio * 1.5);
    var bgColor = aurora + vec3<f32>(0.05, 0.0, 0.12) * (1.0 - bgNoise);
    bgColor += vec3<f32>(0.6, 0.9, 1.0) * worley * audio;

    // Dragonfly SDF
    let flapSpeed = time * 18.0 + audio * 40.0;
    let flap1 = sin(flapSpeed) * 0.35 + 0.45;
    let flap2 = sin(flapSpeed + 1.8) * 0.3 + 0.35;
    var p = uv;
    p = rot(mouse.x * 1.5) * p;
    let d = sdDragonfly(p, wingspan, flap1, flap2);
    let edge = abs(d);
    let density = smoothstep(0.08, 0.0, d);
    let shell = exp(-edge * 14.0);

    // Voronoi wing veins (branchless selection via smoothstep)
    let v = voronoi(p * 14.0 + vec2<f32>(time * 0.2));
    let vein = smoothstep(0.06, 0.02, v.x) * (1.0 - smoothstep(0.0, 0.2, p.y));

    // Iridescent palette + orbit trap around body axis
    let orbit = abs(p.x) * 8.0 + edge * 4.0;
    let irid = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(0.0, 0.33, 0.67) * PI * 2.0 + time * 1.2 + orbit - v.y * 4.0);
    var bodyColor = mix(irid, vec3<f32>(0.05, 0.1, 0.15), vein * 0.8);

    // Plasma core glow
    let core = smoothstep(0.15, 0.0, length(p - vec2<f32>(0.0, 0.2))) * plasma * 4.0;
    bodyColor += vec3<f32>(0.2, 0.9, 0.6) * core * (1.0 + audio * 2.0);

    // Strange-attractor crystal particles
    let particles = attractorParticles(uv, time, audio);
    let particleGlow = vec3<f32>(1.0, 0.85, 0.4) * particles * audio;

    // Branchless mouse halo
    let mouseDist = length(uv01 - mouse);
    let mouseGlow = exp(-mouseDist * 18.0) * (0.25 + audio);

    // Composite with temporal feedback from dataTextureC
    var color = mix(video.rgb, bodyColor, clamp(density + shell * 0.6, 0.0, 1.0));
    color = mix(color, bgColor, 0.45 * (1.0 - density));
    color += particleGlow;
    color += vec3<f32>(0.4, 0.8, 1.0) * mouseGlow;
    color = mix(color, prev.rgb, 0.06 + audio * 0.04);

    // Post-processing: chromatic aberration and gentle tone compression
    color = chromaticShift(color, uv01, audio * 0.025, time);
    color = color / (color + vec3<f32>(1.0));

    // Alpha tied to density, shell and particle emission
    let alpha = clamp(density + shell * 0.35 + particles * 0.3, 0.0, 1.0);
    let depth = mix(inDepth, 0.15 + density * 0.65, clamp(density + shell * 0.6, 0.0, 1.0));

    textureStore(writeTexture, id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(d, v.x, bgNoise, alpha));
}
