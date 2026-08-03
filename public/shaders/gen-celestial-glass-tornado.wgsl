// ═══════════════════════════════════════════════════════════════════
//  Celestial Glass-Tornado
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-03 (Batch 34)
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
    zoom_params: vec4<f32>,  // UI Sliders mapped here
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p: vec3<f32>) -> f32 {
    var q = p;
    let t = u.config.x * 0.5;

    // Mouse anomaly
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouse = select(rawMouse, vec2<f32>(extraBuffer[133], extraBuffer[134]), extraBuffer[137] > 0.5);
    let mx = (mouse.x - 0.5) * 5.0;
    let my = (mouse.y - 0.5) * 5.0;
    let warp_dist = length(q.xy - vec2<f32>(mx, my));
    let pull = exp(-warp_dist * 1.5) * 2.0;

    // Audio reactive turbulence (bass drives the twist intensity)
    let audio_twist = u.zoom_params.w * plasmaBuffer[0].x;
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
    var tornado = length(q.xz) - (1.0 + q.y * 0.2 + sin(q.y * 4.0 + t) * 0.2);

    // KIFS Debris
    var k = p;
    k.y += t * 2.0; // debris falling/rising
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

    // Blend debris into the tornado but keep it separate further out
    let final_dist = min(tornado, debris);

    return final_dist;
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

    // Audio reactivity: mids feed glow accumulation, treble adds star twinkle
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
        d = map(p);
        if (d < 0.001) { hit = true; break; }
        if (t > 40.0) { break; }
        t += max(abs(d) * 0.6, 0.002); // Never march backward inside glass folds.
        glow += 0.005 / (0.01 + abs(d)) * (1.0 + mids * u.zoom_params.w);
    }

    var col = vec3<f32>(0.0);
    var alpha = 0.0;
    if (hit) {
        let p = ro + rd * t;
        // Simulating chromatic split
        let split = u.zoom_params.z * 0.1;
        let r_d = map(p + vec3<f32>(split, 0.0, 0.0));
        let g_d = map(p + vec3<f32>(0.0, split, 0.0));
        let b_d = map(p + vec3<f32>(0.0, 0.0, split));

        let rgb = vec3<f32>(
            mix(0.1, 1.0, 1.0 / (1.0 + r_d * 50.0)),
            mix(0.1, 1.0, 1.0 / (1.0 + g_d * 50.0)),
            mix(0.1, 1.0, 1.0 / (1.0 + b_d * 50.0))
        );
        col = rgb * glow;
        // Alpha: glass tornado opacity from accumulated glow
        alpha = clamp(0.3 + glow * 0.5, 0.0, 1.0);
    } else {
        // Stellar background
        let bg = fract(sin(dot(rd, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
        let star = step(0.995, bg) * bg * (1.0 + treble * 1.5); // treble twinkle
        col = vec3<f32>(star) + vec3<f32>(0.02, 0.01, 0.05) * glow;
        // Alpha: faint stars + glow haze, never flat 1.0
        alpha = clamp(star + glow * 0.1, 0.0, 1.0);
    }

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
    // Depth: tornado hit distance; background sits at far plane
    let depth = select(0.0, clamp(1.0 - t / 40.0, 0.0, 1.0), hit);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
