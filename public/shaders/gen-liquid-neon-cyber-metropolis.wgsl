// ═══════════════════════════════════════════════════════════════════
//  Liquid-Neon Cyber-Metropolis
//  Category: generative
//  Features: raymarching, domain-repetition, kifs, audio-reactive, mouse-driven
//  Complexity: High
//  Created: 2026-04-19
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Neon Intensity, y=City Density, z=Audio Reactivity, w=Gravity Warp Strength
    ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 96;
const MAX_DIST: f32 = 120.0;
const SURF_DIST: f32 = 0.002;
const PI: f32 = 3.14159265;

// ═══ Rotation Helpers ═══
fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// ═══ Hash / Noise ═══
fn hash2(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ SDF Primitives ═══
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdVerticalCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// ═══ Smooth Operators ═══
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn smax(a: f32, b: f32, k: f32) -> f32 {
    return -smin(-a, -b, k);
}

// ═══ Domain Repetition (2D infinite) ═══
fn opRep(p: vec2<f32>, c: f32) -> vec2<f32> {
    return (fract(p / c + 0.5) - 0.5) * c;
}

// ═══ KIFS Fold ═══
fn kifsFold(p: vec3<f32>, iterations: i32) -> vec3<f32> {
    var pt = p;
    for (var i: i32 = 0; i < iterations; i = i + 1) {
        pt = abs(pt) - vec3<f32>(0.4, 0.4, 0.4);
        let r1 = rot2D(0.6 + f32(i) * 0.1);
        let pXY = r1 * vec2<f32>(pt.x, pt.y);
        pt.x = pXY.x;
        pt.y = pXY.y;
        let r2 = rot2D(0.4 + f32(i) * 0.08);
        let pYZ = r2 * vec2<f32>(pt.y, pt.z);
        pt.y = pYZ.x;
        pt.z = pYZ.y;
    }
    return pt;
}

// ═══ Neon Gradient ═══
fn neonGradient(t: f32, audio: f32) -> vec3<f32> {
    let shift = audio * 0.3;
    let cyan = vec3<f32>(0.0, 1.0, 1.0);
    let magenta = vec3<f32>(1.0, 0.0, 1.0);
    let electric = vec3<f32>(0.5, 0.8, 1.0);
    var col = mix(cyan, magenta, fract(t + shift));
    col = mix(col, electric, sin(t * 2.0) * 0.3 + 0.3);
    return col;
}

// ═══ Scene Distance Field ═══
fn map(p_in: vec3<f32>, global_glow: ptr<function, f32>) -> f32 {
    var p = p_in;
    let t = u.config.x;
    let audio = u.config.y * u.zoom_params.z;
    let bass = plasmaBuffer[0].x * u.zoom_params.z;

    // --- Mouse Gravity Warp ---
    let mouseUV = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let warpStrength = u.zoom_params.w;
    if (warpStrength > 0.01) {
        let toMouse = mouseUV - p.xz;
        let distToMouse = length(toMouse);
        let warpRadius = 8.0;
        let warpFactor = warpStrength * 3.0 / (1.0 + distToMouse * distToMouse * 0.1);
        p.xz = p.xz - normalize(toMouse + vec2<f32>(0.001)) * warpFactor * exp(-distToMouse / warpRadius);
    }

    // --- Infinite Domain Repetition ---
    let density = u.zoom_params.y;
    let cellSize = 18.0 - density * 0.5;
    let cellID = floor(p.xz / cellSize + 0.5);
    var localP = p;
    localP.xz = opRep(p.xz, cellSize);

    // Per-cell randomization
    let cellRand = hash2(cellID);
    let cellRand2 = hash2(cellID + vec2<f32>(13.37, 7.77));
    let cellRand3 = hash2(cellID + vec2<f32>(99.99, 11.11));

    // --- Skyscraper Base ---
    let baseWidth = 1.5 + cellRand * 1.0;
    let baseDepth = 1.5 + cellRand2 * 1.0;
    let audioHeight = 6.0 + sin(t * 2.0 + cellRand * 10.0) * 2.0 + bass * 5.0;
    let buildingHeight = max(2.0, audioHeight);

    var building = sdBox(localP - vec3<f32>(0.0, buildingHeight * 0.5, 0.0),
                         vec3<f32>(baseWidth, buildingHeight * 0.5, baseDepth));

    // --- KIFS Antenna Crown ---
    let antennaP = localP - vec3<f32>(0.0, buildingHeight, 0.0);
    let kifsP = kifsFold(antennaP, 3);
    let antenna = sdBox(kifsP, vec3<f32>(0.3, 0.8, 0.3));
    building = smin(building, antenna, 0.5);

    // --- Neon Veins (carved into building) ---
    let veinSpacing = 0.6;
    let veinP = localP;
    veinP.y = fract(veinP.y / veinSpacing) * veinSpacing - veinSpacing * 0.5;
    let veinPlane = abs(veinP.y) - 0.02;
    let veinCylinder = sdVerticalCylinder(veinP - vec3<f32>(0.0, 0.0, 0.0), 0.05, baseWidth * 0.9);
    let veins = smin(veinPlane, veinCylinder, 0.1);

    // --- Horizontal Neon Rings ---
    let ringP = localP;
    let ringY = fract(ringP.y / 2.5) * 2.5 - 1.25;
    let ring = abs(abs(ringY) - 0.04) - 0.01;
    let ringCyl = abs(length(localP.xz) - (baseWidth + 0.05)) - 0.03;
    let rings = max(ring, ringCyl);

    // Combine veins and rings
    let allNeon = min(veins, rings);

    // Smooth subtract neon from building
    building = smax(building, -allNeon, 0.15);

    // --- Street-level details ---
    let streetP = localP;
    streetP.y = streetP.y + 0.2;
    let streetBox = sdBox(streetP, vec3<f32>(baseWidth + 0.3, 0.2, baseDepth + 0.3));
    building = smin(building, streetBox, 0.3);

    // --- Ground plane ---
    let ground = p.y + 0.1;

    // --- Scene combination ---
    var d = min(building, ground);

    // --- Accumulate Glow from Neon ---
    let neonDist = allNeon;
    let neonIntensity = u.zoom_params.x;
    let glowAmount = 0.005 / (0.02 + abs(neonDist)) * neonIntensity * (1.0 + bass * 2.0);
    *global_glow = *global_glow + glowAmount;

    // --- Radar Scan Sweep ---
    let scanSpeed = 0.3;
    let scanPos = fract(t * scanSpeed) * cellSize * 6.0 - cellSize * 3.0;
    let scanDist = abs(p.x - scanPos);
    let scanBand = smoothstep(0.5, 0.0, scanDist);
    *global_glow = *global_glow + scanBand * 0.3 * neonIntensity * (1.0 + bass);

    return d;
}

// ═══ Normal Calculation ═══
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.0005;
    var dummy: f32 = 0.0;
    return normalize(
        e.xyy * map(p + e.xyy, &dummy) +
        e.yyx * map(p + e.yyx, &dummy) +
        e.yxy * map(p + e.yxy, &dummy) +
        e.xxx * map(p + e.xxx, &dummy)
    );
}

// ═══ Main Compute Entry ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<f32>(f32(global_id.x), f32(global_id.y));
    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    var uv = (coords - 0.5 * res) / res.y;
    let t = u.config.x;
    let audio = u.config.y;
    let bass = plasmaBuffer[0].x;

    // --- Camera Setup ---
    var ro = vec3<f32>(
        sin(t * 0.1) * 5.0,
        3.0 + sin(t * 0.2) * 1.5,
        -15.0 + t * 0.8
    );
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.2));

    // --- Mouse Look ---
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let rotY = rot2D(-mouse.x * 1.0);
    let rotX = rot2D(mouse.y * 0.6);

    let rdXZ = rotY * vec2<f32>(rd.x, rd.z);
    rd.x = rdXZ.x; rd.z = rdXZ.y;
    let rdYZ = rotX * vec2<f32>(rd.y, rd.z);
    rd.y = rdYZ.x; rd.z = rdYZ.y;

    let roXZ = rotY * vec2<f32>(ro.x, ro.z);
    ro.x = roXZ.x; ro.z = roXZ.y;

    // --- Raymarch ---
    var dist = 0.0;
    var global_glow = 0.0;
    var p = ro;

    for (var i: i32 = 0; i < MAX_STEPS; i = i + 1) {
        p = ro + rd * dist;
        let d = map(p, &global_glow);
        if (d < SURF_DIST || dist > MAX_DIST) {
            break;
        }
        dist = dist + d;
    }

    // --- Shading ---
    var col = vec3<f32>(0.0);
    p = ro + rd * dist;

    if (dist < MAX_DIST) {
        let n = calcNormal(p);
        let viewDir = normalize(ro - p);

        // Dark matter concrete albedo
        let concrete = vec3<f32>(0.03, 0.03, 0.04);

        // Directional light
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.3));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 16.0);

        // Fresnel for wet/rain-slicked look
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        // Environment reflection (neon sky)
        let refDir = reflect(-viewDir, n);
        let envCol = vec3<f32>(0.1, 0.15, 0.25) * max(0.0, refDir.y)
                   + vec3<f32>(0.05, 0.05, 0.08) * max(0.0, -refDir.y);

        col = concrete * (diff * 0.4 + 0.2) + vec3<f32>(spec) * 0.3;
        col = mix(col, envCol, fresnel * 0.4);

        // Neon vein proximity coloring
        var neonGlow = 0.0;
        var dummy: f32 = 0.0;
        var _ = map(p + n * 0.02, &neonGlow);
        let neonCol = neonGradient(t * 0.5 + p.y * 0.2, bass);
        col = col + neonCol * neonGlow * 0.1 * u.zoom_params.x;
    }

    // --- Volumetric Glow & Bloom ---
    let glowCol = neonGradient(t * 0.3, bass);
    col = col + glowCol * global_glow * 0.08;

    // --- Atmospheric Fog ---
    let fogDensity = 0.015;
    let fogAmount = 1.0 - exp(-dist * fogDensity);
    let fogCol = vec3<f32>(0.01, 0.01, 0.02) * (1.0 + bass * 0.5);
    col = mix(col, fogCol, fogAmount);

    // --- Vignette ---
    let vignette = 1.0 - length(uv) * 0.4;
    col = col * vignette;

    // --- Gamma correction ---
    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
