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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=Mouse Influence
    ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}


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
    let objectScale = mix(0.68, 1.5, clamp(u.zoom_params.z, 0.0, 1.0));
    var p = p_in / objectScale;
    let t = u.config.x * mix(0.45, 2.8, clamp(u.zoom_params.y, 0.0, 1.0));
    let audio = plasmaBuffer[0].x;

    // Domain repetition
    let spacing = 8.0;
    p.x = (fract(p.x / spacing + 0.5) - 0.5) * spacing;
    p.z = (fract(p.z / spacing + 0.5) - 0.5) * spacing;

    // KIFS fold inner core
    var p_kifs = p;
    let complexity = 4;
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
    let surge = sin(t * 2.4 + p_in.x * 0.24 + p_in.z * 0.19);
    let piston_h = 1.0 + surge * (0.8 + audio * 2.8);
    let piston = sdCappedCylinder(p - vec3<f32>(0.0, piston_h, 0.0), 2.0, 0.8);

    // Inner core micro-structures
    let core = sdBox(p_kifs, vec3<f32>(0.3, 0.3, 0.3));

    // Smooth union
    var d = smin(base_box, piston, 4.0);
    d = smin(d, core, 2.0);

    // Plasma glow based on core distance
    *global_glow += 0.008 / (0.012 + abs(core)) * (0.45 + u.zoom_params.x * 1.4);

    return d * objectScale;
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

    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speed = clamp(u.zoom_params.y, 0.0, 1.0);
    let mouseInfluence = clamp(u.zoom_params.w, 0.0, 1.0);

    // Chromatic aberration at screen edges during high audio
    let audio = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let distFromCenter = length(uv);
    uv *= 1.0 - (distFromCenter * audio * 0.1);

    // Camera
    let cameraTravel = u.config.x * (1.6 + speed * 6.0 + audio * 1.8);
    var ro = vec3<f32>(0.0, 4.0, -10.0 + (cameraTravel - 8.0 * floor(cameraTravel / 8.0)));
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Mouse Interaction
    let mouse = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0) * mouseInfluence;

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
    var hit = false;

    for (var i = 0; i < 100; i++) {
        var p = ro + rd * t;
        d = map(p, &global_glow);
        if (d < 0.001) { hit = true; break; }
        if (t > 80.0) { break; }
        t += max(abs(d), 0.002);
    }

    var col = vec3<f32>(0.0);
    var p = ro + rd * t;

    if (hit) {
        var n = calcNormal(p);

        let viewDir = normalize(ro - p);
        let refDir = reflect(-viewDir, n);

        // Pseudo-environment map using refDir
        var envCol = vec3<f32>(0.5, 0.7, 1.0) * max(0.0, refDir.y) + vec3<f32>(0.2, 0.2, 0.2) * max(0.0, -refDir.y);
        // Add some audio-reactive color to the reflection
        envCol += vec3<f32>(0.8, 0.2, 1.0) * audio * 0.5 * max(0.0, refDir.x);

        let chrome_reflectivity = 0.72 + intensity * 0.24;
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
    let boundedGlow = min(global_glow, 8.0);
    col += glowCol * boundedGlow * 0.045 * (0.65 + intensity * 1.1 + audio * 1.8);

    // High-speed reflection bands stretch along the engine conveyor.
    let streakPhase = (uv.x * 19.0 + uv.y * 8.0) - cameraTravel * 3.5;
    let chromeStreak = pow(max(sin(streakPhase), 0.0), 18.0) * smoothstep(0.15, 0.85, distFromCenter);
    col += vec3<f32>(0.35 + treble * 0.4, 0.75 + mids * 0.35, 1.25) * chromeStreak *
           (0.16 + intensity * 0.25);

    // Fog
    col = mix(col, vec3<f32>(0.02, 0.02, 0.05), 1.0 - exp(-0.01 * t));

    // Conveyor-advected, HDR-bounded reflections smear liquid chrome without
    // turning the feedback buffer into an unbounded light accumulator.
    let historyVelocity = vec2<f32>(mouse.x * 2.0, -(2.0 + speed * 5.0 + audio * 2.0));
    let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
    let coord = vec2<i32>(global_id.xy);
    let historyCoord = clamp(coord - vec2<i32>(historyVelocity), vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, historyCoord, 0).rgb;
    let hdrColor = clamp(col * (0.68 + intensity * 0.72) + history * (0.23 + speed * 0.17), vec3<f32>(0.0), vec3<f32>(6.0));
    let alpha = clamp(select(0.02, 0.28 + length(hdrColor) * 0.2, hit) + chromeStreak * 0.18, 0.02, 0.97);
    let depth = select(0.0, clamp(1.0 - t / 80.0, 0.0, 1.0), hit);
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(hdrColor * 1.1), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
