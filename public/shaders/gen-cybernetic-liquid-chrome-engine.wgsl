// ----------------------------------------------------------------
// Cybernetic Liquid-Chrome Engine
// Category: generative
// ----------------------------------------------------------------
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Engine Speed, y=Chrome Reflectivity, z=Plasma Glow, w=Complexity
    ripples: array<vec4<f32>, 50>,
};

fn rotX(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotY(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let res = exp2(-k * a) + exp2(-k * b);
    return -log2(res) / k;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn map(p_in: vec3<f32>, global_glow: ptr<function, f32>) -> f32 {
    var p = p_in;
    let t = u.config.x * u.zoom_params.x;
    let audio = u.config.y;

    // Domain repetition
    let spacing = 8.0;
    p.x = (fract(p.x / spacing + 0.5) - 0.5) * spacing;
    p.z = (fract(p.z / spacing + 0.5) - 0.5) * spacing;

    // KIFS fold inner core
    var p_kifs = p;
    let complexity = i32(u.zoom_params.w);
    for(var i=0; i<complexity; i++) {
        p_kifs = abs(p_kifs) - vec3<f32>(0.5, 0.5, 0.5);
        let rx = rotX(0.5);
        let pYZ = rx * vec2<f32>(p_kifs.y, p_kifs.z);
        p_kifs.y = pYZ.x;
        p_kifs.z = pYZ.y;

        let ry = rotY(0.5);
        let pXZ = ry * vec2<f32>(p_kifs.x, p_kifs.z);
        p_kifs.x = pXZ.x;
        p_kifs.z = pXZ.y;
    }

    // Base structural elements
    let base_box = sdBox(p - vec3<f32>(0.0, -2.0, 0.0), vec3<f32>(2.0, 1.0, 2.0));

    // Piston
    let piston_h = 1.0 + sin(t + p_in.x * 0.2 + p_in.z * 0.2) * (1.0 + audio * 3.0);
    let piston = sdCappedCylinder(p - vec3<f32>(0.0, piston_h, 0.0), 2.0, 0.8);

    // Inner core micro-structures
    let core = sdBox(p_kifs, vec3<f32>(0.3, 0.3, 0.3));

    // Smooth union
    var d = smin(base_box, piston, 4.0);
    d = smin(d, core, 2.0);

    // Plasma glow based on core distance
    *global_glow += 0.01 / (0.01 + abs(core)) * u.zoom_params.z;

    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.001;
    var dummy: f32 = 0.0;
    var d1: f32 = 0.0; d1 = map(p + e.xyy, &dummy);
    var d2: f32 = 0.0; d2 = map(p + e.yyx, &dummy);
    var d3: f32 = 0.0; d3 = map(p + e.yxy, &dummy);
    var d4: f32 = 0.0; d4 = map(p + e.xxx, &dummy);

    return normalize(
        e.xyy * d1 +
        e.yyx * d2 +
        e.yxy * d3 +
        e.xxx * d4
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<f32>(f32(global_id.x), f32(global_id.y));
    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    var uv = (coords - 0.5 * res) / res.y;

    // Chromatic aberration at screen edges during high audio
    let audio = u.config.y;
    let distFromCenter = length(uv);
    uv *= 1.0 - (distFromCenter * audio * 0.1);

    // Camera
    var ro = vec3<f32>(0.0, 4.0, -10.0 + u.config.x * u.zoom_params.x * 2.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Mouse Interaction
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;

    let rx = rotX(-mouse.y * 1.5 + 0.5);
    let roYZ = rx * vec2<f32>(ro.y, ro.z);
    ro.y = roYZ.x;
    ro.z = roYZ.y;
    let rdYZ = rx * vec2<f32>(rd.y, rd.z);
    rd.y = rdYZ.x;
    rd.z = rdYZ.y;

    let ry = rotY(mouse.x * 1.5);
    let roXZ = ry * vec2<f32>(ro.x, ro.z);
    ro.x = roXZ.x;
    ro.z = roXZ.y;
    let rdXZ = ry * vec2<f32>(rd.x, rd.z);
    rd.x = rdXZ.x;
    rd.z = rdXZ.y;

    // Raymarching
    var d = 0.0;
    var t = 0.0;
    var global_glow = 0.0;

    for (var i = 0; i < 100; i++) {
        var p = ro + rd * t;
        d = map(p, &global_glow);
        if (d < 0.001 || t > 80.0) {
            break;
        }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var p = ro + rd * t;

    if (t < 80.0) {
        var n = calcNormal(p);

        let viewDir = normalize(ro - p);
        let refDir = reflect(-viewDir, n);

        // Pseudo-environment map using refDir
        var envCol = vec3<f32>(0.5, 0.7, 1.0) * max(0.0, refDir.y) + vec3<f32>(0.2, 0.2, 0.2) * max(0.0, -refDir.y);
        // Add some audio-reactive color to the reflection
        envCol += vec3<f32>(0.8, 0.2, 1.0) * audio * 0.5 * max(0.0, refDir.x);

        let chrome_reflectivity = u.zoom_params.y;
        col = mix(vec3<f32>(0.1), envCol, chrome_reflectivity);

        // Diffuse lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 32.0);
        col = col * (diff * 0.5 + 0.5) + vec3<f32>(spec) * chrome_reflectivity;
    }

    // Iridescent plasma glow with chromatic dispersion
    let glowCol = vec3<f32>(
        sin(u.config.x * 2.0 + p.z * 0.5) * 0.5 + 0.5,
        sin(u.config.x * 2.3 + p.y * 0.5) * 0.5 + 0.5,
        sin(u.config.x * 2.7 + p.x * 0.5) * 0.5 + 0.5
    );
    col += glowCol * global_glow * 0.05 * (1.0 + audio * 2.0);

    // Fog
    col = mix(col, vec3<f32>(0.02, 0.02, 0.05), 1.0 - exp(-0.01 * t));

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}