// ----------------------------------------------------------------
// Quantum Coral Reef
// Category: generative
// Features: audio-reactive, mouse-driven, upgraded-rgba
// Upgraded: 2026-10-25
// Ideas: KIFS orbit trap (§12.2E) -> brain-coral growth ridges + hue split; SDF curvature (§12.2E) -> luminous convex polyp crowns, dark crevices; Beer-Lambert water column (§12.2F) -> red absorbed first, blue in-scatter
// A packing: ACES display RGBA (alpha = coverage / water translucency)
// ----------------------------------------------------------------
#include "_prelude.wgsl"

// ----------------------------------------------------------------
// Audio-reactive baseline map
// ----------------------------------------------------------------
fn getAudioReactiveParams() -> vec3<f32> {
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    return vec3<f32>(bass, mids, treble);
}

// ----------------------------------------------------------------
// Rotation Matrix
// ----------------------------------------------------------------
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ----------------------------------------------------------------
// Smooth Min
// ----------------------------------------------------------------
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0);
    return min(a, b) - h * h * 0.25 / k;
}

// ----------------------------------------------------------------
// 3D Simplex Noise approximation (cheap, smooth)
// ----------------------------------------------------------------
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

fn smoothNoise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (3.0 - 2.0 * f);

    let n = p.x + p.y * 57.0 + 113.0 * p.z;

    let res = mix(
        mix(
            mix(fract(sin(n + 0.0)*43758.5453), fract(sin(n + 1.0)*43758.5453), f2.x),
            mix(fract(sin(n + 57.0)*43758.5453), fract(sin(n + 58.0)*43758.5453), f2.x),
            f2.y
        ),
        mix(
            mix(fract(sin(n + 113.0)*43758.5453), fract(sin(n + 114.0)*43758.5453), f2.x),
            mix(fract(sin(n + 170.0)*43758.5453), fract(sin(n + 171.0)*43758.5453), f2.x),
            f2.y
        ),
        f2.z
    );
    return res;
}

// ----------------------------------------------------------------
// Global definitions
// ----------------------------------------------------------------
struct MapResult {
    d: f32,
    mat: f32,   // material id / glow mask
    trap: f32,  // Idea 1: KIFS orbit trap (min |q|/scale over the fold loop)
}

var<private> g_glow: f32 = 0.0;
var<private> g_time: f32 = 0.0;
var<private> g_mousePos: vec3<f32>;
const CAM_X: f32 = 4.0;
const CAM_Y: f32 = 4.0;

// ----------------------------------------------------------------
// Map / SDF
// ----------------------------------------------------------------
fn map(p_in: vec3<f32>) -> MapResult {
    var p = p_in;

    // User Params
    let paramScale = mix(0.5, 2.0, clamp(u.zoom_params.x, 0.0, 1.0)); // Zoom/Scale
    let paramComplexity = mix(1.0, 5.0, clamp(u.zoom_params.y, 0.0, 1.0)); // Detail
    let paramSpeed = mix(0.1, 2.0, clamp(u.zoom_params.z, 0.0, 1.0)); // Flow Speed
    let paramAudioInf = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0)); // Audio Reactivity

    // Audio
    let audio = getAudioReactiveParams();
    let pulse = audio.y * paramAudioInf;

    // Distortion field (mouse interaction)
    var distVal = 0.0;
    if (u.zoom_config.w > 0.5) {
        let diff = p - g_mousePos;
        let distSq = dot(diff, diff);
        distVal = smoothstep(4.0, 0.0, sqrt(distSq));

        let twistAxis = normalize(diff + vec3(0.001));

        // twist space
        let twAng = distVal * 2.0 * sin(g_time * 5.0);

        // simple rotation around arbitrary axis - approx via y and z
        let pxy = p.xy * rot2D(twAng * diff.z * 0.2);
        p = vec3<f32>(pxy, p.z);
        let pxz = p.xz * rot2D(twAng * diff.y * 0.2);
        p = vec3<f32>(pxz.x, p.y, pxz.y);
    }

    // Domain Repetition
    let spacing = 8.0;
    let id = floor((p + spacing * 0.5) / spacing);
    p = (fract(p / spacing + 0.5) - 0.5) * spacing;

    // Perturb the position slightly with noise
    let noiseVal = smoothNoise3(p * 0.5 + g_time * paramSpeed);
    p += vec3<f32>(noiseVal * 0.5);

    // KIFS fractal core
    var q = p;
    var scale = 1.0;
    var trap = 1e3;

    for(var i: i32 = 0; i < i32(paramComplexity); i = i + 1) {
        q = abs(q) - vec3<f32>(1.2, 0.8, 1.0) * (0.8 + 0.2*pulse);
        let qxy = q.xy * rot2D(0.5 + g_time * 0.1);
        q = vec3<f32>(qxy, q.z);
        let qxz = q.xz * rot2D(0.3 - g_time * 0.05);
        q = vec3<f32>(qxz.x, q.y, qxz.y);

        // ── Idea 1: orbit trap (§12.2E) — scale-compensated distance of the folded point to the origin
        trap = min(trap, length(q) / scale);

        let k = 1.5;
        q *= k;
        scale *= k;
    }

    // Base shape is a sphere/tube mix
    let dCore = (length(q) - 1.5) / scale;

    // Soften and add organic bumps
    let detailNoise = smoothNoise3(q * 2.0) / scale;
    let d = dCore - detailNoise * 0.5;

    // Bioluminescence Mask
    // High near edges, or near the mouse distVal
    let glowMask = smoothstep(0.1, -0.2, d) + distVal * 0.5 + pulse * 0.3;

    // Accumulate global glow (cheap volumetric trick)
    g_glow += max(0.0, 0.02 / (abs(d) + 0.01)) * glowMask;

    var res: MapResult;
    res.d = d * 0.8; // conservative step
    res.mat = glowMask;
    res.trap = trap;
    return res;
}

// ----------------------------------------------------------------
// Normal + curvature (Idea 2: SDF curvature, §12.2E)
// xyz = normal, w = kappa ~ (sum d(p +- e axis) - 6 d) / e^2  (> 0 convex tip, < 0 crevice)
// map() accumulates g_glow, so the taps are made glow-neutral.
// ----------------------------------------------------------------
fn calcNormalCurv(p: vec3<f32>) -> vec4<f32> {
    let glow0 = g_glow;
    let e = 0.03;
    let d0 = map(p).d;
    let dxp = map(p + vec3<f32>(e, 0.0, 0.0)).d;
    let dxn = map(p - vec3<f32>(e, 0.0, 0.0)).d;
    let dyp = map(p + vec3<f32>(0.0, e, 0.0)).d;
    let dyn = map(p - vec3<f32>(0.0, e, 0.0)).d;
    let dzp = map(p + vec3<f32>(0.0, 0.0, e)).d;
    let dzn = map(p - vec3<f32>(0.0, 0.0, e)).d;
    g_glow = glow0;
    let n = normalize(vec3<f32>(dxp - dxn, dyp - dyn, dzp - dzn) + vec3<f32>(1e-6));
    let kappa = (dxp + dxn + dyp + dyn + dzp + dzn - 6.0 * d0) / (e * e);
    return vec4<f32>(n, kappa);
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let coord = vec2<f32>(global_id.xy);
    if (coord.x >= dims.x || coord.y >= dims.y) { return; }

    g_time = u.config.x;
    let uv = (coord - 0.5 * dims) / min(dims.x, dims.y);

    // Mouse coords mapping
    let mouseUV = u.zoom_config.yz;
    let m = (mouseUV - 0.5) * vec2<f32>(dims.x/min(dims.x,dims.y), dims.y/min(dims.x,dims.y));

    // Camera setup
    // HEAD fix: the camera started inside the solid (every ray hit at t~0 -> flat crumpled wash).
    // It now flies down the open lane between reef columns (cell corner), upright (rd.y = -uv.y).
    let ro = vec3<f32>(CAM_X, CAM_Y, -5.0 + g_time * mix(0.5, 2.0, u.zoom_params.z));
    var rd = normalize(vec3<f32>(uv.x, -uv.y, 1.0));

    // Slight camera sway
    let rdxz = rd.xz * rot2D(sin(g_time * 0.2) * 0.2);
    rd = vec3<f32>(rdxz.x, rd.y, rdxz.y);
    let rdxy = rd.xy * rot2D(cos(g_time * 0.15) * 0.1);
    rd = vec3<f32>(rdxy, rd.z);

    // Determine 3D mouse pos for interaction
    // We assume the interaction point is at a fixed depth in front of the camera
    g_mousePos = ro + normalize(vec3<f32>(m.x, -m.y, 1.0)) * 5.0;

    // Raymarching
    var t = 0.0;
    let maxDist = 30.0;
    let maxIter = 80;
    var hit = false;
    var mRes: MapResult;
    mRes.d = 1.0; mRes.mat = 0.0; mRes.trap = 1.0;

    for(var i = 0; i < maxIter; i = i + 1) {
        let p = ro + rd * t;
        mRes = map(p);
        if(mRes.d < 0.001) { hit = true; break; }
        t += mRes.d;
        if(t > maxDist) { break; }
    }

    // Shading
    var col = vec3<f32>(0.005, 0.02, 0.05); // deep ocean background
    col += rd.y * 0.02; // slight depth gradient

    if (hit) {
        let p = ro + rd * t;
        let nk = calcNormalCurv(p);
        let n = nk.xyz;

        let lightDir = normalize(vec3<f32>(0.5, 1.0, -0.5));
        let diff = max(dot(n, lightDir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Base coral color
        var baseCol = vec3<f32>(0.1, 0.3, 0.4);

        // Bioluminescence mapping
        let bioColor1 = vec3<f32>(0.0, 1.0, 0.8); // Cyan
        let bioColor2 = vec3<f32>(1.0, 0.1, 0.5); // Neon Pink
        // ── Idea 1: orbit-trap growth ridges (§12.2E) — contour lines of the KIFS trap read as
        // brain-coral ridges, and split the cyan/pink hue so colonies are banded, not just noisy.
        let ridgePhase = abs(fract(mRes.trap * 7.0) - 0.5) * 2.0;     // 0 on a ridge crest, 1 in a groove
        let ridge = 1.0 - smoothstep(0.0, 0.35, ridgePhase);
        let hueSel = clamp(mix(smoothNoise3(p * 0.2 + g_time), fract(mRes.trap * 3.0), 0.5), 0.0, 1.0);
        let bioColor = mix(bioColor1, bioColor2, hueSel);

        let glowIntens = mRes.mat * 2.0;
        baseCol = mix(baseCol, bioColor, glowIntens);

        // ── Idea 2: SDF curvature (§12.2E) — convex polyp crowns light up, crevices fall into shadow
        let convex = clamp(nk.w * 0.06, 0.0, 1.0);
        let concave = clamp(-nk.w * 0.06, 0.0, 1.0);

        col = baseCol * (diff * 0.5 + 0.1) * (1.0 - 0.55 * concave);
        col += bioColor * fresnel * 0.8;
        col += bioColor * glowIntens;
        col += bioColor * ridge * (0.12 + 0.25 * glowIntens);
        col += mix(bioColor, vec3<f32>(1.0), 0.35) * convex * (0.25 + 0.5 * glowIntens);

        // ── Idea 3: Beer-Lambert water column (§12.2F) — red goes first, then green; the
        // lost light is replaced by blue in-scatter (replaces the linear smoothstep fog).
        let sigma = vec3<f32>(0.11, 0.045, 0.02);
        let trans = exp(-sigma * t);
        col = col * trans + vec3<f32>(0.005, 0.02, 0.05) * (vec3<f32>(1.0) - trans);
    }

    // Global emissive glow accumulation
    col += vec3<f32>(0.1, 0.5, 0.8) * g_glow * 0.02;

    // Audio particle/blooming response (screenspace effect)
    let audio = getAudioReactiveParams();
    let trebleBloom = audio.z * 0.1 * u.zoom_params.w;
    col += vec3<f32>(1.0, 0.5, 0.2) * trebleBloom * smoothstep(1.0, 0.0, length(uv));

    // ACES Tonemapping (clamped input: the catalog ACES fit maps negatives to bright)
    col = max(col, vec3<f32>(0.0));
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    col = clamp((col * (a * col + b)) / (col * (c * col + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));

    // Semantic alpha: solid coral is opaque, open water is translucent and glows with the accumulated bloom.
    let alpha = select(clamp(0.45 + g_glow * 0.02, 0.45, 0.85), 1.0, hit);
    let outPix = vec2<i32>(global_id.xy);
    textureStore(writeTexture, outPix, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, outPix, vec4<f32>(select(0.0, 1.0 - clamp(t / maxDist, 0.0, 1.0), hit), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, outPix, vec4<f32>(col, alpha));
}
