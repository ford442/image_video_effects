// ----------------------------------------------------------------
// Photonic Crystal-Brain
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Synapse Density, y=Pulse Speed, z=Crystal Distortion, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Mouse-Driven Focus (Gravity Well)
    let mx = (u.zoom_config.y * 2.0 - 1.0) * 5.0;
    let my = (u.zoom_config.z * 2.0 - 1.0) * -5.0;
    let mousePos = vec3<f32>(mx, my, p.z);

    let distToMouse = length(p - mousePos);
    let pull = exp(-distToMouse * 0.5) * 2.0;
    p = mix(p, mousePos, pull * 0.2); // Distort space towards mouse

    // Distortion from parameters
    let distortion = u.zoom_params.z;
    p.x += sin(p.y * 2.0 + u.config.x) * 0.1 * distortion;
    p.y += cos(p.x * 2.0 + u.config.x) * 0.1 * distortion;

    // Domain Repetition
    let spacing = 4.0 / u.zoom_params.x; // Synapse density affects spacing
    let id = floor(p / spacing);
    p = fract(p / spacing) * spacing - spacing * 0.5;

    // Organic crystal web structure
    let cylX = length(p.yz) - 0.1;
    let cylY = length(p.xz) - 0.1;
    let cylZ = length(p.xy) - 0.1;

    var d = smin(cylX, cylY, 0.3);
    d = smin(d, cylZ, 0.3);

    // Add central node (synapse)
    let sphere = length(p) - 0.3;
    d = smin(d, sphere, 0.4);

    // Displace surface
    let h = hash3(id);
    let disp = sin(p.x * 10.0) * cos(p.y * 10.0) * sin(p.z * 10.0) * 0.05 * distortion;
    d += disp;

    return vec2<f32>(d, h.x); // x = distance, y = material ID
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(id.xy);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(id.xy) - res * 0.5) / res.y;

    // Camera
    var ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 0.5); // Moving forward
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Add slight camera rotation
    let rotX = rotate2D(sin(u.config.x * 0.2) * 0.1);
    let rotY = rotate2D(cos(u.config.x * 0.3) * 0.1);

    let rdYZ = rotX * vec2<f32>(rd.y, rd.z);
    rd.y = rdYZ.x;
    rd.z = rdYZ.y;

    let rdXZ = rotY * vec2<f32>(rd.x, rd.z);
    rd.x = rdXZ.x;
    rd.z = rdXZ.y;

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var glow = vec3<f32>(0.0);

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let res_map = map(p);
        d = res_map.x;
        m = res_map.y;

        // Volumetric Glow Accumulation
        // Audio reactive bursts of plasma
        let audioPulse = u.config.y * 0.5;
        let pulseSpeed = u.zoom_params.y;
        let glowIntens = u.zoom_params.w;
        let pulse = sin(p.z * 2.0 - u.config.x * 5.0 * pulseSpeed) * 0.5 + 0.5;

        let colorA = vec3<f32>(0.1, 0.8, 1.0); // Cyan
        let colorB = vec3<f32>(1.0, 0.1, 0.8); // Magenta
        let glowColor = mix(colorA, colorB, m + sin(u.config.x));

        glow += glowColor * (0.01 / (d * d + 0.01)) * pulse * audioPulse * glowIntens;

        if (d < 0.001 || t > 20.0) { break; }
        t += d * 0.5; // smaller steps for smin/refraction
    }

    var col = vec3<f32>(0.0);

    if (t < 20.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting / Refraction simulation
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(reflect(rd, n), l), 0.0), 32.0);
        let fresnel = pow(1.0 + dot(rd, n), 4.0);

        col = vec3<f32>(0.05) + vec3<f32>(0.2) * diff;
        col += spec * vec3<f32>(1.0);
        col += fresnel * vec3<f32>(0.5, 0.8, 1.0) * 0.5;
    }

    col += glow;

    // Fog
    col = mix(col, vec3<f32>(0.0, 0.0, 0.05), 1.0 - exp(-t * 0.1));

    // Tonemapping
    col = col / (1.0 + col);

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
