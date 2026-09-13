// ═══════════════════════════════════════════════════════════════════
//  Luminescent Cyber-Chrono Void-Turtle
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: chronal plate drift (per-cell lift, bass-kicked); chrono-distortion time dilation in mouse well; scute growth rings; void wake via exact C history
//  A packing: raw linear wake emission RGB (pre-tonemap) + a = wake energy
// ═══════════════════════════════════════════════════════════════════
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX (uv), z=MouseY (uv, 0=top), w=MouseDown
    zoom_params: vec4<f32>,  // x=Shell Complexity, y=Plasma Intensity, z=Chrono-Distortion, w=Swim Speed
    ripples: array<vec4<f32>, 50>,
};

// Math & Noise Functions
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

const TAU: f32 = 6.28318530718;

// 3D Voronoi for the shell plates — returns (F1, F2, nearest plate id hash)
fn voronoi(x: vec3<f32>) -> vec3<f32> {
    let p = floor(x);
    let f = fract(x);

    var res = vec2<f32>(8.0, 8.0);
    var cellId = 0.0;

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = vec3<f32>(b) - f + hash33(p + b);
                let d = dot(r, r);

                if (d < res.x) {
                    res.y = res.x;
                    res.x = d;
                    cellId = hash33(p + b + vec3<f32>(7.13)).x;
                } else if (d < res.y) {
                    res.y = d;
                }
            }
        }
    }

    return vec3<f32>(sqrt(res.x), sqrt(res.y), cellId);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 0.0001);
}

// Global Variables
var<private> glow: f32 = 0.0;
var<private> gTime: f32 = 0.0;
var<private> gBass: f32 = 0.0;
// Plate state at the last map() evaluation (read after the hit for shading)
var<private> gPlateF1: f32 = 0.0;
var<private> gPlateEdge: f32 = 1.0;
var<private> gPlateId: f32 = 0.0;
var<private> gDilation: f32 = 0.0;

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Mouse Gravity Well (Chrono-distortion)
    let mouseNorm = u.zoom_config.yz; // already canvas UV (0=top)
    // Map from [0,1] to world [-4, 4]; world Y is up, UV Y is down
    let mousePos = vec3<f32>((mouseNorm.x * 2.0 - 1.0) * 4.0, -(mouseNorm.y * 2.0 - 1.0) * 4.0, 0.0);

    let distToMouse = length(p - mousePos);
    let distortionStrength = u.zoom_params.z;
    if (distortionStrength > 0.0) {
        let warp = distortionStrength / (distToMouse + 0.1);
        p = p + (p - mousePos) / max(distToMouse, 0.001) * warp;
    }

    // IDEA 2 — chrono-distortion time dilation: the gravity well slows local time
    let dilation = distortionStrength * smoothstep(3.5, 0.0, distToMouse);
    gDilation = dilation;
    let localTime = gTime * (1.0 - 0.75 * dilation);

    // Turtle Base Shape (Ellipsoid body)
    let bodyRot = rot(sin(gTime * u.zoom_params.w) * 0.2);
    var pBody = p;
    let temp_yz = bodyRot * pBody.yz;
    pBody = vec3<f32>(pBody.x, temp_yz.x, temp_yz.y);
    let temp_xz = bodyRot * pBody.xz;
    pBody = vec3<f32>(temp_xz.x, pBody.y, temp_xz.y);

    let baseShell = sdEllipsoid(pBody, vec3<f32>(2.0, 1.0, 2.5));

    // Shell Complexity (Voronoi Plates)
    let complexity = u.zoom_params.x * 5.0 + 2.0;
    let v = voronoi(pBody * complexity + vec3<f32>(localTime * 0.1));

    // Plate edge thickness
    let edge = v.y - v.x;

    // Create gaps between plates
    let gapWidth = 0.1;
    let inGap = smoothstep(gapWidth, 0.0, edge);

    // IDEA 1 — chronal plate drift: every plate rises/sinks on its own phase,
    // kicked by bass; gaps stay anchored so plates read as floating tiles
    let plateLift = sin(localTime * (0.6 + 0.8 * u.zoom_params.w) + v.z * TAU)
                  * (0.04 + gBass * 0.05) * (1.0 - inGap);

    // Extrude plates out slightly
    var shell = baseShell - v.x * 0.2 - plateLift;

    gPlateF1 = v.x;
    gPlateEdge = edge;
    gPlateId = v.z;

    // Hollow out gaps slightly
    shell = shell + inGap * 0.15;

    // Plasma Glow in gaps
    let plasmaIntensity = u.zoom_params.y;
    // Base glow
    // Plates rising out of the shell open wider plasma seams
    var localGlow = inGap * plasmaIntensity * (1.0 + gBass * 1.2 + max(plateLift, 0.0) * 4.0);

    // Ripple effect in glow (ripples: xy = uv, z = start time; w is padding)
    let rippleCount = min(u32(u.config.y), 5u); // Only check first 5 for performance
    for(var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = gTime - ripple.z;
        let live = select(0.0, exp(-age * 1.2), ripple.z > 0.0 && age >= 0.0);
        let rPos = vec2<f32>((ripple.x * 2.0 - 1.0) * 4.0, -(ripple.y * 2.0 - 1.0) * 4.0);
        let rDist = length(p.xy - rPos);
        let rRadius = age * 2.5;
        let rWave = sin((rDist - rRadius) * 5.0) * 0.5 + 0.5;
        let rEnvelope = smoothstep(0.5, 0.0, abs(rDist - rRadius));
        localGlow += rWave * rEnvelope * live * inGap * plasmaIntensity * 5.0;
    }

    // Accumulate glow (attenuated by distance to surface)
    glow += localGlow * 0.02 / (abs(shell) + 0.01);

    // Add simple head and fins
    var pHead = pBody;
    pHead.z -= 3.0;
    pHead.y -= 0.2;
    let head = sdEllipsoid(pHead, vec3<f32>(0.5, 0.4, 0.8));

    var pFinL = pBody;
    pFinL.x -= 2.2;
    pFinL.z -= 1.5;
    let tempL_xy = rot(-0.5) * pFinL.xy;
    pFinL = vec3<f32>(tempL_xy.x, tempL_xy.y, pFinL.z);
    let finL = sdEllipsoid(pFinL, vec3<f32>(1.2, 0.1, 0.8));

    var pFinR = pBody;
    pFinR.x += 2.2;
    pFinR.z -= 1.5;
    let tempR_xy = rot(0.5) * pFinR.xy;
    pFinR = vec3<f32>(tempR_xy.x, tempR_xy.y, pFinR.z);
    let finR = sdEllipsoid(pFinR, vec3<f32>(1.2, 0.1, 0.8));

    var turtle = smin(shell, head, 0.5);
    turtle = smin(turtle, finL, 0.3);
    turtle = smin(turtle, finR, 0.3);

    return turtle;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let h = 0.001;
    let k = vec2<f32>(1.0, -1.0);
    return normalize(
        k.xyy * map(p + k.xyy * h) +
        k.yyx * map(p + k.yyx * h) +
        k.yxy * map(p + k.yxy * h) +
        k.xxx * map(p + k.xxx * h)
    );
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p2 = p;
    for (var i = 0; i < 4; i++) {
        v += a * hash33(p2).x;
        p2 = p2 * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let pixelCoords = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (pixelCoords.x >= dims.x || pixelCoords.y >= dims.y) {
        return;
    }

    let uv = (pixelCoords - 0.5 * dims) / dims.y;

    gTime = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    gBass = clamp(bass, 0.0, 2.0);

    // Camera setup
    var ro = vec3<f32>(0.0, 2.0, -8.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slow rotation of camera
    let camRot = rot(sin(gTime * 0.1) * 0.2);

    let temp_ro_xz = camRot * ro.xz;
    ro = vec3<f32>(temp_ro_xz.x, ro.y, temp_ro_xz.y);
    let temp_rd_xz = camRot * rd.xz;
    rd = vec3<f32>(temp_rd_xz.x, rd.y, temp_rd_xz.y);

    let rot_x = rot(0.2);
    let temp_ro_yz = rot_x * ro.yz;
    ro = vec3<f32>(ro.x, temp_ro_yz.x, temp_ro_yz.y);
    let temp_rd_yz = rot_x * rd.yz;
    rd = vec3<f32>(rd.x, temp_rd_yz.x, temp_rd_yz.y);

    var t = 0.0;
    var d = 0.0;
    var p = ro;
    var hit = false;
    glow = 0.0;

    // Raymarching
    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        d = map(p);

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d * 0.7; // Step size reduction for safety with distortions
    }

    var col = vec3<f32>(0.0);
    var bgClouds = 0.0;
    var fresnel = 0.0;

    if (hit) {
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let viewDir = normalize(ro - p);
        let refl = reflect(-l, n);
        let spec = pow(max(dot(viewDir, refl), 0.0), 32.0);

        // Plate state at the hit (last map() calls were at/near p)
        let plateF1 = gPlateF1;
        let plateEdge = gPlateEdge;
        let plateId = gPlateId;
        fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        // Dark Obsidian base color, each plate a slightly different stone
        let baseColor = vec3<f32>(0.05, 0.06, 0.07) * (0.8 + 0.4 * plateId);

        col = baseColor * (diff * 0.8 + 0.2) + vec3<f32>(spec * 0.5);

        // IDEA 3 — scute growth rings: concentric annuli around each plate
        // centre, grooved into the obsidian; ring phase creeps outward with
        // (dilated) chronal time so older rings feel like accumulated epochs
        let ringTime = gTime * (1.0 - 0.75 * gDilation) * 0.15;
        let ringPhase = plateF1 * (18.0 + 10.0 * u.zoom_params.x) - ringTime + plateId * TAU;
        let groove = smoothstep(0.75, 1.0, 0.5 + 0.5 * cos(ringPhase))
                   * smoothstep(0.02, 0.12, plateEdge);
        col *= 1.0 - 0.45 * groove;
        col += vec3<f32>(0.1, 0.8, 1.0) * groove * u.zoom_params.y * 0.06 * (1.0 + mids * 0.6);

        // Add fake subsurface scattering / ambient based on glow
        col += vec3<f32>(0.1, 0.8, 1.0) * glow * 0.5;
    } else {
        // Nebula background
        let bgStars = pow(fbm(rd * 50.0), 10.0) * 2.0 * (1.0 + clamp(treble, 0.0, 2.0) * 0.4);
        bgClouds = fbm(rd * 3.0 + vec3<f32>(0.0, 0.0, gTime * 0.05));
        col = vec3<f32>(0.02, 0.05, 0.1) * bgClouds + vec3<f32>(bgStars);
    }

    // Add volumetric plasma glow
    let glowColor = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.2, 0.8), sin(gTime + clamp(mids, 0.0, 2.0) * 0.8)*0.5+0.5);
    col += glow * glowColor;

    // IDEA 4 — void wake: plasma shed by the shell streams outward from the
    // turtle through the void at Swim Speed. Exact C history, advected radially.
    let center = dims * 0.5;
    let toPix = pixelCoords - center;
    let wakeDir = toPix / max(length(toPix), 1.0);
    let wakeSpeed = 0.6 + 1.6 * u.zoom_params.w;
    let srcCoord = clamp(vec2<i32>(pixelCoords - wakeDir * wakeSpeed), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
    let prevWake = textureLoad(dataTextureC, srcCoord, 0);
    let wakeDecay = 0.955;
    let shed = glowColor * min(glow, 3.0) * 0.12;
    let wakeRGB = min(prevWake.rgb * wakeDecay + shed, vec3<f32>(4.0));
    let wakeEnergy = clamp(max(prevWake.a * wakeDecay, min(glow, 1.0)), 0.0, 1.0);
    col += wakeRGB * select(0.7, 0.15, hit);

    // Add ripple visual directly to background if no hit (for extra effect)
    if (!hit) {
         let bgRipples = min(u32(u.config.y), 5u);
         for(var i = 0u; i < bgRipples; i++) {
            let ripple = u.ripples[i];
            let age = gTime - ripple.z;
            let live = select(0.0, exp(-age * 1.5), ripple.z > 0.0 && age >= 0.0);
            let rUV = (pixelCoords / dims) - ripple.xy;
            let rDist = length(vec2<f32>(rUV.x * dims.x / max(dims.y, 1.0), rUV.y));
            let rRadius = age * 0.4;
            let rWave = sin((rDist - rRadius) * 60.0) * 0.5 + 0.5;
            let rEnvelope = smoothstep(0.05, 0.0, abs(rDist - rRadius));
            col += glowColor * rWave * rEnvelope * live * 0.2;
        }
    }

    // ACES tone mapping on display RGB, then gamma (keeps HEAD's lifted obsidian)
    let mapped = pow(acesToneMap(col), vec3<f32>(1.0 / 2.2));

    // Semantic alpha: body coverage + fresnel rim, plasma glow, wake, nebula density
    let glowLum = clamp(glow * 0.5, 0.0, 1.0);
    let alpha = clamp(select(0.0, 0.8 + 0.2 * fresnel, hit) + glowLum * 0.4 + wakeEnergy * 0.3 + bgClouds * 0.15, 0.05, 1.0);

    textureStore(writeTexture, vec2<i32>(pixelCoords), vec4<f32>(mapped, alpha));
    let depth = select(0.0, 1.0 - clamp(t / 20.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(pixelCoords), vec4<f32>(wakeRGB, wakeEnergy));
}
