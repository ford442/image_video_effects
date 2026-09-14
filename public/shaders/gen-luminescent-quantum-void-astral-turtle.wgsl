// ═══════════════════════════════════════════════════════════════════
//  Luminescent Quantum-Void Astral-Turtle
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: carapace scute plates with glowing growth-ring annuli; counter-rotating flipper wake vortex rings
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
    zoom_params: vec4<f32>,  // .x = Fractal Detail, .y = Plasma Glow, .z = Void Density, .w = Acoustic Reactivity
    ripples: array<vec4<f32>, 50>,
};

// Per-frame audio / interaction state shared with map()
var<private> g_bass: f32 = 0.0;
var<private> g_mids: f32 = 0.0;
var<private> g_treble: f32 = 0.0;
var<private> g_held: f32 = 0.0;
var<private> g_shock: f32 = 0.0;

// PRNG
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash12(p), hash12(p + vec2<f32>(19.19, 7.31)));
}

// 2D Rotation
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise (value noise)
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n = mix(
        mix(
            mix(hash12(i.xy + vec2<f32>(0.0, 0.0) + i.z * vec2<f32>(17.0, 37.0)),
                hash12(i.xy + vec2<f32>(1.0, 0.0) + i.z * vec2<f32>(17.0, 37.0)), u.x),
            mix(hash12(i.xy + vec2<f32>(0.0, 1.0) + i.z * vec2<f32>(17.0, 37.0)),
                hash12(i.xy + vec2<f32>(1.0, 1.0) + i.z * vec2<f32>(17.0, 37.0)), u.x), u.y),
        mix(
            mix(hash12(i.xy + vec2<f32>(0.0, 0.0) + (i.z + 1.0) * vec2<f32>(17.0, 37.0)),
                hash12(i.xy + vec2<f32>(1.0, 0.0) + (i.z + 1.0) * vec2<f32>(17.0, 37.0)), u.x),
            mix(hash12(i.xy + vec2<f32>(0.0, 1.0) + (i.z + 1.0) * vec2<f32>(17.0, 37.0)),
                hash12(i.xy + vec2<f32>(1.0, 1.0) + (i.z + 1.0) * vec2<f32>(17.0, 37.0)), u.x), u.y), u.z);
    return n;
}

// fBm
fn fbm(p: vec3<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p_mut = p;
    for (var i = 0; i < octaves; i = i + 1) {
        v = v + a * noise(p_mut);
        p_mut = p_mut * 2.0 + shift;
        a = a * 0.5;
    }
    return v;
}

// SDFs
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// Native idea 1: carapace scutes with growth-ring annuli.
// Real turtle shells are tiled with keratin scutes; each scute lays down
// concentric annuli as it grows. Voronoi over the carapace top gives the
// plates; rings step outward from each plate's origin, seams glow.
// Returns vec3(annuli glow, seam glow, cell hash).
// ----------------------------------------------------------------
fn carapaceScutes(sp: vec3<f32>, detail: f32, t: f32) -> vec3<f32> {
    let q = sp.xz * vec2<f32>(1.4, 1.1);
    let n = floor(q);
    let f = fract(q);
    var f1 = 8.0;
    var f2 = 8.0;
    var cellH = 0.0;
    for (var j = -1; j <= 1; j = j + 1) {
        for (var i = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash22(n + g) * 0.8 + vec2<f32>(0.1);
            let dist = length(g + o - f);
            if (dist < f1) {
                f2 = f1;
                f1 = dist;
                cellH = hash12(n + g);
            } else if (dist < f2) {
                f2 = dist;
            }
        }
    }
    let seam = smoothstep(0.08, 0.0, f2 - f1);
    // Growth rings: density follows Fractal Detail; mids push a slow outward growth wave
    let ringCount = 4.0 + detail * 3.0;
    let ringPhase = f1 * ringCount * 6.2831 - t * 0.6 - g_mids * 2.0 + cellH * 6.2831;
    let ring = pow(0.5 + 0.5 * cos(ringPhase), 6.0);
    let annuli = ring * smoothstep(0.9, 0.2, f1) * (0.35 + g_mids * 0.5);
    return vec3<f32>(annuli, seam, cellH);
}

// ----------------------------------------------------------------
// Native idea 2: flipper wake vortex rings.
// Each front-flipper stroke sheds a vortex ring that drifts aft; the two
// flippers shed counter-rotating trains. Bass strengthens shedding, mouse
// hold drives a harder power-stroke.
// ----------------------------------------------------------------
fn flipperWake(tp: vec3<f32>, t: f32, side: f32) -> f32 {
    let q = tp - vec3<f32>(side * 1.7, 0.0, 0.9);
    let behind = -q.z;
    if (behind < -0.2 || behind > 3.5) { return 0.0; }
    let spacing = 0.75;
    let shed = behind - t * 0.9;
    let zc = (shed - spacing * floor(shed / spacing)) - spacing * 0.5;
    let expand = 0.18 + behind * 0.08;
    let swirl = atan2(q.y, q.x * side) + t * 3.0 * side;
    let torus = length(vec2<f32>(length(q.xy) - expand, zc * 1.4));
    let core = exp(-torus * 18.0) * (0.75 + 0.25 * sin(swirl * 3.0));
    let fade = smoothstep(3.5, 0.5, behind) * smoothstep(-0.2, 0.2, behind);
    return core * fade * (0.35 + g_bass * 0.6 + g_held * 0.4 + g_shock * 0.5);
}

struct MapResult {
    d: f32,
    mat: f32,
    glow: vec3<f32>,
    lp: vec3<f32>, // turtle-space position
}

fn map(pos: vec3<f32>, time: f32, audio: f32) -> MapResult {
    var res = MapResult(1000.0, 0.0, vec3<f32>(0.0), vec3<f32>(0.0));
    let t = time * 0.5;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouse_dist = length(mouse);
    var p = pos;

    // Orbital distortion from mouse
    let rotA = rot2D(mouse.x * 2.0);
    let rotB = rot2D(mouse.y * 2.0);
    let rotX = rot2D(mouse_dist * 5.0);
    let xz_new = rotX * p.xz;
    p = vec3<f32>(xz_new.x, p.y, xz_new.y);

    let xy_r = rotA * p.xy;
    p = vec3<f32>(xy_r.x, xy_r.y, p.z);
    let yz_r = rotB * p.yz;
    p = vec3<f32>(p.x, yz_r.x, yz_r.y);

    // Turtle Body
    var turtle_p = p;
    // Hovering motion
    turtle_p = turtle_p + vec3<f32>(0.0, sin(t * 2.0) * 0.2, 0.0);
    let yz_t = rot2D(sin(t)*0.1) * turtle_p.yz;
    turtle_p = vec3<f32>(turtle_p.x, yz_t.x, yz_t.y);
    res.lp = turtle_p;

    // Shell
    let frac_detail = u.zoom_params.x; // Fractal Detail
    let acoustic_react = u.zoom_params.w; // Acoustic Reactivity

    var shell_p = turtle_p;
    let shell_base = sdEllipsoid(shell_p, vec3<f32>(1.2, 0.5, 1.5));
    // fBm displacement for crystalline shell
    let shell_disp = fbm(shell_p * frac_detail + t, 4) * 0.3;
    let shell_audio_disp = audio * acoustic_react * fbm(shell_p * 10.0 - t * 5.0, 2) * 0.2;
    let d_shell = shell_base - shell_disp + shell_audio_disp;

    // Head
    var head_p = turtle_p - vec3<f32>(0.0, 0.1, 1.8);
    let d_head = sdEllipsoid(head_p, vec3<f32>(0.3, 0.25, 0.4));

    // Fins (mouse hold = stronger power-stroke)
    let stroke = 0.2 + g_held * 0.15;
    let beat = t * (3.0 + g_held * 1.5);
    // Front fins
    var fl_p = turtle_p - vec3<f32>(1.2, 0.0, 1.0);
    let xy_fl = rot2D(0.5 + sin(beat)*stroke) * fl_p.xy;
    fl_p = vec3<f32>(xy_fl.x, xy_fl.y, fl_p.z);
    let yz_fl = rot2D(-0.2) * fl_p.yz;
    fl_p = vec3<f32>(fl_p.x, yz_fl.x, yz_fl.y);
    let d_fl = sdEllipsoid(fl_p, vec3<f32>(0.8, 0.05, 0.3));

    var fr_p = turtle_p - vec3<f32>(-1.2, 0.0, 1.0);
    let xy_fr = rot2D(-0.5 - sin(beat)*stroke) * fr_p.xy;
    fr_p = vec3<f32>(xy_fr.x, xy_fr.y, fr_p.z);
    let yz_fr = rot2D(-0.2) * fr_p.yz;
    fr_p = vec3<f32>(fr_p.x, yz_fr.x, yz_fr.y);
    let d_fr = sdEllipsoid(fr_p, vec3<f32>(0.8, 0.05, 0.3));

    // Temporal rippling on fins
    let ripple = sin(turtle_p.x * 5.0 + t * 10.0) * 0.05 * audio * acoustic_react;
    let d_fins = smin(d_fl, d_fr, 0.2) + ripple;

    // Combine turtle parts
    let d_turtle_body = smin(d_head, d_fins, 0.3);
    let d_turtle = smin(d_shell, d_turtle_body, 0.2);

    res.d = d_turtle;
    res.mat = 1.0;

    // Quantum Core (inside shell)
    let d_core = sdSphere(turtle_p - vec3<f32>(0.0, 0.1, 0.0), 0.4) - audio * 0.2;
    if (d_core < res.d) {
        res.d = d_core;
        res.mat = 2.0;
    }

    // Plasma Glow mapping
    let pg = u.zoom_params.y;
    res.glow = vec3<f32>(0.0);
    if (d_shell < 0.5) {
        let emission = clamp(1.0 - d_shell*2.0, 0.0, 1.0) * pg;
        let c_base = vec3<f32>(0.2, 0.8, 1.0); // Cyan
        let c_peak = vec3<f32>(1.0, 0.2, 0.8); // Pink
        res.glow = mix(c_base, c_peak, clamp(audio * acoustic_react, 0.0, 1.0)) * emission;
    }

    // Flipper wake vortex rings (volumetric glow only)
    let wake = flipperWake(turtle_p, t, 1.0) + flipperWake(turtle_p, t, -1.0);
    res.glow = res.glow + vec3<f32>(0.35, 0.7, 1.0) * wake * (0.4 + pg * 0.4);

    return res;
}

// Raymarching
fn calcNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.001;
    return normalize(
        e.xyy * map(p + e.xyy, time, audio).d +
        e.yyx * map(p + e.yyx, time, audio).d +
        e.yxy * map(p + e.yxy, time, audio).d +
        e.xxx * map(p + e.xxx, time, audio).d
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let size = textureDimensions(writeTexture);
    if (id.x >= size.x || id.y >= size.y) { return; }

    let coord = vec2<i32>(id.xy);
    let time = u.config.x;

    g_bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    g_mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    g_treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    g_held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let audio = clamp(g_bass * 0.8 + g_mids * 0.2, 0.0, 1.0);

    let fragCoord = vec2<f32>(id.xy);
    let resolution = vec2<f32>(size);
    var uv = (fragCoord - 0.5 * resolution) / resolution.y;
    let screenUV = fragCoord / resolution;
    let aspect = resolution.x / resolution.y;

    // Click ripples: nebula shock rings + wake/shell flash
    var shock = 0.0;
    var ringGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rip = u.ripples[i];
        let age = time - rip.z;
        if (age >= 0.0 && age < 3.0) {
            shock = max(shock, exp(-age * 1.6));
            let dv = (screenUV - rip.xy) * vec2<f32>(aspect, 1.0);
            let ring = abs(length(dv) - age * 0.4);
            ringGlow = ringGlow + smoothstep(0.035, 0.0, ring) * exp(-age * 1.4);
        }
    }
    g_shock = shock;

    // Camera setup
    let ro = vec3<f32>(0.0, 2.0, -6.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching
    var t_dist = 0.0;
    var col = vec3<f32>(0.0);
    var accum_glow = vec3<f32>(0.0);

    let max_steps = 100;
    let max_dist = 20.0;
    let surf_dist = 0.001;

    var hit = false;
    var m = MapResult(0.0, 0.0, vec3<f32>(0.0), vec3<f32>(0.0));
    let void_dens = u.zoom_params.z;

    for (var i = 0; i < max_steps; i = i + 1) {
        let p = ro + rd * t_dist;
        m = map(p, time, audio);

        // Volumetric accumulation
        let v_noise = fbm(p * 0.5 - time * 0.2, 3);
        let vol_dens_local = max(0.0, v_noise - 0.5) * void_dens;
        accum_glow = accum_glow + m.glow * 0.02 + vec3<f32>(0.1, 0.05, 0.2) * vol_dens_local * 0.05 * (1.0 + audio * u.zoom_params.w * 0.5);

        if (abs(m.d) < surf_dist) {
            hit = true;
            break;
        }
        if (t_dist > max_dist) {
            break;
        }
        t_dist = t_dist + m.d * 0.5; // step safely
    }

    var alpha = 0.0;
    var depth = 0.0;

    if (hit) {
        let p = ro + rd * t_dist;
        let n = calcNormal(p, time, audio);
        let l = normalize(vec3<f32>(1.0, 2.0, -3.0));

        let dif = max(dot(n, l), 0.0);
        let amb = 0.1;
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        var mat_col = vec3<f32>(0.1, 0.1, 0.2); // Shell base
        if (m.mat == 2.0) {
            mat_col = vec3<f32>(1.0, 0.5, 0.8) * (1.0 + audio * 0.5); // Core
        }

        col = mat_col * (dif + amb) + vec3<f32>(0.5, 0.8, 1.0) * fresnel * u.zoom_params.y;

        // Scute plates with growth-ring annuli on the upper carapace
        if (m.mat == 1.0) {
            let lp = m.lp;
            let onShell = smoothstep(-0.15, 0.15, lp.y) * smoothstep(1.9, 1.5, length(lp.xz * vec2<f32>(1.0, 0.8)));
            let sc = carapaceScutes(lp, u.zoom_params.x, time);
            let tint = mix(vec3<f32>(0.25, 0.85, 1.0), vec3<f32>(0.95, 0.45, 0.9), sc.z);
            let scuteGlow = tint * sc.x * u.zoom_params.y * 0.6
                + vec3<f32>(1.0, 0.85, 0.5) * sc.y * (0.25 + g_treble * 0.35 + g_shock * 0.6);
            col = col * (1.0 - sc.y * 0.4 * onShell) + scuteGlow * onShell;
            alpha = alpha + (sc.x + sc.y) * 0.2 * onShell;
        }

        depth = clamp(1.0 - t_dist / max_dist, 0.0, 1.0);
        alpha = alpha + 0.6 + dif * 0.2 + fresnel * 0.2;
    }

    // Add accumulated glow and background
    col = col + accum_glow;
    col = col + vec3<f32>(0.4, 0.3, 0.9) * ringGlow * 0.3 * (0.5 + void_dens * 0.4);

    // Vignette
    col = col * (1.0 - length(uv) * 0.3);

    // Nebula persistence: exact previous-frame load
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    let pc = clamp(coord, vec2<i32>(0), dims - vec2<i32>(1));
    let previous = textureLoad(dataTextureC, pc, 0);
    col = mix(col, max(col, previous.rgb * 0.5), 0.3 + g_mids * 0.1);

    // Tonemapping
    col = acesToneMap(col * (1.1 + g_bass * 0.2));

    let glowAlpha = clamp(dot(accum_glow, vec3<f32>(0.3, 0.5, 0.2)) * 1.5 + ringGlow * 0.3, 0.0, 1.0);
    let finalAlpha = clamp(alpha + glowAlpha, 0.0, 1.0);
    let finalColor = vec4<f32>(col, finalAlpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
