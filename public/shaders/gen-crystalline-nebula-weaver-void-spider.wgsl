// ----------------------------------------------------------------
// Crystalline Nebula-Weaver Void-Spider
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
    ripples: array<vec4<f32>, 50>
}

// ----------------------------------------------------------------
// Real hash-based value noise + fbm (replaces fake sin-dot field)
// ----------------------------------------------------------------

fn hash3(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.3183099 + vec3<f32>(0.1, 0.2, 0.3)) * 17.0;
    return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

fn vnoise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f); // smoothstep weights
    return mix(
        mix(mix(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), hash3(i + vec3<f32>(1.0, 0.0, 0.0)), s.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), hash3(i + vec3<f32>(1.0, 1.0, 0.0)), s.x), s.y),
        mix(mix(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), hash3(i + vec3<f32>(1.0, 0.0, 1.0)), s.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), hash3(i + vec3<f32>(1.0, 1.0, 1.0)), s.x), s.y),
        s.z);
}

// Rotation matrix between octaves decorrelates the crystalline lattice
const FBM_ROT = mat3x3<f32>(
    vec3<f32>( 0.00,  0.80,  0.60),
    vec3<f32>(-0.80,  0.36, -0.48),
    vec3<f32>(-0.60, -0.48,  0.64)
);

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) { // 4 octaves, rotated between layers
        value += amplitude * vnoise(pos);
        pos = FBM_ROT * pos * 2.03;
        amplitude *= 0.5;
    }
    return value;
}

// IQ cosine palette for crystalline hue grading
fn palette(t: f32) -> vec3<f32> {
    let ab = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return ab + ab * cos(6.28318 * (c * t + d));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// ----------------------------------------------------------------
// Spider Geometry (abdomen pulses with real bass)
// ----------------------------------------------------------------

fn sdSpider(p: vec3<f32>, audioReact: f32) -> f32 {
    // Abdomen and Cephalothorax
    let abdomen = length(p * vec3<f32>(1.0, 1.5, 1.0)) - (1.0 + audioReact * 0.2);
    let head = length(p - vec3<f32>(0.0, 0.0, 1.5)) - 0.7;
    var body = smin(abdomen, head, 0.5);

    // Legs (Simplified Domain Repetition)
    var pLeg = p;
    pLeg.x = abs(pLeg.x) - 1.5;
    let leg = length(max(abs(pLeg) - vec3<f32>(0.2, 2.0, 0.2), vec3<f32>(0.0))) - 0.1;

    return smin(body, leg, 0.2);
}

// ----------------------------------------------------------------
// Web and Environment Geometry
// ----------------------------------------------------------------

fn sdWeb(p: vec3<f32>) -> f32 {
    let web_complexity = u.zoom_params.x; // Web Complexity
    let p_scaled = p * web_complexity;
    let thread1 = length(p_scaled.xy) - 0.02;
    let thread2 = length(fract(p_scaled * 2.0) - vec3<f32>(0.5)) - 0.01;
    return min(thread1, thread2) / web_complexity;
}

fn displace(p: vec3<f32>, time: f32, mouse: vec2<f32>) -> vec3<f32> {
    let gravity_distortion = u.zoom_params.y; // Gravity Distortion
    let distortedP = p + vec3<f32>(fbm(p + vec3<f32>(time * 0.5))) * gravity_distortion;
    return distortedP - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);
}

fn map(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> f32 {
    let displacedP = displace(p, time, mouse);

    let spider = sdSpider(displacedP, audioReact);
    let web = sdWeb(displacedP) + fbm(p) * 0.1;
    return min(spider, web);
}

// Central-difference normal for crystalline shading
fn calcNormal(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.002, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audioReact, mouse) - map(p - e.xyy, time, audioReact, mouse),
        map(p + e.yxy, time, audioReact, mouse) - map(p - e.yxy, time, audioReact, mouse),
        map(p + e.yyx, time, audioReact, mouse) - map(p - e.yyx, time, audioReact, mouse)
    ));
}

// Hue-preserving clamp: scales rgb down by its peak instead of per-channel clip
fn hueClamp(col: vec3<f32>, limit: f32) -> vec3<f32> {
    let peak = max(col.r, max(col.g, col.b));
    return col * (limit / max(peak, limit));
}

// ACES filmic tonemapping (Narkowicz fit)
fn aces(x: vec3<f32>) -> vec3<f32> {
    let y = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    return clamp(y, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// Main Raymarching and Shading
// ----------------------------------------------------------------

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let id = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let uv = (id - 0.5 * vec2<f32>(f32(dimensions.x), f32(dimensions.y))) / f32(dimensions.y);

    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x;   // real bass drives the abdomen pulse
    let audioTreble = plasmaBuffer[0].z; // real treble drives web-thread glint
    let mouse = u.zoom_config.yz;

    // Ray setup (void_depth coupling keeps the spider in frame)
    let void_depth = u.zoom_params.w; // Void Depth
    let ro = vec3<f32>(0.0, 0.0, -5.0 * void_depth);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching loop with crystalline glow accumulation
    var t = 0.0;
    var d = 0.0;
    var glow = 0.0;
    let max_dist = 20.0 * void_depth;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p, time, audioBass, mouse);
        glow += exp(-max(d, 0.0) * 6.0) * 0.02;
        if (d < 0.001 || t > max_dist) { break; }
        t += d;
    }

    let plasma_intensity = u.zoom_params.z; // Plasma Intensity

    // Nebula background: true fbm density graded through the cosine palette
    let nebDens = fbm(vec3<f32>(uv * 2.5, time * 0.15));
    var col = palette(nebDens + uv.x * 0.15 + time * 0.02) * nebDens * nebDens * 0.35;

    var depthNorm = 1.0;
    if (t < max_dist) {
        let hitP = ro + rd * t;
        let n = calcNormal(hitP, time, audioBass, mouse);
        let lightDir = normalize(vec3<f32>(0.6, 0.8, -0.4));
        let diff = max(dot(n, lightDir), 0.0);
        let fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        depthNorm = clamp(t / max_dist, 0.0, 1.0);

        // Crystalline hue from the nebula field at the hit point
        let hueT = fbm(hitP * 0.7 + vec3<f32>(time * 0.1));
        var surf = palette(hueT) * (0.25 + 0.75 * diff) * (1.0 - depthNorm * 0.8);
        surf += palette(hueT + 0.35) * fres * 1.2;

        // Bass-lit plasma body
        surf += vec3<f32>(1.0, 0.2, 0.8) * audioBass * (0.4 + fres);

        // Treble glint: sparkle hugging the web threads near the hit
        let webD = sdWeb(displace(hitP, time, mouse));
        let sparkle = pow(vnoise(hitP * 24.0 + vec3<f32>(time * 3.0)), 8.0);
        surf += vec3<f32>(0.9, 0.95, 1.0) * sparkle * audioTreble * exp(-max(webD, 0.0) * 24.0) * 6.0;

        col += surf * plasma_intensity;
    }

    // Crystalline glow gathered along the march, tinted by palette + plasma
    col += palette(nebDens + 0.5) * glow * (0.6 + audioBass * 0.8) * (0.5 + plasma_intensity);

    // Tame the blowout: hue-preserving clamp at ~2.0, then ACES
    col = hueClamp(col, 2.0);
    col = aces(col);

    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthNorm, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(glow, audioBass, audioTreble, depthNorm));
}
