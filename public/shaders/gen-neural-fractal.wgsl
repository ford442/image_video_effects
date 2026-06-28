// ═══════════════════════════════════════════════════════════════════════════════
//  Neural Fractal - Visualist Upgrade
//  Category: generative
//  Features: OkLab color mixing, Blackbody temperature, Cosine palettes,
//            Fresnel rim lighting, HDR tone mapping, neural activation fractals
//  Upgraded: 2026-06-28
// ═══════════════════════════════════════════════════════════════════════════════
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

// --- Color Science: OkLab ---
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(2.2));
}
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(1.0 / 2.2));
}
fn linear_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        vec3<f32>(0.8189330101, 0.3618667424, -0.1288597137),
        vec3<f32>(0.0329845436, 0.9293118715, 0.0361456387),
        vec3<f32>(0.0482003018, 0.2643662691, 0.6338517070)
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0/3.0));
    return mat3x3<f32>(
        vec3<f32>(0.2104542553, 1.9779984951, 0.0259040371),
        vec3<f32>(0.7936177850, -2.4285922050, 0.7827717662),
        vec3<f32>(-0.0040720468, 0.4505937099, -0.8086757660)
    ) * lms_;
}
fn oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.3963377774, -0.1055613458, -0.0894841775),
        vec3<f32>(0.2158037573, -0.0638541728, -1.2914855480)
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        vec3<f32>(1.2270138510, -0.5577992887, 0.2812561490),
        vec3<f32>(-0.0405801784, 1.1122568696, -0.0716766787),
        vec3<f32>(-0.0763812845, -0.4214819784, 1.5861632204)
    ) * lms;
}
fn oklab_mix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear(mix(linear_to_oklab(a), linear_to_oklab(b), t));
}

// --- Blackbody Color Temperature ---
fn blackbody(t: f32) -> vec3<f32> {
    var col = vec3<f32>(1.0);
    col.y = 0.3900815787690196 * log(t) - 0.6318414437886275;
    col.z = 0.5432067891101961 * log(t) - 1.1964741063266880;
    return clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Cosine Palette (Inigo Quilez) ---
fn cosinePalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// --- HDR Tone Mapping ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(2.51); let b = vec3<f32>(0.03);
    let c = vec3<f32>(2.43); let d = vec3<f32>(0.59);
    let e = vec3<f32>(0.14);
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Fresnel Rim ---
fn fresnelRim(n: vec3<f32>, v: vec3<f32>, power: f32) -> f32 {
    return pow(1.0 + dot(n, v), power);
}

// Activation functions
fn sigmoid(x: f32) -> f32 { return 1.0 / (1.0 + exp(-x)); }
fn tanh_activation(x: f32) -> f32 { return tanh(x); }
fn relu(x: f32) -> f32 { return max(x, 0.0); }
fn swish(x: f32) -> f32 { return x * sigmoid(x); }

fn neuralLayer(z: vec2<f32>, c: vec2<f32>, activation: i32) -> vec2<f32> {
    var result: vec2<f32>;
    if (activation == 0) {
        result = vec2<f32>(sigmoid(z.x * z.x - z.y * z.y + c.x), sigmoid(2.0 * z.x * z.y + c.y));
    } else if (activation == 1) {
        result = vec2<f32>(tanh_activation(z.x * z.x - z.y * z.y + c.x), tanh_activation(2.0 * z.x * z.y + c.y));
    } else if (activation == 2) {
        result = vec2<f32>(swish(z.x * z.x - z.y * z.y + c.x), swish(2.0 * z.x * z.y + c.y));
    } else {
        result = vec2<f32>(sigmoid(z.x * z.x - z.y * z.y + c.x), tanh_activation(2.0 * z.x * z.y + c.y));
    }
    return result;
}

fn domainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
    let warp1 = vec2<f32>(sin(p.x * 3.0 + time * 0.5) * 0.1, cos(p.y * 3.0 + time * 0.3) * 0.1);
    let warp2 = vec2<f32>(sin(p.y * 5.0 - time * 0.4) * 0.05, cos(p.x * 5.0 + time * 0.6) * 0.05);
    return p + warp1 + warp2;
}

// Multi-trap coloring for richer detail
fn multiTrapColor(z: vec2<f32>, trap1: f32, trap2: f32, time: f32, bass: f32) -> vec3<f32> {
    let t1 = 1.0 - exp(-trap1 * 3.0);
    let t2 = 1.0 - exp(-trap2 * 2.0);
    let cp1 = cosinePalette(t1 + time * 0.05, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0,0.8,0.6), vec3<f32>(0.0,0.33,0.67));
    let cp2 = cosinePalette(t2 + time * 0.07, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(0.8,1.0,1.0), vec3<f32>(0.2,0.5,0.8));
    let bb1 = blackbody(mix(2000.0, 8000.0, t1));
    let bb2 = blackbody(mix(4000.0, 12000.0, t2));
    let col1 = oklab_mix(cp1, bb1, 0.4 + bass * 0.2);
    let col2 = oklab_mix(cp2, bb2, 0.3 + bass * 0.1);
    return oklab_mix(col1, col2, 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    let bass = plasmaBuffer[0].x;

    // Mouse Y-flip: screen-top = +Y/up
    let mouseX = u.zoom_config.y;
    let mouseY = 1.0 - u.zoom_config.z;
    let mouseDist = length(uv - vec2<f32>(mouseX, mouseY));
    let mouseInfluence = smoothstep(0.5, 0.0, mouseDist);

    let zoom = mix(0.5, 3.0, u.zoom_params.x);
    let colorSpeed = mix(0.1, 1.0, u.zoom_params.y);
    let iterations = i32(mix(30.0, 100.0, u.zoom_params.z));
    let mutation = mix(0.0, 0.5, u.zoom_params.w);
    let aspect = resolution.x / resolution.y;
    let zoomAnim = zoom * (1.0 + 0.2 * sin(t * 0.1));
    let scale = 2.5 / zoomAnim;
    let center = vec2<f32>(sin(t * 0.05) * 0.1, cos(t * 0.07) * 0.1);
    var p = (uv - 0.5) * vec2<f32>(scale * aspect, scale) + center;
    p = domainWarp(p, t);
    // Mouse warps the domain too
    p += (uv - vec2<f32>(mouseX, mouseY)) * mouseInfluence * 0.3;

    let juliaC = vec2<f32>(sin(t * 0.1) * 0.5 + mutation * sin(p.x * 10.0), cos(t * 0.08) * 0.5 + mutation * cos(p.y * 10.0));
    var z = p;
    var iter = 0;
    var trap1 = 1000.0;
    var trap2 = 1000.0;
    var sumZ = vec2<f32>(0.0);
    var minZ = vec2<f32>(1000.0);
    for (iter = 0; iter < iterations; iter++) {
        let activationType = (iter / 10) % 4;
        z = neuralLayer(z, juliaC, activationType);
        let d1 = length(z - vec2<f32>(0.5, 0.0));
        let d2 = length(z - vec2<f32>(-0.5, 0.0));
        trap1 = min(trap1, d1);
        trap2 = min(trap2, d2);
        minZ = min(minZ, abs(z));
        sumZ = sumZ + z;
        if (length(z) > 10.0) { break; }
    }
    let iterRatio = f32(iter) / f32(iterations);

    // Multi-trap coloring with OkLab and Blackbody
    var col = multiTrapColor(z, trap1, trap2, t, bass);

    // Glow from orbit traps with Fresnel-like rim
    let glow1 = exp(-trap1 * 5.0) * 0.5;
    let glow2 = exp(-trap2 * 4.0) * 0.4;
    let rim = fresnelRim(normalize(vec3<f32>(uv - 0.5, 0.1)), vec3<f32>(0.0, 0.0, 1.0), 3.0);
    col += oklab_mix(vec3<f32>(0.4, 0.2, 0.6), blackbody(10000.0), 0.5) * (glow1 + glow2 * 0.5) * (1.0 + rim * 0.3);

    // Structure from sum with cosine palette modulation
    let structure = length(sumZ) * 0.01;
    let structCol = cosinePalette(structure + t * 0.02, vec3<f32>(0.5), vec3<f32>(0.3), vec3<f32>(1.0,0.9,0.7), vec3<f32>(0.1,0.4,0.6));
    col = mix(col, col * (1.0 + structure) + structCol * 0.1, 0.3);

    // Add detail from minZ
    let detail = length(minZ) * 2.0;
    col += oklab_mix(blackbody(3000.0), blackbody(7000.0), detail) * detail * 0.1;

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.8;
    col *= vignette;

    // HDR tone mapping with audio boost
    col = acesToneMap(col * (1.0 + bass * 0.3));

    let _luma_q = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let _alpha_q = clamp(_luma_q * 0.7 + 0.2, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, _alpha_q));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
