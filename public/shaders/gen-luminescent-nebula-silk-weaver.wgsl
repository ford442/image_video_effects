// ═══════════════════════════════════════════════════════════════════
//  Luminescent Nebula-Silk Weaver
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: plucked-thread standing waves (bass, mouse tension damps); dew beads with treble glint; silk afterglow via exact C history; gossamer backlighting (Henyey-Greenstein forward scatter from the nebula core behind the web); vibrating-string envelope (antinodes blur into a dimmer spindle)
//  A packing: linear HDR composite RGB (pre-ACES) + a = accumulated silk density
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: .x = Flow Complexity, .y = Ribbon Width, .z = Iridescence, .w = Audio Pulse

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Per-frame audio + per-sample bead state (set in main / map)
var<private> gPluck: f32 = 0.0;
var<private> gBead: f32 = 0.0;
var<private> gEnv: f32 = 0.0;

// Nebula core that backlights the web (world space, behind the target).
const CORE_POS: vec3<f32> = vec3<f32>(0.0, 0.4, 7.0);
const CORE_COL: vec3<f32> = vec3<f32>(1.0, 0.72, 0.5);

// --- UTILS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Simplex 3D Noise
fn mod289(x: vec3<f32>) -> vec3<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn mod289_4(x: vec4<f32>) -> vec4<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn permute(x: vec4<f32>) -> vec4<f32> { return mod289_4(((x*34.0)+1.0)*x); }
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> { return 1.79284291400159 - 0.85373472095314 * r; }

fn snoise(v: vec3<f32>) -> f32 {
    let C = vec2<f32>(1.0/6.0, 1.0/3.0);
    let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);

    var i = floor(v + dot(v, C.yyy));
    var x0 = v - i + dot(i, C.xxx);

    var g = step(x0.yzx, x0.xyz);
    var l = 1.0 - g;
    var i1 = min(g.xyz, l.zxy);
    var i2 = max(g.xyz, l.zxy);

    var x1 = x0 - i1 + C.xxx;
    var x2 = x0 - i2 + C.yyy;
    var x3 = x0 - D.yyy;

    i = mod289(i);
    var p = permute(permute(permute(
        i.z + vec4<f32>(0.0, i1.z, i2.z, 1.0))
      + i.y + vec4<f32>(0.0, i1.y, i2.y, 1.0))
      + i.x + vec4<f32>(0.0, i1.x, i2.x, 1.0));

    var n_ = 0.142857142857;
    var ns = n_ * D.wyz - D.xzx;

    var j = p - 49.0 * floor(p * ns.z * ns.z);

    var x_ = floor(j * ns.z);
    var y_ = floor(j - 7.0 * x_);

    var x = x_ *ns.x + ns.yyyy;
    var y = y_ *ns.x + ns.yyyy;
    var h = 1.0 - abs(x) - abs(y);

    var b0 = vec4<f32>(x.xy, y.xy);
    var b1 = vec4<f32>(x.zw, y.zw);

    var s0 = floor(b0)*2.0 + 1.0;
    var s1 = floor(b1)*2.0 + 1.0;
    var sh = -step(h, vec4<f32>(0.0));

    var a0 = b0.xzyw + s0.xzyw*sh.xxyy;
    var a1 = b1.xzyw + s1.xzyw*sh.zzww;

    var p0 = vec3<f32>(a0.xy, h.x);
    var p1 = vec3<f32>(a0.zw, h.y);
    var p2 = vec3<f32>(a1.xy, h.z);
    var p3 = vec3<f32>(a1.zw, h.w);

    var norm = taylorInvSqrt(vec4<f32>(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
    p0 = p0 * norm.x;
    p1 = p1 * norm.y;
    p2 = p2 * norm.z;
    p3 = p3 * norm.w;

    var m = max(0.6 - vec4<f32>(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), vec4<f32>(0.0));
    m = m * m;
    return 42.0 * dot(m*m, vec4<f32>(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

// Curl noise
fn snoiseVec3(x: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        snoise(x),
        snoise(x + vec3<f32>(43.2, 17.5, 93.1)),
        snoise(x + vec3<f32>(-21.7, 52.8, -43.5))
    );
}

fn curlNoise(p: vec3<f32>) -> vec3<f32> {
    // Central differences as a loop over the three axes (same stencil as six
    // unrolled snoiseVec3 taps, but the noise body is emitted twice, not six
    // times — the unrolled form never finished compiling on SwiftShader).
    let e = 0.01;
    var dfdx = vec3<f32>(0.0);
    var dfdy = vec3<f32>(0.0);
    var dfdz = vec3<f32>(0.0);
    for (var a = 0; a < 3; a++) {
        let off = vec3<f32>(f32(a == 0), f32(a == 1), f32(a == 2)) * e;
        let diff = snoiseVec3(p + off) - snoiseVec3(p - off);
        dfdx += diff * off.x / e;
        dfdy += diff * off.y / e;
        dfdz += diff * off.z / e;
    }
    let x = dfdy.z - dfdz.y;
    let y = dfdz.x - dfdx.z;
    let z = dfdx.y - dfdy.x;

    return normalize(vec3<f32>(x, y, z) / (2.0 * e));
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    let t = u.config.x;

    // Mouse Interaction
    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    let mouseWorld = vec3<f32>(mouse.x * 3.0, -mouse.y * 3.0, 0.0); // Simple projection
    let dMouse = distance(p, mouseWorld);

    let pull = smoothstep(2.0, 0.0, dMouse) * u.zoom_config.w;
    if (pull > 0.0) {
        // Vortex effect
        let pullDir = (p - mouseWorld) / max(dMouse, 0.001);
        var r = p.xy;
        let vAngle = pull * 2.0;
        let s = sin(vAngle);
        let c = cos(vAngle);
        let rot = mat2x2<f32>(c, -s, s, c);
        r = rot * r;
        p = vec3<f32>(r.x, r.y, p.z) - pullDir * pull * 0.5;
    }

    let complexity = u.zoom_params.x; // 0.5 - 4.0
    let width = u.zoom_params.y; // 0.01 - 0.2

    // Warp wavelength kept long against the 0.5 displacement: at HEAD's p * complexity
    // the warp folded every tube into sub-pixel speckle.
    var flow = p * complexity * 0.2 + t * 0.2;
    var curl = curlNoise(flow);

    // Add fBM turbulence
    // One turbulence octave (HEAD's 5x octave only fed the speckle; dropped for cost).
    curl += snoiseVec3(flow * 2.5) * 0.25;
    curl = normalize(curl);

    // SDF to "ribbons" or "tubes" along the curl noise
    // We approximate this by finding the distance to a grid of lines that have been perturbed by the curl noise.
    // A simpler volumetric approach is to evaluate density directly.
    // For SDF map, we can evaluate distance to the closest flow path.

    // Distance to the curl field itself (creating tubes)
    // Project position onto the flow direction
    let proj = dot(p, curl) * curl;
    let dLine = length(p - proj);

    // We use a periodic structure perturbed by the noise to create multiple ribbons
    let qWorld = p + curl * 0.5;
    let spacing = 1.5;
    var q = (fract(qWorld / spacing + 0.5) - 0.5) * spacing;

    // Per-thread identity from the grid cell
    let cell = floor(qWorld / spacing + 0.5);
    let phase = fract(sin(dot(cell, vec3<f32>(12.9898, 78.233, 37.719))) * 43758.5453) * TAU;

    // IDEA 1 — plucked-thread standing waves: each silk thread vibrates like a
    // string (node pattern along its length, own phase/direction). Bass plucks
    // it; the mouse vortex pulls the web taut and damps the vibration.
    let tension = clamp(pull, 0.0, 1.0);
    let pluckAmp = gPluck * (1.0 - 0.8 * tension);
    let standing = sin(qWorld.y * 2.2 + phase) * cos(t * 9.0 + phase);
    q = vec3<f32>(q.x - cos(phase) * pluckAmp * standing, q.y, q.z - sin(phase) * pluckAmp * standing);

    // IDEA 4 — vibrating-string envelope: a string oscillating faster than the
    // eye resolves is seen as its swept envelope, widest at the antinodes and
    // pinched at the nodes; the same silk spread wider glows dimmer.
    let env = abs(sin(qWorld.y * 2.2 + phase)) * pluckAmp * 1.6;
    gEnv = env / (env + width);

    // IDEA 2 — dew beads: periodic droplet swellings strung along the thread
    let bead = pow(0.5 + 0.5 * cos(qWorld.y * 7.0 + phase * 3.0), 12.0);
    gBead = bead;

    // Distance to ribbon surface
    var dRibbon = length(q.xz) - width * (1.0 + 1.8 * bead) - env;
    // Only ~75% of lattice columns carry a thread, so rays reach the void between
    // strands; empty columns return the distance to their cell wall + 0.1 (scaled
    // ≥ 0.06, outside the 0.05 accumulation shell, so empty cells leave no ghost walls).
    let colHash = fract(sin(dot(cell.xz, vec2<f32>(127.1, 311.7))) * 43758.5453);
    dRibbon = select(0.75 - max(abs(q.x), abs(q.z)) + 0.1, dRibbon, colHash < 0.75);

    // Material ID based on noise
    let matID = snoise(p * 0.5) * 0.5 + 0.5;

    return vec2<f32>(dRibbon * 0.6, matID); // 0.6 is a safe under-estimator for raymarching with heavy noise
}

// Get normal for lighting: tetrahedral 4-tap gradient in a loop so map() is
// emitted once here (HEAD's six unrolled taps blew up shader compilation).
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    var n = vec3<f32>(0.0);
    for (var i = 0; i < 4; i++) {
        let k = 2.0 * vec3<f32>(f32(((i + 3) >> 1) & 1), f32((i >> 1) & 1), f32(i & 1)) - 1.0;
        n += k * map(p + k * e).x;
    }
    return normalize(n);
}

// ACES Tone Mapping
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

struct SilkResult {
    rgb: vec3<f32>,
    a: f32,
    firstHit: f32,
};

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, audioPulse: f32, treble: f32) -> SilkResult {
    var dO = 0.0;
    var dS: vec2<f32>;
    var col = vec3<f32>(0.0);
    var accumDens = 0.0;
    var firstHit = -1.0;

    let iridescence = u.zoom_params.z; // 0.0 - 3.0

    for (var i = 0; i < 56; i++) {
        let p = ro + rd * dO;
        dS = map(p);
        let beadHere = gBead; // capture before getNormal re-evaluates map
        let envHere = gEnv;
        // Weight each sample by its step length so density no longer depends on
        // where the variable steps happen to land inside the shell.
        let stepLen = max(abs(dS.x), 0.03);
        let w = stepLen / 0.05;

        // Volumetric accumulation
        if (dS.x < 0.05) {
            let dens = (0.05 - dS.x) * 10.0 * (1.0 - 0.65 * envHere); // Density (IDEA 4: envelope spreads it thin)
            accumDens += dens * 0.05 * w;
            firstHit = select(firstHit, dO, firstHit < 0.0);

            // Color based on material ID and time
            let t = u.config.x;
            var baseCol = 0.5 + 0.5 * cos(t + dS.y * 6.28 + vec3<f32>(0.0, 2.0, 4.0));

            // Audio Pulse emission
            let emission = audioPulse * (0.5 + 0.5 * sin(dO * 5.0 - t * 10.0));
            baseCol += vec3<f32>(1.0, 0.2, 0.8) * emission * dens; // Magenta/gold flare

            // Pseudo-Iridescence / Fresnel
            let n = getNormal(p);
            let fre = pow(1.0 + dot(n, rd), 3.0);
            let iriCol = 0.5 + 0.5 * cos(fre * 10.0 + vec3<f32>(0.0, 2.0, 4.0));
            baseCol += iriCol * iridescence * fre;

            // Dew-bead glint: droplets catch starlight at grazing angles, treble sparkles
            baseCol += vec3<f32>(0.9, 0.95, 1.0) * beadHere * (0.25 + treble * 0.8) * (0.3 + fre * 1.5);

            // IDEA 3 — gossamer backlighting: silk is nearly invisible lit from the
            // front and flares when the light sits behind it. Henyey-Greenstein
            // forward scatter (g = 0.78) of the nebula core through each strand.
            let toCore = normalize(CORE_POS - p);
            let hgG = 0.78;
            let cosT = dot(rd, toCore);
            let hg = (1.0 - hgG * hgG) / pow(max(1.0 + hgG * hgG - 2.0 * hgG * cosT, 1e-3), 1.5) / (4.0 * PI);
            baseCol += CORE_COL * hg * (0.9 + audioPulse * 0.6);

            col += baseCol * dens * 0.1 * w * exp(-dO * 0.2); // Attenuation
        }

        if (accumDens > 0.95 || dO > 20.0) { break; }

        // Push forward, minimum step size to avoid getting stuck in negative space
        dO += stepLen;
    }

    return SilkResult(col, accumDens, firstHit);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) {
        return;
    }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = vec2<f32>(coords) / resolution;
    let base_uv = uv; // Keep for data textures
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;
    uv.y = -uv.y; // y=0 is the top row: flip so world up is screen up and the vortex sits under the cursor

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);

    // Simple pan based on time
    let t = u.config.x * 0.1;
    ro.x += sin(t);
    ro.y += cos(t);

    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);

    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Audio from plasmaBuffer (HEAD misread dataTextureC as frequency data)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.5);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.5);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.5);
    let audioSample = clamp(bass * 0.7 + mids * 0.4, 0.0, 1.5);
    let audioPulse = u.zoom_params.w * audioSample; // 0.0 - 3.0
    gPluck = (0.015 + bass * 0.09) * u.zoom_params.w;

    // Raymarch
    let result = raymarch(ro, rd, audioPulse, treble * u.zoom_params.w);

    // Background color (dark blue/purple void)
    var bg = max(vec3<f32>(0.01, 0.0, 0.03) - length(uv) * 0.01, vec3<f32>(0.0));
    // The backlighting core itself, a soft glow behind the web.
    let coreDir = normalize(CORE_POS - ro);
    bg += CORE_COL * pow(max(dot(rd, coreDir), 0.0), 60.0) * 0.35;

    // Composite
    var color = mix(bg, result.rgb, min(result.a, 1.0));

    // Bloom approximation
    color += result.rgb * 0.5;

    // IDEA 3 — silk afterglow: woven light lingers and fades toward violet
    // (trailing max, so it never accumulates past the live frame)
    let prev = textureLoad(dataTextureC, coords, 0);
    let decay = 0.9;
    let lingering = prev.rgb * decay * vec3<f32>(0.88, 0.8, 1.0);
    let linearOut = min(max(color, lingering), vec3<f32>(8.0));
    let density = clamp(max(min(result.a, 1.0), prev.a * decay), 0.0, 1.0);

    // Tone mapping (display only; A keeps linear)
    let display = aces(linearOut);

    // Semantic alpha: void floor 0.85 (HEAD's 0.05 let the white page show
    // through the whole void), raised to opaque by live silk and afterglow density
    let alpha = clamp(0.85 + min(result.a, 1.0) * 0.15 + density * 0.05, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(display, alpha));
    let depth = select(0.0, 1.0 - clamp(result.firstHit / 20.0, 0.0, 1.0), result.firstHit >= 0.0);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(linearOut, density));
}
