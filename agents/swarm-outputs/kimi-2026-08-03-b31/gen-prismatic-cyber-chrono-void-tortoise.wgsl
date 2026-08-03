// Prismatic Cyber-Chrono Void-Tortoise — Category: generative
// Upgraded 2026-08-03 (swarm b31, optimizer): CRITICAL non-canonical Uniforms
// struct replaced (resolution/time/mouse fields misaligned the 848-byte
// buffer); sliders remapped off config.yzw (resH/rippleCount!) onto
// zoom_params.xyzw. Added smooth-union legs/head/tail, hex-scute shell
// tessellation with emissive seams, KIFS distance-LOD, adaptive raymarch,
// abyssal mote field, real depth + dataTextureA + semantic alpha.
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1, y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // x=Time, y=Audio Reactivity, z=Brightness, w=Evolution Speed
  ripples: array<vec4<f32>, 50>,
};
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_DIST: f32 = 20.0;
const BASE_STEPS: i32 = 64;
const STEP_RANGE: f32 = 32.0;    // adaptive steps: 64..96 with Evolution Speed
const SMIN_BODY: f32 = 0.3;      // body/shell blend radius
const SMIN_LIMB: f32 = 0.25;     // limb blend radius
const MAT_BODY: f32 = 1.0;
const MAT_SHELL: f32 = 2.0;

// Axis-angle rotation matrix
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
// 2D hex-tessellation: distance to nearest hex-cell border (shell scutes)
fn hexBorder(p: vec2<f32>) -> f32 {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let a = fract(p / r) * r - h;
    let b = fract((p + h) / r) * r - h;
    let ga = abs(a);
    let gb = abs(b);
    return 0.5 - min(max(dot(ga, vec2<f32>(0.8660254, 0.5)), ga.x),
                     max(dot(gb, vec2<f32>(0.8660254, 0.5)), gb.x));
}
// Drifting abyssal motes (background particulate layer)
fn moteField(p: vec2<f32>) -> f32 {
    let cell = floor(p);
    let f = fract(p) - 0.5;
    let jitter = vec2<f32>(hash21(cell + 3.0), hash21(cell + 11.0)) - 0.5;
    let mote = 1.0 - smoothstep(0.0, 0.06, length(f - jitter * 0.7));
    return mote * step(0.93, hash21(cell));
}

// KIFS fractal for the shell's pocket dimension (iteration count = LOD input)
fn kifs(p: vec3<f32>, time: f32, iters: i32) -> f32 {
    var z = p;
    var scale = 1.0;
    let axis = vec3<f32>(0.57735027, 0.57735027, 0.57735027); // normalize(1,1,1)
    for (var i = 0; i < iters; i++) {
        z = abs(z) - vec3<f32>(0.5, 0.5, 0.5);
        z = z * rot3D(axis, time * 0.1);
        z = z * 2.0;
        scale = scale * 2.0;
    }
    return (length(z) - 1.0) / scale;
}

// Main SDF map: returns vec2(distance, materialID)
fn map(p: vec3<f32>, time: f32, audioWobble: f32, kIters: i32) -> vec2<f32> {
    // Gravitational drag from mouse (branchless; mouse pre-centered, y=0 top kept)
    let mouse = (u.zoom_config.yz - 0.5) * 2.0;
    let mouse_pos = vec3<f32>(mouse, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    let twist_angle = 2.0 / (dist_to_mouse + 0.5);
    let dragAxis = normalize(mouse_pos + vec3<f32>(0.0, 0.0, 1.0));
    let pd = p * rot3D(dragAxis, twist_angle * (1.0 + u.zoom_config.w));

    // Tortoise body base (audio-pulsing breath)
    let breathe = 1.0 + audioWobble * 0.04;
    let body = length(pd * vec3<f32>(1.0, 2.0, 1.0)) - 1.5 * breathe;

    // Limbs + head + tail: smooth-union capsules (slow swimming gait)
    let gait = time * 0.8;
    var limbs = 1000.0;
    limbs = min(limbs, sdCapsule(pd, vec3<f32>( 0.9, -0.4,  0.6), vec3<f32>( 1.5, -0.7 + sin(gait) * 0.15,  1.0), 0.28));
    limbs = min(limbs, sdCapsule(pd, vec3<f32>(-0.9, -0.4,  0.6), vec3<f32>(-1.5, -0.7 - sin(gait) * 0.15,  1.0), 0.28));
    limbs = min(limbs, sdCapsule(pd, vec3<f32>( 0.9, -0.4, -0.6), vec3<f32>( 1.5, -0.7 - sin(gait) * 0.15, -1.0), 0.28));
    limbs = min(limbs, sdCapsule(pd, vec3<f32>(-0.9, -0.4, -0.6), vec3<f32>(-1.5, -0.7 + sin(gait) * 0.15, -1.0), 0.28));
    limbs = min(limbs, sdCapsule(pd, vec3<f32>(0.0, 0.1, 1.2), vec3<f32>(0.0, 0.25 + sin(gait * 0.5) * 0.1, 2.1), 0.32)); // head
    limbs = min(limbs, sdCapsule(pd, vec3<f32>(0.0, -0.3, -1.2), vec3<f32>(0.0, -0.4, -1.8), 0.15));                     // tail

    // Shell: base dome intersected with KIFS pocket dimension (distance-LOD iters)
    let shell_base = length(pd * vec3<f32>(1.0, 1.5, 1.0) - vec3<f32>(0.0, 0.5, 0.0)) - 1.6;
    let shell_fractal = kifs(pd, time, kIters);
    let shell = max(shell_base, shell_fractal * 0.5);

    // Smooth-union the anatomy, branchless material pick
    let flesh = smin(body, limbs, SMIN_LIMB);
    let tortoise = smin(flesh, shell, SMIN_BODY);
    let mat = select(MAT_BODY, MAT_SHELL, shell < flesh);
    return vec2<f32>(tortoise, mat);
}

fn calcNormal(p: vec3<f32>, time: f32, audioWobble: f32, kIters: i32) -> vec3<f32> {
    let e = vec2<f32>(0.002, 0.0);
    let dx = map(p + e.xyy, time, audioWobble, kIters).x - map(p - e.xyy, time, audioWobble, kIters).x;
    let dy = map(p + e.yxy, time, audioWobble, kIters).x - map(p - e.yxy, time, audioWobble, kIters).x;
    let dz = map(p + e.yyx, time, audioWobble, kIters).x - map(p - e.yyx, time, audioWobble, kIters).x;
    return normalize(vec3<f32>(dx, dy, dz));
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let pixel = vec2<i32>(gid.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);

    // Sliders — all four live (remapped off the misused config.yzw)
    let timeOffset = u.zoom_params.x;      // "Time" — chrono phase offset
    let audioReact = u.zoom_params.y;      // "Audio Reactivity"
    let brightness = u.zoom_params.z;      // "Brightness" — exposure
    let evoSpeed = u.zoom_params.w;        // "Evolution Speed" — time scale

    let time = u.config.x * evoSpeed * 0.4 + timeOffset * 2.0;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioWobble = bass * audioReact;

    // Adaptive march budget scales with Evolution Speed
    let steps = BASE_STEPS + i32(clamp(evoSpeed * 6.0, 0.0, STEP_RANGE));

    // Camera: slow orbit + mouse parallax, rebuilt in-code
    let camA = time * 0.08 + (u.zoom_config.y - 0.5) * 0.9;
    let camR = 5.0 - u.zoom_config.w * 1.2; // mouse-down leans in
    let cr = rot3D(vec3<f32>(0.0, 1.0, 0.0), camA);
    let ro = cr * vec3<f32>(0.0, 0.6 + (u.zoom_config.z - 0.5) * 1.2, camR);
    let rd = cr * normalize(vec3<f32>(uv, -1.5));

    // Raymarch: growing epsilon, KIFS distance-LOD, early exits
    var t = 0.0;
    var hit = false;
    var mat = 0.0;
    for (var i = 0; i < steps; i++) {
        let p = ro + rd * t;
        let kIters = select(4, 3, t > 9.0); // LOD: fewer KIFS folds far away
        let m = map(p, time, audioWobble, kIters);
        let eps = 0.001 * (1.0 + t * 0.4);
        if (m.x < eps) { hit = true; mat = m.y; break; }
        t += m.x * 0.9;
        if (t > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.0);
    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p, time, audioWobble, 4);
        let lig = normalize(vec3<f32>(0.6, 0.9, 0.5));
        let dif = max(dot(n, lig), 0.0);
        let fre = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let spec = pow(max(dot(reflect(-lig, n), -rd), 0.0), 24.0);

        // Cheap soft shadow toward the key light (hit pixels only, 8 taps)
        var shadow = 1.0;
        var st = 0.05;
        for (var s = 0; s < 8; s++) {
            let sd = map(p + lig * st, time, audioWobble, 3).x;
            shadow = min(shadow, 8.0 * sd / st);
            st += clamp(sd, 0.05, 0.4);
        }
        shadow = clamp(shadow, 0.2, 1.0);

        // Obsidian-glass flesh with prismatic Fresnel rim
        let fleshCol = vec3<f32>(0.08, 0.13, 0.18) * (0.3 + dif * shadow * 0.9)
                     + vec3<f32>(0.3, 0.9, 1.0) * fre * 0.5
                     + vec3<f32>(1.0) * spec * 0.6;

        // Chrono-glass shell: hex-scute tessellation with emissive seams
        let sp = vec2<f32>(atan2(p.z, p.x) / TAU + 0.5, p.y * 0.25 + 0.5);
        let scute = hexBorder(sp * vec2<f32>(10.0, 6.0));
        let seam = (1.0 - smoothstep(0.0, 0.05, scute)) * (0.6 + treble * audioReact * 0.5);
        var fft = 0.0;
        if (arrayLength(&extraBuffer) > 40u) { fft = extraBuffer[5u + (gid.x + gid.y) % 32u]; }
        let pocketHue = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0),
                            0.5 + 0.5 * sin(time + t * 5.0 + fft * 2.0));
        let shellCol = vec3<f32>(0.05, 0.1, 0.14) * (0.3 + dif * shadow * 0.8)
                     + pocketHue * (0.35 + bass * audioReact * 0.5)
                     + pocketHue.brg * seam * 1.2
                     + vec3<f32>(1.0) * spec * 0.8;

        col = select(fleshCol, shellCol, mat > 1.5);
    }

    // Abyssal quantum sea: depth gradient + drifting motes + plankton glow
    let abyss = mix(vec3<f32>(0.02, 0.05, 0.1), vec3<f32>(0.0, 0.01, 0.03), saturate(uv.y + 0.5));
    let motes = moteField(uv * 8.0 + vec2<f32>(time * 0.1, -time * 0.05)) * (0.3 + mids * audioReact * 0.4);

    // Engine ripple rings shimmering across the sea (guarded loop, <=50)
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleGlow = 0.0;
    for (var ri = 0u; ri < rippleCount; ri++) {
        let rp = u.ripples[ri];
        let age = u.config.x - rp.z;
        let ruv = (rp.xy - 0.5) * res / min(res.x, res.y);
        let ring = abs(length(uv - ruv) - age * 0.6);
        rippleGlow += (1.0 - smoothstep(0.0, 0.03, ring)) * exp(-max(age, 0.0) * 1.5) * step(0.0, age);
    }
    rippleGlow = min(rippleGlow, 1.5);

    col = select(abyss + vec3<f32>(0.4, 0.8, 0.9) * motes + vec3<f32>(0.2, 0.7, 0.9) * rippleGlow, col, hit);
    col += vec3<f32>(0.2, 0.7, 0.9) * rippleGlow * select(0.3, 0.0, hit);

    col = acesToneMap(col * (0.6 + brightness * 0.8)); // Brightness = exposure
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.12 + luma * 0.9, 0.0, 1.0); // semantic alpha
    let depth = select(0.0, clamp(1.0 - t / MAX_DIST, 0.0, 1.0), hit);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, select(0.0, mat, hit)));
}
