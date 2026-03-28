// ----------------------------------------------------------------
// Neural Bioluminescence Matrix
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Node Density, y=Pulse Speed, z=Audio Reactivity, w=Bio-Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// --- Core SDFs & Noise ---
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let res = exp2(-k * a) + exp2(-k * b);
    return -log2(res) / k;
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (3.0 - 2.0 * f);
    let res = mix(mix(mix(hash33(p + vec3<f32>(0.0,0.0,0.0)).x, hash33(p + vec3<f32>(1.0,0.0,0.0)).x, f2.x),
                      mix(hash33(p + vec3<f32>(0.0,1.0,0.0)).x, hash33(p + vec3<f32>(1.0,1.0,0.0)).x, f2.x), f2.y),
                  mix(mix(hash33(p + vec3<f32>(0.0,0.0,1.0)).x, hash33(p + vec3<f32>(1.0,0.0,1.0)).x, f2.x),
                      mix(hash33(p + vec3<f32>(0.0,1.0,1.0)).x, hash33(p + vec3<f32>(1.0,1.0,1.0)).x, f2.x), f2.y), f2.z);
    return res;
}

fn fbm(p_in: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p_in;
    for (var i = 0; i < 4; i++) {
        f += amp * noise(pos);
        pos *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn mod_float(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Magnetic mouse repulsion
    let mouseX = (u.zoom_config.y / u.config.z) * 2.0 - 1.0;
    let mouseY = -(u.zoom_config.z / u.config.w) * 2.0 + 1.0;
    let mousePos = vec3<f32>(mouseX * 5.0, mouseY * 5.0, p.z);
    let distToMouse = length(p.xy - mousePos.xy);
    let repulsion = 2.0 * exp(-distToMouse * 1.5);
    p = p + normalize(vec3<f32>(p.xy - mousePos.xy, 0.0001)) * repulsion;

    // Organic displacement using FBM
    p += (vec3<f32>(fbm(p), fbm(p + 10.0), fbm(p + 20.0)) - 0.5) * 1.5;

    let spacing = 4.0 / u.zoom_params.x; // Node Density

    var q = p;
    q.x = mod_float(q.x + spacing * 0.5, spacing) - spacing * 0.5;
    q.y = mod_float(q.y + spacing * 0.5, spacing) - spacing * 0.5;
    q.z = mod_float(q.z + spacing * 0.5, spacing) - spacing * 0.5;

    // A few connecting capsules
    let r = 0.15;
    let d1 = sdCapsule(q, vec3<f32>(-spacing*0.5, 0.0, 0.0), vec3<f32>(spacing*0.5, 0.0, 0.0), r);
    let d2 = sdCapsule(q, vec3<f32>(0.0, -spacing*0.5, 0.0), vec3<f32>(0.0, spacing*0.5, 0.0), r);
    let d3 = sdCapsule(q, vec3<f32>(0.0, 0.0, -spacing*0.5), vec3<f32>(0.0, 0.0, spacing*0.5), r);

    var d = smin(d1, d2, 12.0);
    d = smin(d, d3, 12.0);

    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

// --- Main Render Loop ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = textureDimensions(writeTexture);
    if (id.x >= texSize.x || id.y >= texSize.y) { return; }

    let fragCoord = vec2<f32>(id.xy);
    var uv = (fragCoord - 0.5 * vec2<f32>(texSize)) / f32(texSize.y);

    let time = u.config.x;
    let audioPulse = u.config.y * u.zoom_params.z; // Audio Reactivity

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, time * 2.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slow camera rotation
    let rd_xy = rot(time * 0.1) * vec2<f32>(rd.x, rd.y);
    rd.x = rd_xy.x;
    rd.y = rd_xy.y;

    let rd_xz = rot(sin(time * 0.05) * 0.2) * vec2<f32>(rd.x, rd.z);
    rd.x = rd_xz.x;
    rd.z = rd_xz.y;

    // Raymarching logic
    var t = 0.0;
    var d = 0.0;
    var p = ro;
    var glow = 0.0;

    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        d = map(p);

        let pulseWave = sin(dot(p, vec3<f32>(0.5, 0.5, 0.5)) - time * u.zoom_params.y * 3.0) * 0.5 + 0.5; // Pulse Speed
        let pulseIntensity = pow(pulseWave, 4.0) * (1.0 + audioPulse * 2.0);

        glow += (0.02 / (0.01 + abs(d))) * pulseIntensity * u.zoom_params.w; // Bio-Glow Intensity

        if (d < 0.01 || t > 50.0) { break; }
        t += d * 0.7;
    }

    var color = vec3<f32>(0.01, 0.01, 0.02); // Deep void background

    if (t < 50.0) {
        let n = calcNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let ao = clamp(map(p + n * 0.5) * 2.0, 0.0, 1.0);

        let baseCol = vec3<f32>(0.05, 0.1, 0.15);
        color = baseCol * diff * ao;

        let sss = max(0.0, map(p + rd * 0.5));
        color += vec3<f32>(0.1, 0.3, 0.4) * sss * 0.5;
    }

    let glowCol = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.0, 0.8), sin(p.z * 0.5 + time) * 0.5 + 0.5);
    color += glowCol * glow * 0.05 * exp(-t * 0.05);

    color = mix(color, vec3<f32>(0.01, 0.01, 0.02), 1.0 - exp(-t * 0.02));

    textureStore(writeTexture, id.xy, vec4<f32>(color, 1.0));
}