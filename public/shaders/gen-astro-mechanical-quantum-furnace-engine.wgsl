// ----------------------------------------------------------------
// Astro-Mechanical Quantum-Furnace Engine
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// --- Math & Noise Helpers ---

const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + vec3<f32>(33.33));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);
    let n = i.x + i.y * 157.0 + i.z * 113.0;

    let a = hash3(vec3<f32>(n)).x;
    let b = hash3(vec3<f32>(n + 1.0)).x;
    let c = hash3(vec3<f32>(n + 157.0)).x;
    let d = hash3(vec3<f32>(n + 158.0)).x;
    let e = hash3(vec3<f32>(n + 113.0)).x;
    let f1 = hash3(vec3<f32>(n + 114.0)).x;
    let g = hash3(vec3<f32>(n + 270.0)).x;
    let h = hash3(vec3<f32>(n + 271.0)).x;

    let res = mix(
        mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
        mix(mix(e, f1, u.x), mix(g, h, u.x), u.y),
        u.z
    );
    return res * 2.0 - 1.0;
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for(var i = 0; i < 4; i++) {
        f += amp * noise3D(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return f;
}

// --- SDF Scene ---

struct MapData {
    d: f32,
    mat: f32, // 0 = void/dust, 1 = gears, 2 = plasma core
    glow: f32
}

fn map(p: vec3<f32>, time: f32, audio: f32, gearComplexity: f32, mouseXY: vec2<f32>) -> MapData {
    var d = 1000.0;
    var mat = 0.0;
    var glow = 0.0;

    var pos = p;

    // Magnetic distortion field driven by mouse interaction
    let gravityWell = vec3<f32>(mouseXY.x * 10.0, mouseXY.y * 10.0, 0.0);
    let distToMouse = length(pos - gravityWell);
    let warpAmt = exp(-distToMouse * 0.2);
    pos += normalize(pos - gravityWell) * warpAmt * sin(time * 2.0);

    // Core Plasma Furnace
    let coreRadius = 2.0 + audio * 0.5;
    let coreWarp = fbm(pos * 2.0 - time);
    let dCore = length(pos) - coreRadius + coreWarp * 0.8;

    // KIFS Fractal Gears
    var q = pos;
    let new_xz1 = rot(time * 0.2) * vec2<f32>(q.x, q.z);
    q.x = new_xz1.x;
    q.z = new_xz1.y;
    let new_xy = rot(time * 0.15) * vec2<f32>(q.x, q.y);
    q.x = new_xy.x;
    q.y = new_xy.y;

    let iterations = i32(mix(2.0, 6.0, gearComplexity));
    var scale = 1.0;

    for(var i = 0; i < 6; i++) {
        if (i >= iterations) { break; }
        q = abs(q) - 1.5 * pow(0.6, f32(i));

        let a = dot(q, vec3<f32>(1.0)) * 0.5;
        q -= 2.0 * min(0.0, a) * vec3<f32>(1.0);
        q = q * 1.4;
        scale *= 1.4;

        // Twist KIFS
        let new_xz2 = rot(0.2) * vec2<f32>(q.x, q.z);
        q.x = new_xz2.x;
        q.z = new_xz2.y;
    }

    var dGears = sdTorus(q, vec2<f32>(3.0, 0.5)) / scale;

    // Audio-reactive exhaust streams
    var pStream = pos;
    pStream.y -= time * 5.0; // flow upwards/outwards
    let streamNoise = fbm(pStream * 3.0);
    let dStreams = length(pos.xz) - 0.5 - audio * streamNoise * 2.0;

    // Combine geometry
    dGears = max(dGears, -(length(pos) - coreRadius - 0.5)); // carve out cavity for core

    if (dCore < dGears && dCore < dStreams) {
        d = dCore;
        mat = 2.0;
        glow = pow(max(0.0, 1.0 - dCore), 2.0);
    } else if (dGears < dStreams) {
        d = dGears;
        mat = 1.0;
    } else {
        d = dStreams;
        mat = 2.0;
        glow = pow(max(0.0, 1.0 - dStreams), 2.0);
    }

    return MapData(d * 0.6, mat, glow); // safe step
}

fn getNormal(p: vec3<f32>, time: f32, audio: f32, complexity: f32, mouse: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, audio, complexity, mouse).d;
    let n = vec3<f32>(
        map(p + e.xyy, time, audio, complexity, mouse).d - d,
        map(p + e.yxy, time, audio, complexity, mouse).d - d,
        map(p + e.yyx, time, audio, complexity, mouse).d - d
    );
    return normalize(n);
}

// --- Main Compute ---

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) { return; }

    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * res) / res.y;

    let time = u.config.x;
    let audio = u.config.y;

    // UI Sliders
    let gearComplexity = u.zoom_params.x;
    let plasmaIntensity = u.zoom_params.y;
    let refIndex = u.zoom_params.z;
    let emissionThresh = u.zoom_params.w;

    let mouseNorm = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) / res) * 2.0 - 1.0;

    // Camera
    var ro = vec3<f32>(0.0, 0.0, 12.0);
    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let fwd = normalize(lookAt - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(fwd + right * uv.x + up * uv.y);

    // Raymarch
    var t = 0.0;
    var d = 0.0;
    var mat = 0.0;
    var totalGlow = 0.0;
    var iter = 0;

    for(var i = 0; i < 120; i++) {
        iter = i;
        let p = ro + rd * t;
        let resData = map(p, time, audio, gearComplexity, mouseNorm);
        d = resData.d;
        mat = resData.mat;

        if (resData.mat == 2.0) {
            totalGlow += resData.glow * 0.05 * plasmaIntensity;
        }

        if (d < 0.001 || t > 30.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);

    if (t < 30.0) {
        let p = ro + rd * t;
        let n = getNormal(p, time, audio, gearComplexity, mouseNorm);

        if (mat == 1.0) {
            // Metallic brass shading
            let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
            let diff = max(dot(n, lightDir), 0.0);
            let refl = reflect(rd, n);
            let spec = pow(max(dot(refl, lightDir), 0.0), 32.0);

            let baseColor = vec3<f32>(0.8, 0.6, 0.2); // Brass

            // Refraction simulation using view vector
            let envWarp = fbm(refl * refIndex);

            col = baseColor * diff * 0.6 + vec3<f32>(1.0) * spec * 0.4 + baseColor * envWarp * 0.2;

            // Ambient occlusion based on KIFS depth
            let ao = clamp(1.0 - f32(iter) / 120.0, 0.0, 1.0);
            col *= ao;
        } else if (mat == 2.0) {
            // Quantum Plasma Core
            col = vec3<f32>(1.0, 1.0, 1.0) * 1.5; // pure white hot core
        }
    } else {
        // Deep space nebula void
        let starNoise = fbm(rd * 50.0 + time * 0.1);
        col = mix(vec3<f32>(0.0), vec3<f32>(0.1, 0.05, 0.2), fbm(rd * 5.0 - time * 0.05));
        if (starNoise > 0.8) {
            col += vec3<f32>(1.0) * pow((starNoise - 0.8) * 5.0, 3.0);
        }
    }

    // Add volumetric glow
    let glowColor = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.9, 0.5), audio);
    col += glowColor * totalGlow * step(emissionThresh, totalGlow);

    // Cinematic DOF / Vignette
    let vignette = 1.0 - smoothstep(0.5, 1.5, length(uv));
    col *= vignette;

    // Tone mapping
    col = col / (1.0 + col);

    // Previous frame mix for temporal motion blur
    var prev = textureLoad(readTexture, vec2<i32>(id.xy), 0).rgb;
    let finalCol = mix(prev, col, 0.4);

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(finalCol, 1.0));
}
