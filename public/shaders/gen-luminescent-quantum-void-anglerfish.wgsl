// ═══════════════════════════════════════════════════════════════════
//  Luminescent Quantum-Void Anglerfish
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: esca symbiotic-bacteria colony pulse with quorum-sensing sync; bioluminescent lateral-line photophore wave
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
    config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
    zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
    zoom_params: vec4<f32>,  // .x = Jaw Rotation, .y = Lure Intensity, .z = Void Density, .w = Fractal Rust
    ripples: array<vec4<f32>, 50>,
};

// Per-frame audio / interaction state shared with map()
var<private> g_bass: f32 = 0.0;
var<private> g_mids: f32 = 0.0;
var<private> g_treble: f32 = 0.0;
var<private> g_shock: f32 = 0.0;
var<private> g_held: f32 = 0.0;

// ----------------------------------------------------------------
// Helper Math & SDFs
// ----------------------------------------------------------------

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p2 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p2 += vec3<f32>(dot(p2, p2.yxz + vec3<f32>(33.33)));
    return fract((p2.xxy + p2.yxx) * p2.zyx);
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// Native idea 1: esca symbiotic-bacteria colony pulse.
// The anglerfish lure glows from bacterial colonies packed in the esca bulb.
// Each colony flickers on its own phase; quorum sensing pulls them into a
// synchronized breath that bass tightens.
// ----------------------------------------------------------------
fn escaBacterialPulse(pLure: vec3<f32>, t: f32) -> f32 {
    let cellP = pLure * 9.0;
    let cell = floor(cellP);
    let h = hash33(cell);
    let f = fract(cellP) - vec3<f32>(0.5) - (h - vec3<f32>(0.5)) * 0.6;
    let colony = smoothstep(0.55, 0.1, length(f));
    let ownPhase = sin(t * (2.0 + h.y * 3.0) + h.x * 6.2831);
    let quorum = sin(t * 1.7);
    let sync = clamp(0.25 + g_bass * 0.6, 0.0, 1.0);
    let flicker = 0.5 + 0.5 * mix(ownPhase, quorum, sync);
    return 0.45 + colony * flicker * (0.9 + g_bass * 0.4) + g_shock * 0.6;
}

// ----------------------------------------------------------------
// Native idea 2: lateral-line photophores.
// Rows of bioluminescent photophores along the flanks of the body, lit by
// a travelling wave that runs head-to-tail; treble sparkles them and click
// ripples send a flash down the line.
// ----------------------------------------------------------------
fn lateralLinePhotophores(pb: vec3<f32>, t: f32) -> f32 {
    let flank = smoothstep(0.7, 1.3, abs(pb.x));
    let spacing = 0.42;
    let cz = pb.z - spacing * floor(pb.z / spacing) - spacing * 0.5;
    let row1 = length(vec2<f32>(pb.y - 0.05, cz));
    let row2 = length(vec2<f32>(pb.y + 0.55, cz));
    let spot = max(smoothstep(0.11, 0.03, row1), smoothstep(0.08, 0.02, row2) * 0.7);
    let wave = 0.5 + 0.5 * sin(pb.z * 3.5 - t * 4.0);
    let travel = pow(wave, 3.0) * (0.6 + g_treble * 0.5);
    let flash = g_shock * exp(-abs(pb.z - (g_shock * 5.0 - 2.0)) * 1.5);
    let inRange = smoothstep(-2.6, -2.0, pb.z) * smoothstep(3.5, 2.5, pb.z);
    return flank * spot * inRange * (0.25 + travel + flash * 2.0);
}

// ----------------------------------------------------------------
// Procedural Geometries
// ----------------------------------------------------------------

struct MapData {
    d: f32,
    mat_id: i32,  // 0=body, 1=lure, 2=jaw/teeth, 3=particles, 4=fins
    emis: vec3<f32>,
    bp: vec3<f32>, // body-space position
}

fn map(pos: vec3<f32>) -> MapData {
    var d = 1e10;
    var res = MapData(d, 0, vec3<f32>(0.0), vec3<f32>(0.0));
    let t = u.config.x;

    // Body SDF
    var pBody = pos;
    // Mouse gaze interaction: simple slow rotation towards mouse mapping
    let gazeRotX = (u.zoom_config.y * 2.0 - 1.0) * 0.5;
    let gazeRotY = (u.zoom_config.z * 2.0 - 1.0) * 0.5;
    let pBodyXZ = rot(-gazeRotX) * pBody.xz;
    pBody.x = pBodyXZ.x;
    pBody.z = pBodyXZ.y;
    let pBodyYZ = rot(-gazeRotY) * pBody.yz;
    pBody.y = pBodyYZ.x;
    pBody.z = pBodyYZ.y;
    res.bp = pBody;

    // Anglerfish Main Body (Deformed Sphere + Capsule)
    var dBody = sdCapsule(pBody, vec3<f32>(0.0, 0.0, -2.0), vec3<f32>(0.0, 0.0, 1.0), 1.5);
    let tail = sdCapsule(pBody, vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.0, 0.0, 4.0), 0.5 - pBody.z * 0.05);
    dBody = smin(dBody, tail, 1.0);

    // Fractal Rust Displacement
    let rustParam = u.zoom_params.w;
    let rustDisp = (sin(pBody.x * 20.0) * sin(pBody.y * 20.0) * sin(pBody.z * 20.0)) * 0.05 * rustParam;
    dBody += rustDisp;

    res.d = dBody;
    res.mat_id = 0;

    // Jaw & Teeth (Box & Cone SDF mapped along curved domain)
    var pJaw = pBody;
    pJaw.y += 1.0;
    pJaw.z += 1.5;

    // Jaw Rotation from uniform; holding the mouse gapes the jaw wider, bass snaps it
    let jawOpen = clamp(u.zoom_params.x + g_held * 0.3 + g_bass * 0.08, 0.0, 1.0);
    let jawAngle = jawOpen * 3.14159 * 0.5; // Up to 90 degrees open
    if (pJaw.y < 0.0) {
        let pJawYZ = rot(jawAngle) * pJaw.yz;
        pJaw.y = pJawYZ.x;
        pJaw.z = pJawYZ.y;
    }

    var dJaw = sdBox(pJaw - vec3<f32>(0.0, -0.5, 0.0), vec3<f32>(1.2, 0.2, 1.0));
    dJaw = max(dJaw, -sdBox(pJaw - vec3<f32>(0.0, -0.5, 0.0), vec3<f32>(1.0, 0.5, 0.8))); // Hollow inside

    // Teeth instances
    var pTeeth = pJaw;
    pTeeth.x = pTeeth.x - 0.3 * floor(pTeeth.x / 0.3); // modulo replacement
    let dTeeth = sdCapsule(pTeeth, vec3<f32>(0.0, -0.3, -1.0), vec3<f32>(0.0, 0.2, -1.0), 0.05);
    dJaw = min(dJaw, dTeeth);

    if (dJaw < res.d) {
        res.d = dJaw;
        res.mat_id = 2;
    }

    // Esca (Lure)
    var pLure = pBody;
    pLure.y -= 2.0 + sin(t) * 0.2;
    pLure.z += 2.5;

    let dLure = sdSphere(pLure, 0.3);

    // Aether-Particle Swarm
    // Sonic shockwave effect on click ripples
    let shockwave = g_shock;
    var pParticles = pLure;
    let particleOffset = hash33(floor(pParticles * 5.0 + vec3<f32>(t))) * 2.0 - vec3<f32>(1.0);
    pParticles += particleOffset * (1.0 + shockwave * 5.0);
    let dParticles = sdSphere(pParticles - vec3<f32>(0.0, -0.5, 0.0), 0.05);

    if (dLure < res.d) {
        res.d = dLure;
        res.mat_id = 1;
        let pulse = escaBacterialPulse(pLure, t);
        let bloom = vec3<f32>(0.0, 1.0, 1.0) * u.zoom_params.y * pulse * (1.0 + g_bass * 0.45);
        res.emis = bloom;
    }

    if (dParticles < res.d) {
        res.d = dParticles;
        res.mat_id = 3;
        res.emis = vec3<f32>(1.0, 0.0, 1.0) * u.zoom_params.y * 2.0 * (1.0 + g_treble * 0.35);
    }

    // Translucent Fins
    var pFins = pBody;
    pFins.y += 1.5;
    let dFins = sdBox(pFins, vec3<f32>(0.1, 1.0, 2.0)) + sin(pFins.z * 5.0 - t * 2.0) * 0.2 * (1.0 + g_mids * 0.4);
    if (dFins < res.d) {
        res.d = dFins;
        res.mat_id = 4;
        res.emis = vec3<f32>(0.0, 0.5, 1.0) * 0.5;
    }

    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy).d - map(p - e.xyy).d,
        map(p + e.yxy).d - map(p - e.yxy).d,
        map(p + e.yyx).d - map(p - e.yyx).d
    );
    return normalize(n);
}

// ----------------------------------------------------------------
// Volumetric & Rendering
// ----------------------------------------------------------------

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resX = u.config.z;
    let resY = u.config.w;

    if (f32(global_id.x) >= resX || f32(global_id.y) >= resY) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;

    g_bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    g_mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    g_treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    g_held = select(0.0, 1.0, u.zoom_config.w > 0.5);

    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    var uv = (fragCoord - 0.5 * vec2<f32>(resX, resY)) / resY;
    let screenUV = fragCoord / vec2<f32>(resX, resY);
    let aspect = resX / resY;

    // Click ripples: global shockwave for the swarm/lateral line + screen rings
    var shock = 0.0;
    var ringGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rip = u.ripples[i];
        let age = time - rip.z;
        if (age >= 0.0 && age < 3.0) {
            shock = max(shock, exp(-age * 1.8));
            let dv = (screenUV - rip.xy) * vec2<f32>(aspect, 1.0);
            let ring = abs(length(dv) - age * 0.45);
            ringGlow += smoothstep(0.03, 0.0, ring) * exp(-age * 1.5);
        }
    }
    g_shock = shock;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -8.0);
    var rd = normalize(vec3<f32>(uv, 1.5));

    // Mouse camera rotation
    let mx = (u.zoom_config.y * 2.0 - 1.0) * 0.5;
    let my = (u.zoom_config.z * 2.0 - 1.0) * 0.5;
    let rdYZ = rot(-my) * rd.yz;
    rd.y = rdYZ.x;
    rd.z = rdYZ.y;
    let rdXZ = rot(mx) * rd.xz;
    rd.x = rdXZ.x;
    rd.z = rdXZ.y;

    var t = 0.0;
    var col = vec3<f32>(0.0);
    var accumEmis = vec3<f32>(0.0);
    var hit = false;
    var m = MapData(0.0, 0, vec3<f32>(0.0), vec3<f32>(0.0));

    let voidDensity = u.zoom_params.z;

    // Raymarching Loop
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        m = map(p);

        // Volumetric accumulation in the void
        accumEmis += vec3<f32>(0.05, 0.0, 0.1) * voidDensity * 0.01 * (1.0 + g_mids * 0.3);
        accumEmis += m.emis * 0.05;

        if (m.d < 0.001) {
            hit = true;
            break;
        }
        if (t > 30.0) {
            break;
        }
        t += m.d;
    }

    var alpha = 0.0;
    var depth = 0.0;

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, -2.0));

        var matCol = vec3<f32>(0.1); // Base metal

        if (m.mat_id == 0) {
            matCol = vec3<f32>(0.2, 0.18, 0.15); // Tarnished brass
        } else if (m.mat_id == 2) {
            matCol = vec3<f32>(0.4); // Mechanics
        } else if (m.mat_id == 4) {
            matCol = vec3<f32>(0.0, 0.2, 0.4); // Fins
        }

        let diff = max(dot(n, l), 0.0);
        let refl = reflect(rd, n);
        let spec = pow(max(dot(refl, l), 0.0), 32.0);

        col = matCol * diff + spec * 0.5;
        col += m.emis;

        // Lateral-line photophores on the body flanks
        if (m.mat_id == 0) {
            let photo = lateralLinePhotophores(m.bp, time);
            col += vec3<f32>(0.15, 0.75, 1.0) * photo * (0.6 + u.zoom_params.y * 0.4);
            alpha += photo * 0.3;
        }

        depth = clamp(1.0 - t / 30.0, 0.0, 1.0);
        alpha += 0.55 + diff * 0.3 + spec * 0.15;
    }

    // Apply volumetric absorption (Beer's Law)
    let absorb = 1.0 - exp(-t * voidDensity * 0.1);
    col = mix(col, vec3<f32>(0.0, 0.0, 0.05), absorb);
    col += accumEmis;
    col += vec3<f32>(0.1, 0.6, 0.8) * ringGlow * 0.35 * (0.5 + u.zoom_params.y * 0.3);

    // Bioluminescent afterglow: exact previous-frame load
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    let pc = clamp(coord, vec2<i32>(0), dims - vec2<i32>(1));
    let previous = textureLoad(dataTextureC, pc, 0);
    col = max(col, previous.rgb * (0.82 + g_mids * 0.06) * 0.35);

    col = acesToneMap(col * (1.0 + g_bass * 0.2));
    let glowAlpha = clamp(dot(accumEmis, vec3<f32>(0.3, 0.5, 0.2)) + ringGlow * 0.3, 0.0, 1.0);
    let finalAlpha = clamp(alpha * (1.0 - absorb * 0.5) + glowAlpha, 0.0, 1.0);
    let finalColor = vec4<f32>(col, finalAlpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
