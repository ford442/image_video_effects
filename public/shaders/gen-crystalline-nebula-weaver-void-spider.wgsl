// ----------------------------------------------------------------
// Crystalline Nebula-Weaver Void-Spider
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>
}

// ----------------------------------------------------------------
// Core SDF and Noise Functions
// ----------------------------------------------------------------

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    var pos = p;
    for (var i = 0; i < 5; i++) {
        // Simplified noise logic
        value += amplitude * sin(dot(pos, vec3<f32>(1.0, 1.5, 2.0)));
        pos *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// ----------------------------------------------------------------
// Spider Geometry
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
    let thread2 = length(fract(p_scaled * 2.0) - 0.5) - 0.01;
    return min(thread1, thread2) / web_complexity;
}

fn map(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> f32 {
    let gravity_distortion = u.zoom_params.y; // Gravity Distortion

    let distortedP = p + vec3<f32>(fbm(p + time * 0.5)) * gravity_distortion;
    let displacedP = distortedP - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);

    let spider = sdSpider(displacedP, audioReact);
    let web = sdWeb(displacedP) + fbm(p) * 0.1;
    return min(spider, web);
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
    let audioBass = u.ripples[0].x; // Using plasmaBuffer[0].x proxy
    let mouse = u.zoom_config.yz;

    // Ray setup
    let void_depth = u.zoom_params.w; // Void Depth
    let ro = vec3<f32>(0.0, 0.0, -5.0 * void_depth);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching loop
    var t = 0.0;
    var d = 0.0;
    let max_dist = 20.0 * void_depth;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p, time, audioBass, mouse);
        if (d < 0.001 || t > max_dist) { break; }
        t += d;
    }

    let plasma_intensity = u.zoom_params.z; // Plasma Intensity

    // Basic shading
    var col = vec3<f32>(0.0);
    if (t < max_dist) {
        col = vec3<f32>(0.2, 0.8, 1.0) * (1.0 - t / max_dist) * plasma_intensity;
        col += vec3<f32>(1.0, 0.2, 0.8) * audioBass * plasma_intensity;
    }

    textureStore(writeTexture, vec2<i32>(i32(global_id.x), i32(global_id.y)), vec4<f32>(col, 1.0));
}
