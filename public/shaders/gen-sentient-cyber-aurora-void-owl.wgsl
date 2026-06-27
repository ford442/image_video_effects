// ----------------------------------------------------------------
// Sentient Cyber-Aurora Void-Owl
// Category: generative
// ----------------------------------------------------------------

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

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

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash3(p + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(dot(hash3(p + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash3(p + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash3(p + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(dot(hash3(p + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash3(p + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for(var i = 0; i < 4; i++) {
        value += amp * noise3(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    return value;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// --- SDF functions ---

struct MapData {
    d: f32,
    mat: f32,
    glow: f32,
}

fn map(p: vec3<f32>, time: f32, audio: f32, mouseXY: vec2<f32>, wingbeat_speed: f32, eye_intensity: f32) -> MapData {
    var d = 1000.0;
    var mat = 0.0;
    var glow = 0.0;

    var pos = p;

    // Head tracking the mouse
    let headLookX = mouseXY.x * 0.5;
    let headLookY = -mouseXY.y * 0.5;
    var headPos = pos - vec3<f32>(0.0, 1.0, 0.0);
    let headRotMatX = rot(headLookX);
    let headRotMatY = rot(headLookY);
    // Apply rotations
    headPos.x = headPos.x * headRotMatX[0][0] + headPos.z * headRotMatX[0][1];
    headPos.z = headPos.x * headRotMatX[1][0] + headPos.z * headRotMatX[1][1];
    let newYZ = rot(headLookY) * vec2<f32>(headPos.y, headPos.z);
    headPos.y = newYZ.x;
    headPos.z = newYZ.y;

    // Body Base (Capsule)
    let pa = pos - vec3<f32>(0.0, -1.5, 0.0);
    let ba = vec3<f32>(0.0, 3.0, 0.0) - vec3<f32>(0.0, -1.5, 0.0);
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    let dBody = length(pa - ba * h) - 1.2 * (1.0 - h * 0.5);

    // Head Base (Sphere)
    let dHead = length(headPos) - 1.0;
    var dOwl = smin(dBody, dHead, 0.5);

    // Feathers (Lattice of prisms)
    var fPos = pos;
    // Wing animation
    let wingbeat = sin(time * 5.0 * wingbeat_speed) * (0.5 + audio * 1.5);

    // Repetition for feathers
    fPos.x = abs(fPos.x); // Symmetry
    let wingPos = fPos - vec3<f32>(1.5, 0.0, 0.0);

    // Rotate wings based on wingbeat
    var wPos = wingPos;
    let wRot = rot(wingbeat * 0.5);
    let nwxy = wRot * vec2<f32>(wPos.x, wPos.y);
    wPos.x = nwxy.x;
    wPos.y = nwxy.y;

    let latticeScale = 0.5;
    var q = wPos;
    q = (fract(q / latticeScale + 0.5) - 0.5) * latticeScale;
    let dFeatherCube = length(max(abs(q) - vec3<f32>(0.2, 0.05, 0.1), vec3<f32>(0.0)));

    // Bounding volume for wings
    let dWingBox = length(max(abs(wPos) - vec3<f32>(2.0, 3.0, 0.5), vec3<f32>(0.0)));
    let dWings = max(dFeatherCube, dWingBox);

    dOwl = min(dOwl, dWings);

    // Eyes (Nested spheres)
    var eyePosL = headPos - vec3<f32>(0.4, 0.2, -0.8);
    var eyePosR = headPos - vec3<f32>(-0.4, 0.2, -0.8);

    let dEyeGlassL = length(eyePosL) - 0.3;
    let dEyeGlassR = length(eyePosR) - 0.3;
    let dEyeGlass = min(dEyeGlassL, dEyeGlassR);

    // Eye Core
    let dEyeCoreL = length(eyePosL) - 0.15;
    let dEyeCoreR = length(eyePosR) - 0.15;
    let dEyeCore = min(dEyeCoreL, dEyeCoreR);

    if (dEyeCore < dOwl && dEyeCore < dEyeGlass) {
        d = dEyeCore;
        mat = 2.0; // Emissive core
        glow = pow(max(0.0, 1.0 - dEyeCore), 2.0) * eye_intensity * (1.0 + audio * 2.0);
    } else if (dEyeGlass < dOwl) {
        d = dEyeGlass;
        mat = 1.0; // Glass
    } else {
        d = dOwl;
        mat = 0.0; // Feathers / Body
    }

    return MapData(d * 0.5, mat, glow); // Safe step due to space warping
}

fn getNormal(p: vec3<f32>, time: f32, audio: f32, mouseXY: vec2<f32>, wingbeat_speed: f32, eye_intensity: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, audio, mouseXY, wingbeat_speed, eye_intensity).d;
    let n = vec3<f32>(
        map(p + e.xyy, time, audio, mouseXY, wingbeat_speed, eye_intensity).d - d,
        map(p + e.yxy, time, audio, mouseXY, wingbeat_speed, eye_intensity).d - d,
        map(p + e.yyx, time, audio, mouseXY, wingbeat_speed, eye_intensity).d - d
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
    let wingbeat_speed = u.zoom_params.x;
    let eye_intensity = u.zoom_params.y;
    let aurora_density = u.zoom_params.z;
    let glass_refraction = u.zoom_params.w;

    let mouseNorm = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) / res) * 2.0 - 1.0;

    // Camera
    var ro = vec3<f32>(0.0, 1.0, 10.0);
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

    // Volumetric Aurora
    var volColor = vec3<f32>(0.0);
    var volDensity = 0.0;

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let resData = map(p, time, audio, mouseNorm, wingbeat_speed, eye_intensity);
        d = resData.d;
        mat = resData.mat;

        if (resData.mat == 2.0) {
            totalGlow += resData.glow * 0.1;
        }

        // Volumetric aurora accumulation (background/ambient)
        let auroraNoise = fbm(p * 0.5 + vec3<f32>(time * 0.2, time * 0.1, 0.0));
        let localDensity = smoothstep(0.4, 0.8, auroraNoise) * aurora_density * 0.05;
        volDensity += localDensity;

        // Color mapping for aurora
        let aColor = mix(vec3<f32>(0.0, 0.8, 0.5), vec3<f32>(0.8, 0.2, 0.8), sin(p.y * 0.5 + time) * 0.5 + 0.5);
        volColor += aColor * localDensity;

        if (d < 0.005 || t > 25.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);

    if (t < 25.0) {
        let p = ro + rd * t;
        let n = getNormal(p, time, audio, mouseNorm, wingbeat_speed, eye_intensity);

        if (mat == 0.0) {
            // Obsidian Feathers
            let lightDir = normalize(vec3<f32>(1.0, 2.0, 1.0));
            let diff = max(dot(n, lightDir), 0.0);
            let refl = reflect(rd, n);
            let spec = pow(max(dot(refl, lightDir), 0.0), 32.0);

            let baseColor = vec3<f32>(0.05, 0.05, 0.08); // Obsidian
            col = baseColor * diff * 0.8 + vec3<f32>(0.5, 0.8, 1.0) * spec * 0.5;

        } else if (mat == 1.0) {
            // Glass Refraction
            let lightDir = normalize(vec3<f32>(1.0, 2.0, 1.0));
            let refl = reflect(rd, n);
            let envWarp = fbm(refl * 5.0 + time);
            col = vec3<f32>(0.2, 0.4, 0.5) * envWarp * glass_refraction;

            // Rim light
            let rim = 1.0 - max(dot(-rd, n), 0.0);
            col += vec3<f32>(0.5, 0.8, 1.0) * pow(rim, 3.0);
        } else if (mat == 2.0) {
            // Quantum Plasma Core
            col = mix(vec3<f32>(0.8, 0.2, 1.0), vec3<f32>(0.2, 1.0, 1.0), audio);
            col *= 2.0; // Emissive
        }
    }

    // Add aurora and glow
    col += volColor;

    let glowColor = mix(vec3<f32>(0.8, 0.2, 1.0), vec3<f32>(0.2, 1.0, 1.0), clamp(audio * 2.0, 0.0, 1.0));
    col += glowColor * totalGlow;

    // Aether-Glimmer Dust (Particles via noise overlay)
    let pNoise = fbm(vec3<f32>(uv * 20.0, time));
    if (pNoise > 0.8) {
        col += vec3<f32>(0.5, 1.0, 0.8) * (pNoise - 0.8) * 5.0 * (1.0 + audio);
    }

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
