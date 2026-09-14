// ═══════════════════════════════════════════════════════════════════
//  Micro-Cosmos
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Zernike phase-contrast imaging from optical path through each cell (halo + thin-specimen interference tint), mouse-held condenser swaps to darkfield; binary-fission cell cycle with smooth cleavage-furrow pinch
//  A packing: ACES display RGBA in A
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Population Density, y=Fluid Activity, z=Membrane Glow, w=Color Shift
    ripples: array<vec4<f32>, 50>,
};

var<private> g_audio: vec3<f32>;
var<private> g_minD: f32;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// SDF Primitives
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p/r);
    let k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 2D Rotation
fn rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Hash function for random values
fn hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.543))) * 43758.5453);
}

// Scene Map function
fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    var time = u.config.x;

    // Zoom params mapping
    let densityParams = u.zoom_params.x; // 0.0 - 1.0
    let flowSpeed = u.zoom_params.y;     // 0.0 - 2.0

    // Audio-driven helical current and fast forward transport. Both are
    // closed-form, avoiding fixed-per-frame integration.
    let currentAngle = time * (0.8 + flowSpeed * 1.4) + g_audio.y * 0.35 + p.z * 0.22;
    let currentXZ = rotate2D(p.xz, currentAngle * 0.28);
    p.x = currentXZ.x + sin(currentAngle) * (0.35 + g_audio.x * 0.18);
    p.z = currentXZ.y + time * (1.2 + flowSpeed * 1.8);
    p.y += time * (0.45 + flowSpeed * 0.9) + cos(currentAngle) * (0.25 + g_audio.z * 0.12);

    // Domain Repetition
    // Adjust grid size based on density. Higher density -> smaller grid cells.
    let gridSize = mix(6.0, 3.0, densityParams);

    let id = floor(p / gridSize);
    let q = (fract(p / gridSize) - 0.5) * gridSize;

    // Randomization per cell
    let rand = hash(id);

    // Vary position within cell
    let offset = (vec3<f32>(rand, fract(rand * 12.3), fract(rand * 45.6)) - 0.5) * gridSize * 0.4;
    var localP = q - offset;

    // Random rotation
    let temp_localP_xy = rotate2D(localP.xy, time * (0.7 + flowSpeed + rand * 0.6) + g_audio.y * 0.2 + rand * 6.28);
    localP.x = temp_localP_xy.x;
    localP.y = temp_localP_xy.y;

    let temp_localP_xz = rotate2D(localP.xz, time * (0.45 + flowSpeed * 0.7 + rand * 0.35));
    localP.x = temp_localP_xz.x;
    localP.z = temp_localP_xz.y;

    // Cell Body (Ellipsoid)
    // Random scale
    let scale = 0.5 + rand * 0.5;
    let r = vec3<f32>(1.0, 1.5, 0.8) * scale;

    // Wobble effect
    let wobble = sin(localP.x * 3.0 + time * 2.0) * sin(localP.y * 3.0 + time) * sin(localP.z * 3.0) * 0.1 * flowSpeed;

    // IDEA 2: binary fission. Each cell runs its own cycle; late in the cycle
    // the long axis elongates, a cleavage furrow pinches the waist (smooth-min
    // of two daughter ellipsoids with shrinking blend radius) and the daughters
    // drift apart before the cycle restarts. Bass pushes the daughters apart.
    let cycle = fract(time * (0.045 + flowSpeed * 0.02) + rand * 7.31);
    let divide = smoothstep(0.55, 0.92, cycle) * (1.0 - smoothstep(0.96, 1.0, cycle)) * step(0.35, rand);
    let sep = divide * r.y * (0.85 + g_audio.x * 0.15);
    let rd = r * vec3<f32>(1.0 - 0.18 * divide, 1.0 - 0.3 * divide, 1.0 - 0.18 * divide);
    let dA = sdEllipsoid(localP - vec3<f32>(0.0, sep, 0.0), rd);
    let dB = sdEllipsoid(localP + vec3<f32>(0.0, sep, 0.0), rd);
    let body = smin(dA, dB, mix(0.6, 0.06, divide) * scale);

    var d = body + wobble;

    // Note: Organelles are handled via procedural shading (fake inner glow) rather than SDF geometry
    // to simulate translucency without complex transparency sorting.

    // Small surface bump for organic texture
    let bump = sin(localP.x * 10.0) * sin(localP.y * 10.0) * sin(localP.z * 10.0) * 0.02;
    d += bump;

    // Material ID: 1.0 = Cell Membrane, fraction carries division progress
    var mat = 1.0 + divide * 0.5;

    return vec2<f32>(d, mat);
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    var d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.1;
    var mat = 0.0;
    g_minD = 1e3;
    for(var i=0; i<80; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        mat = res.y;
        g_minD = min(g_minD, d / max(t * 0.08, 0.05));
        if(d < 0.001 || t > 50.0) { break; }
        t += d * 0.8; // Understep for better organic shapes
    }
    return vec2<f32>(t, mat);
}

// Optical path through the translucent cell body (entry → exit), sampled
// by stepping inside the SDF. Used for phase-contrast imaging.
fn cellThickness(p: vec3<f32>, rd: vec3<f32>) -> f32 {
    var inside = 0.0;
    let stepLen = 0.22;
    for (var i = 0; i < 12; i++) {
        let q = p + rd * (0.03 + f32(i) * stepLen);
        if (map(q).x < 0.0) { inside += stepLen; }
    }
    return inside;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let screenUV = vec2<f32>(global_id.xy) / resolution;

    // Camera Setup
    var time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    g_audio = vec3<f32>(bass, mids, treble);

    // Mouse Interaction for Camera
    var mouse = u.zoom_config.yz;
    let mouseDown = step(0.5, u.zoom_config.w);
    let aspectFix = vec2<f32>(resolution.x / resolution.y, 1.0);

    // Camera Position - drifting slowly
    let flowSpeed = u.zoom_params.y;
    let ro = vec3<f32>(sin(time * 0.75) * (1.0 + mids * 0.25), cos(time * 0.55) * 0.4, -8.0 + time * (1.4 + flowSpeed * 0.8));
    // Look At
    let ta = vec3<f32>(sin(time * 0.65) * 0.5, cos(time * 0.5) * 0.3, time * (1.4 + flowSpeed * 0.8));

    // Camera Basis
    let fw = normalize(ta - ro);
    let rt = normalize(cross(fw, vec3<f32>(0.0, 1.0, 0.0)));
    let up = cross(rt, fw);

    // Mouse perturbs the ray direction (look offset)
    let rd_pre = normalize(fw + rt * uv.x + up * uv.y);
    let rd = normalize(rd_pre + rt * (mouse.x - 0.5) * 0.5 + up * (mouse.y - 0.5) * 0.5);

    // Raymarch
    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;
    let hit = t < 50.0;
    let nearMiss = g_minD;

    // Environment/Fluid Color (Deep Blue/Purple)
    let colorShift = u.zoom_params.w;
    let glowIntensity = u.zoom_params.z;
    var bgColor = vec3<f32>(0.02, 0.05, 0.1);
    bgColor = mix(bgColor, vec3<f32>(0.1, 0.02, 0.08), colorShift); // Shift to purple

    // Mouse-held condenser swap: brightfield/phase → darkfield around the cursor.
    let mouseDelta = (screenUV - mouse) * aspectFix;
    let darkfield = mouseDown * exp(-dot(mouseDelta, mouseDelta) * 5.0);

    var color = mix(bgColor, bgColor * 0.15, darkfield);
    var coverage = 0.0;
    var thicknessOut = 0.0;

    // IDEA 1 (halo): Zernike phase-contrast rings a bright halo just outside
    // specimen edges; near-miss rays carry it.
    let haloBand = exp(-max(nearMiss, 0.0) * 6.0) * (1.0 - select(0.0, 1.0, hit));
    color += mix(vec3<f32>(0.55, 0.75, 0.85), vec3<f32>(0.85, 0.6, 0.8), colorShift) * haloBand * 0.18 * glowIntensity * (1.0 + treble * 0.4);

    if (hit) {
        var p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting vectors
        let lightDir = normalize(vec3<f32>(0.5, 0.8, -0.5));
        let viewDir = -rd;

        // Basic Diffuse
        let diff = max(dot(n, lightDir), 0.0);

        // Rim Light (Fresnel) - Crucial for microscopic look
        let rim = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        // Base Color of Cell
        var objColor = vec3<f32>(0.4, 0.8, 0.9); // Cyan-ish
        if (colorShift > 0.5) {
             objColor = vec3<f32>(0.9, 0.4, 0.8); // Magenta-ish
        }

        // Translucency / SSS approximation
        let sss = max(0.0, dot(-n, lightDir)) * 0.5;

        // Combine
        var cellCol = objColor * (diff * 0.2 + 0.1) + // Ambient + Diffuse
                vec3<f32>(0.8, 0.9, 1.0) * rim * glowIntensity * 1.5 + // Rim Glow
                objColor * sss * 0.5; // Backlight

        // IDEA 1: phase contrast. Optical path difference (n_cell − n_medium)
        // × thickness shifts phase; the Zernike ring converts it to intensity,
        // and wavelength-dependent phase gives thin-specimen interference tints.
        let thick = cellThickness(p, rd);
        thicknessOut = thick;
        let phase = thick * (2.4 + mids * 0.9);
        let interference = 0.5 + 0.5 * cos(phase * vec3<f32>(1.0, 1.19, 1.43) + colorShift * 2.0);
        let phaseDark = 1.0 - 0.55 * (0.5 - 0.5 * cos(phase));
        cellCol = cellCol * phaseDark + interference * objColor * 0.35 * (0.6 + glowIntensity * 0.25);

        // Darkfield: only scattered light from edges/organelles reaches the eye.
        let dfCol = vec3<f32>(0.9, 0.95, 1.0) * rim * (0.9 + glowIntensity * 0.6) + interference * rim * 0.4;
        cellCol = mix(cellCol, dfCol, darkfield);

        let membraneRunner = pow(max(0.0, sin(atan2(p.y, p.x) * 7.0 + p.z * 9.0 - time * (15.0 + flowSpeed * 3.0))), 10.0);
        cellCol += vec3<f32>(0.2, 0.9, 1.0) * membraneRunner * (0.15 + bass * 0.4) * glowIntensity;

        // Cleavage furrow glow on dividing cells (division progress in mat fraction).
        let divide = clamp((mat - 1.0) * 2.0, 0.0, 1.0);
        cellCol += vec3<f32>(1.0, 0.75, 0.45) * divide * rim * 0.35 * glowIntensity;

        // Inner Organelle Glow (Fake)
        let innerGlow = sin(p.x * 20.0) * sin(p.y * 20.0) * sin(p.z * 20.0);
        if (innerGlow > 0.8 - treble * 0.08) {
             cellCol += vec3<f32>(1.0, 0.8, 0.4) * 0.5 * glowIntensity; // Orange specks
        }

        // Distance Fog (Fluid density)
        let fogAmount = 1.0 - exp(-t * 0.08);
        color = mix(cellCol, color, fogAmount);
        coverage = (1.0 - fogAmount) * clamp(0.45 + thick * 0.25 + rim * 0.3, 0.0, 1.0);
    }

    // Smooth traveling marine snow with fixed particle identities.
    var marineSnow = 0.0;
    for (var si = 0; si < 12; si++) {
        let fs = f32(si);
        let seed = hash(vec3<f32>(fs, fs * 3.1, 7.2));
        let travel = fract(seed + time * (0.06 + flowSpeed * 0.035 + seed * 0.025));
        let snowPos = vec2<f32>(fract(seed * 7.31 + sin(time * 0.7 + fs) * 0.04), 1.1 - travel * 1.2);
        let delta = (screenUV - snowPos) * aspectFix;
        marineSnow += exp(-dot(delta, delta) * 9000.0) * (0.35 + seed * 0.65);
    }
    color += vec3<f32>(0.35, 0.55, 0.7) * marineSnow * (1.0 + darkfield * 1.5);

    // Clicks spawn short-lived microbe blooms instead of mutating persistent state.
    var bloom = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.2) { continue; }
        let delta = (screenUV - ripple.xy) * aspectFix;
        let radius = length(delta);
        let membrane = exp(-abs(radius - age * 0.32) * 80.0);
        let colonies = pow(max(0.0, sin(atan2(delta.y, delta.x) * 9.0 + age * 14.0)), 12.0) * exp(-abs(radius - age * 0.24) * 35.0);
        bloom += (membrane + colonies * 0.7) * (1.0 - age / 2.2);
    }
    color += vec3<f32>(0.25, 1.0, 0.7) * bloom * (0.35 + glowIntensity * 0.2);

    // ACES display colour
    let display = acesToneMap(color * (1.1 + bass * 0.3));

    // Helical advection turns prior membranes into visible organism wakes
    // (exact integer load of display-space history from A).
    let currentDir = normalize(vec2<f32>(cos(time * 0.8), sin(time * 0.8)) + vec2<f32>(0.001));
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);
    let shiftPx = vec2<i32>(round(currentDir * (0.004 + flowSpeed * 0.005) * resolution));
    let historyCoord = clamp(coord - shiftPx, vec2<i32>(0), maxCoord);
    let previous = textureLoad(dataTextureC, historyCoord, 0);
    let temporal = clamp(max(display, previous.rgb * 0.89), vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha = specimen optical density / coverage + snow, blooms, halo, wake.
    let alpha = clamp(max(coverage + marineSnow * 0.5 + bloom * 0.4 + haloBand * 0.15, previous.a * 0.85), 0.06, 1.0);
    let depth = select(1.0, clamp(t / 50.0, 0.0, 0.995), hit);
    let finalColor = vec4<f32>(temporal, alpha);
    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
