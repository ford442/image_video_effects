// ═══════════════════════════════════════════════════════════════════
//  Silica Tsunami
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-03 (Batch 33)
// ═══════════════════════════════════════════════════════════════════

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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=waveHeight, y=glassRefraction, z=particleDensity, w=audioReactivity
    ripples: array<vec4<f32>, 50>,
};

// Utils
fn hash31(p: vec3<f32>) -> f32 {
    var p3  = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// Map function
fn map(pos: vec3<f32>, time: f32) -> f32 {
    let waveHeight = u.zoom_params.x; // default 2.0
    let particleDensity = u.zoom_params.z; // default 1.0
    let audioReactivity = u.zoom_params.w; // default 1.5
    let audio = plasmaBuffer[0].x * audioReactivity; // bass swells the wave crests

    var p = pos;
    // Higher Particle Density means tighter repetition; default 1.0 is unchanged.
    let spacing = 1.0 / max(particleDensity, 0.1);
    let half_spacing = spacing * 0.5;

    // Mouse attractor/repulsor
    let mouseActive = u.zoom_config.w;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouse = select(rawMouse, vec2<f32>(extraBuffer[133], extraBuffer[134]), extraBuffer[137] > 0.5);
    let mousePos = vec3<f32>((mouse.x - 0.5) * 16.0, 0.0, -time * 5.0 + (mouse.y - 0.5) * 16.0);

    if (mouseActive > 0.5) {
        let dToMouse = length(p.xz - mousePos.xz);
        let repel = smoothstep(5.0, 0.0, dToMouse) * 2.0;
        p.y += repel;
    }

    // Wave displacement
    let waveOffset = sin(p.x * 0.5 - time) * cos(p.z * 0.5 - time) * waveHeight;
    p.y -= waveOffset + audio * sin(p.x * 2.0);

    // Domain repetition
    let id = floor(p / spacing);
    p = fract(p / spacing) * spacing - half_spacing;

    // Base shape
    let r = 0.3 * (0.5 + 0.5 * hash31(id));
    return length(p) - r;
}

fn calcNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time);
    return normalize(vec3<f32>(
        map(p + e.xyy, time) - d,
        map(p + e.yxy, time) - d,
        map(p + e.yyx, time) - d
    ));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let pixel = vec2<f32>(f32(id.x), f32(id.y));

    if (pixel.x >= dims.x || pixel.y >= dims.y) {
        return;
    }

    var uv = (pixel - 0.5 * dims) / dims.y;
    let time = u.config.x;

    // Audio reactivity: mids boost fresnel caustics, treble adds spec sparkle
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouse = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouse) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouse += mouseVelocity * springDt;
    if (id.x == 0u && id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = time;
    }

    var ro = vec3<f32>(0.0, 5.0, -time * 5.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y - 0.5, -1.0)); // look slightly down
    let rot_xz = rot(0.2) * rd.xz;
    rd.x = rot_xz.x;
    rd.z = rot_xz.y;

    var t = 0.0;
    var d = 0.0;
    var p = vec3<f32>(0.0);
    var col = vec3<f32>(0.0);

    let max_steps = 80;
    let max_dist = 40.0;

    for (var i = 0; i < max_steps; i++) {
        p = ro + rd * t;
        d = map(p, time);
        if (d < 0.01 || t > max_dist) { break; }
        t += max(d * 0.8, 0.002);
    }

    let hit = t < max_dist;
    var surfFresnel = 0.0;
    if (hit) {
        let n = calcNormal(p, time);
        let l = normalize(vec3<f32>(-1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let r = reflect(rd, n);

        let glassRefraction = u.zoom_params.y; // default 0.8
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
        surfFresnel = fresnel;
        let eta = mix(0.62, 0.92, glassRefraction);
        let refracted = refract(rd, n, eta);
        let transmission = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.1, 4.2) + refracted.y * 5.0 + refracted.x * 2.0);

        col = vec3<f32>(0.1, 0.4, 0.8) * diff; // base water color
        col += transmission * (0.25 + glassRefraction * 0.55) * (1.0 - fresnel) * (1.0 + mids * 0.35);
        col += vec3<f32>(0.8, 0.9, 1.0) * fresnel * glassRefraction * (1.0 + mids * 0.6); // caustics
        col += pow(max(dot(r, l), 0.0), 32.0) * vec3<f32>(1.0) * (1.0 + treble * 1.5); // spec

        // Fog
        col = mix(col, vec3<f32>(0.05, 0.1, 0.2), 1.0 - exp(-0.02 * t * t));
    } else {
        col = vec3<f32>(0.05, 0.1, 0.2); // background
    }

    let uv01 = (pixel + vec2<f32>(0.5)) / dims;
    var clickFracture = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(dims.x / dims.y, 1.0);
            let radius = length(delta);
            let ring = exp(-abs(radius - age * 0.24) * 75.0) * exp(-age * 1.6);
            let shards = pow(max(0.0, cos(atan2(delta.y, delta.x) * 9.0 + age * 3.0)), 16.0);
            clickFracture = max(clickFracture, ring * (0.65 + shards * 0.7));
        }
    }
    col += vec3<f32>(0.65, 0.9, 1.35) * clickFracture * (0.5 + treble * 0.3);
    col = col / (1.0 + max(col, vec3<f32>(0.0)));
    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.4545));

    // Alpha: water surface coverage from fresnel + diffuse body, never flat 1.0
    let alpha = clamp(select(0.0, 0.45, hit) + surfFresnel * 0.5 + clickFracture * 0.25, 0.0, 0.97);
    let out = vec4<f32>(acesToneMap(col * 1.1), alpha);

    // Depth: wave hit distance (near = closer)
    let depth = select(0.0, clamp(1.0 - t / max_dist, 0.0, 1.0), hit);
    let coord = vec2<i32>(id.xy);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
