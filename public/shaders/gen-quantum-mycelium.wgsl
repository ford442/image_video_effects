// ----------------------------------------------------------------
// Quantum Mycelium
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Network Density, y=Growth Chaos, z=Pulse Speed, w=Edge Softness
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var bp = p;
    var amp = 0.5;
    for (var i = 0; i < 4; i++) {
        let h = hash33(bp);
        f += amp * h.x;
        bp *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdCylinder(p: vec3<f32>, c: vec3<f32>) -> f32 {
    return length(p.xz - c.xy) - c.z;
}

var<private> g_time: f32;
var<private> g_mouse: vec2<f32>;
var<private> g_audio: f32;

fn map(p: vec3<f32>) -> vec3<f32> {
    var bp = p;
    let density = u.zoom_params.x; // Network Density
    let chaos = u.zoom_params.y; // Growth Chaos

    // Domain Repetition
    let c = vec3<f32>(5.0 / density);
    var q = bp;

    // FBM Distortion for organic twisting
    let noiseOffset = vec3<f32>(fbm(q * 0.5 + vec3<f32>(g_time * 0.2)), fbm(q * 0.4 - vec3<f32>(g_time * 0.1)), fbm(q * 0.6)) * chaos;
    q += noiseOffset;

    // Apply repetition
    q = q - c * round(vec3<f32>(q / c));

    // Spatial folding for branching illusion
    q = abs(q) - vec3<f32>(1.0 / density, 1.0 / density, 1.0 / density);
    let temp_q_xy = rot(0.5) * q.xy;
    q.x = temp_q_xy.x;
    q.y = temp_q_xy.y;

    q = abs(q) - vec3<f32>(0.5 / density, 0.5 / density, 0.5 / density);
    let temp_q_xz = rot(0.3) * q.xz;
    q.x = temp_q_xz.x;
    q.z = temp_q_xz.y;

    // Base Cylinder SDF
    var d = sdCylinder(q, vec3<f32>(0.0, 0.0, 0.15 / density));
    let threadCenterDist = length(q.xz);

    // Mouse Repulsion Sphere
    let mouse3D = vec3<f32>(g_mouse.x * 10.0, g_mouse.y * 10.0, 5.0); // Projection of mouse into space
    let mouseDist = length(bp - mouse3D);
    let repulsionSphere = mouseDist - 2.5; // Big void sphere

    // Smin blending to push cylinders away and thin them out
    d = smin(d, repulsionSphere + 2.0, 1.0); // Softly blend
    d = max(d, -repulsionSphere); // Cut out the sphere completely

    return vec3<f32>(d, 1.0, threadCenterDist);
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
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }

    var uv = (fragCoord * 2.0 - dims) / dims.y;

    g_time = u.config.x;
    g_audio = u.config.y * 0.1;

    let mX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mY = -(u.zoom_config.z / dims.y) * 2.0 + 1.0;
    g_mouse = vec2<f32>(mX, mY);

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -g_time * 2.0); // Move forward through the network
    ro = vec3<f32>(ro.xy + g_mouse * 2.0, ro.z);

    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var maxT = 30.0;
    var accumDens = 0.0;

    for (var i = 0; i < 90; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;

        // Volumetric spore accumulation
        let sporeThick = u.zoom_params.w * 0.5;
        if (d > 0.1) {
            accumDens += sporeThick * 0.02 * (1.0 / (1.0 + d * d));
        }

        if (d < 0.005 || t > maxT) { break; }
        t += d * 0.7; // Step factor for safety
    }

    var col = vec3<f32>(0.02, 0.01, 0.05); // Deep background
    var alpha = 0.0;

    if (t < maxT) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Retrieve thread center distance from the hit point
        let res = map(p);
        let distToThread = res.z;
        let edgeSoftness = u.zoom_params.w * 0.5;
        alpha = 1.0 - smoothstep(0.0, edgeSoftness, distToThread);

        // Fake Subsurface Scattering
        let subsurfaceP = p - n * 0.15;
        let subsurfaceDist = map(subsurfaceP).x;
        let sss = smoothstep(0.0, 0.2, -subsurfaceDist) * 0.8;
        let fleshyCol = vec3<f32>(0.8, 0.3, 0.4);

        // Bioluminescent Energy Pulses
        let pulseSpeed = u.zoom_params.z;
        let treble = plasmaBuffer[0].z;
        let pulseWave = sin(p.z * 5.0 - g_time * pulseSpeed * 3.0 + g_audio * 5.0 + treble * 10.0);
        let pulse = smoothstep(0.8, 1.0, pulseWave);
        let glowCol = vec3<f32>(0.1, 0.9, 0.8) * pulse * 3.0; // Neon cyan pulse

        let dif = max(dot(n, vec3<f32>(0.5, 0.8, 0.5)), 0.0);
        let fre = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        col = fleshyCol * dif * 0.5;
        col += fleshyCol * sss;
        col += glowCol;
        col += fre * vec3<f32>(0.5, 0.7, 1.0) * 0.5;

        // Distance fog
        let fog = 1.0 - exp(-t * 0.15);
        col = mix(col, vec3<f32>(0.02, 0.01, 0.05), fog);
    }

    // Apply volumetric spore cloud
    let sporeCol = vec3<f32>(0.4, 0.8, 0.5);
    col += sporeCol * min(accumDens, 1.0);

    // Tone mapping
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    let screenUV = fragCoord / dims;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screenUV, 0.0).r;
    textureStore(writeDepthTexture, vec2<u32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, vec2<u32>(id.xy), vec4<f32>(col, alpha));
}
