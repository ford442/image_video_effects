// ═══════════════════════════════════════════════════════════════════
//  gen-celestial-glass-tornado
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, spring-dynamics, depth-aware
//  Ideas: Cauchy prismatic facet TIR glints, helical plasma funnel discharge arcs, centrifugal glass dust accretion disk
//  A packing: display RGBA (RGB=ACES tone-mapped glass tornado, A=glow opacity)
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
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Vortex Twist, y=Debris Density, z=Chromatic Split, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p: vec3<f32>, mouse: vec2<f32>) -> f32 {
    var q = p;
    let t = u.config.x * 0.5;

    let mx = (mouse.x - 0.5) * 5.0;
    let my = (mouse.y - 0.5) * 5.0;
    let warp_dist = length(q.xy - vec2<f32>(mx, my));
    let pull = exp(-warp_dist * 1.5) * 2.0;

    // Audio reactive turbulence
    let audio_twist = u.zoom_params.w * plasmaBuffer[0].x * 0.8;
    let base_twist = u.zoom_params.x;

    // Twist the tornado
    let q_xz = rot(q.y * (base_twist + audio_twist) + t) * q.xz;
    q.x = q_xz.x;
    q.z = q_xz.y;

    // Pull towards mouse
    let q_xy = mix(q.xy, vec2<f32>(mx, my), pull * 0.2);
    q.x = q_xy.x;
    q.y = q_xy.y;

    // Tornado core
    let tornado = length(q.xz) - (1.0 + q.y * 0.2 + sin(q.y * 4.0 + t) * 0.2);

    // KIFS Crystalline Debris
    var k = p;
    k.y += t * 2.0;
    let k_xz = rot(t * 0.5) * k.xz;
    k.x = k_xz.x;
    k.z = k_xz.y;
    for (var i = 0; i < 4; i++) {
        k = abs(k) - vec3<f32>(0.5, 0.8, 0.5) * u.zoom_params.y;
        let k_xy = rot(1.2) * k.xy;
        k.x = k_xy.x;
        k.y = k_xy.y;
        let k_xz2 = rot(0.8) * k.xz;
        k.x = k_xz2.x;
        k.z = k_xz2.y;
    }
    let debris = length(k) - 0.1;

    return min(tornado, debris);
}

fn calcNormal(p: vec3<f32>, mouse: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, mouse) - map(p - e.xyy, mouse),
        map(p + e.yxy, mouse) - map(p - e.yxy, mouse),
        map(p + e.yyx, mouse) - map(p - e.yyx, mouse)
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
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }
    let res = vec2<f32>(dims);
    let uv = (vec2<f32>(id.xy) + vec2<f32>(0.5)) / res;
    let nuv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Single-writer spring-damper cursor in extraBuffer[133..138]
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

    var ro = vec3<f32>(0.0, 0.0, -8.0);
    var rd = normalize(vec3<f32>(nuv, 1.0));

    // Mouse camera sweep
    let mx = (mouse.x - 0.5) * 3.14 * 0.5;
    let my = (mouse.y - 0.5) * 3.14 * 0.5;
    let rd_yz = rot(-my) * rd.yz;
    rd.y = rd_yz.x;
    rd.z = rd_yz.y;
    let rd_xz = rot(-mx) * rd.xz;
    rd.x = rd_xz.x;
    rd.z = rd_xz.y;
    let ro_yz = rot(-my) * ro.yz;
    ro.y = ro_yz.x;
    ro.z = ro_yz.y;
    let ro_xz = rot(-mx) * ro.xz;
    ro.x = ro_xz.x;
    ro.z = ro_xz.y;

    var t = 0.0;
    var d = 0.0;
    var glow = 0.0;
    var hit = false;

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        d = map(p, mouse);
        if (d < 0.001) { hit = true; break; }
        if (t > 40.0) { break; }
        t += max(abs(d) * 0.6, 0.002);
        glow += 0.005 / (0.01 + abs(d)) * (1.0 + mids * u.zoom_params.w);
    }

    var col = vec3<f32>(0.0);
    var alpha = 0.0;
    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p, mouse);
        let v = -rd;
        let cosi = max(dot(n, v), 0.0);

        // IDEA 1: Cauchy prismatic glass facet TIR glints
        let split = u.zoom_params.z * 0.15;
        let r_d = map(p + n * split, mouse);
        let g_d = map(p, mouse);
        let b_d = map(p - n * split, mouse);

        let rgb = vec3<f32>(
            mix(0.1, 1.0, 1.0 / (1.0 + r_d * 50.0)),
            mix(0.1, 1.0, 1.0 / (1.0 + g_d * 50.0)),
            mix(0.1, 1.0, 1.0 / (1.0 + b_d * 50.0))
        );

        let fresnel = pow(1.0 - cosi, 3.0);
        let reflDir = reflect(rd, n);
        let glint = pow(max(dot(reflDir, normalize(vec3<f32>(0.0, 1.0, -0.5))), 0.0), 32.0);
        let thinFilm = 0.5 + 0.5 * cos(cosi * 12.0 + vec3<f32>(0.0, 2.094, 4.188));

        col = rgb * glow + thinFilm * fresnel * 0.6 + vec3<f32>(1.2, 1.3, 1.5) * glint * (1.0 + treble * 1.5);
        alpha = clamp(0.35 + glow * 0.5 + fresnel * 0.3, 0.0, 1.0);
    } else {
        let bg = fract(sin(dot(rd, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
        let star = step(0.995, bg) * bg * (1.0 + treble * 1.5);
        col = vec3<f32>(star) + vec3<f32>(0.02, 0.01, 0.05) * glow;
        alpha = clamp(star + glow * 0.1, 0.0, 1.0);
    }

    // IDEA 2: Helical plasma funnel discharge arcs
    // Arcs spiral down the tornado center driven by bass
    let funnelRadius = length(nuv);
    let funnelAngle = atan2(nuv.y, nuv.x);
    let helicalArc = sin(funnelAngle * 3.0 + funnelRadius * 20.0 - time * 8.0);
    let arcDischarge = pow(max(helicalArc, 0.0), 16.0) * exp(-funnelRadius * 2.5) * bass * u.zoom_params.w;
    col += vec3<f32>(0.4, 0.85, 1.4) * arcDischarge * 2.0;

    // IDEA 3: Centrifugal glass dust accretion disk
    // Equatorial disc at the bottom of the vortex scattering starlight
    let diskDist = abs(nuv.y + 0.35);
    let diskRing = smoothstep(0.08, 0.0, diskDist) * smoothstep(0.1, 0.6, abs(nuv.x));
    let dustNoise = fract(sin(dot(uv * 180.0, vec2<f32>(37.1, 89.3))) * 43758.5453);
    let accretionDust = dustNoise * diskRing * (0.3 + mids * 0.4);
    col += vec3<f32>(0.7, 0.5, 0.9) * accretionDust;

    // Click glass shatter rings
    var clickGlass = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let delta = (uv - ripple.xy) * vec2<f32>(res.x / res.y, 1.0);
            let radius = length(delta);
            let ring = exp(-abs(radius - age * 0.24) * 72.0) * exp(-age * 1.5);
            let shards = pow(max(cos(atan2(delta.y, delta.x) * 10.0 + age * 4.0), 0.0), 14.0);
            clickGlass = max(clickGlass, ring * (0.65 + shards * 0.55));
        }
    }
    col += vec3<f32>(0.35, 0.8, 1.4) * clickGlass * (0.7 + treble * 0.3);
    alpha = max(alpha, clickGlass * 0.42);

    let coord = vec2<i32>(id.xy);
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(col, prev.rgb * 0.9, clamp(0.025 + mids * 0.01, 0.0, 0.06));
    let out = vec4<f32>(acesToneMap(max(col, vec3<f32>(0.0)) * 1.1), clamp(alpha, 0.0, 0.96));
    let depth = select(0.0, clamp(1.0 - t / 40.0, 0.0, 1.0), hit);

    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
