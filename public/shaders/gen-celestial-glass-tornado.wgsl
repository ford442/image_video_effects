// ----------------------------------------------------------------
// Celestial Glass-Tornado
// Category: generative
// ----------------------------------------------------------------
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
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
    let mx = (u.zoom_config.y - 0.5) * 5.0;
    let my = (u.zoom_config.z - 0.5) * 5.0;
    let warp_dist = length(q.xy - vec2<f32>(mx, my));
    let pull = exp(-warp_dist * 1.5) * 2.0;

    // Audio reactive turbulence
    let audio_twist = u.zoom_params.w * u.config.y;
    let base_twist = u.zoom_params.x;

    // Twist the tornado
    q.xz = rot(q.y * (base_twist + audio_twist) + t) * q.xz;

    // Pull towards mouse
    q.xy = mix(q.xy, vec2<f32>(mx, my), pull * 0.2);

    // Tornado core
    var tornado = length(q.xz) - (1.0 + q.y * 0.2 + sin(q.y * 4.0 + t) * 0.2);

    // KIFS Debris
    var k = p;
    k.y += t * 2.0; // debris falling/rising
    k.xz = rot(t * 0.5) * k.xz;
    for (var i = 0; i < 4; i++) {
        k = abs(k) - vec3<f32>(0.5, 0.8, 0.5) * u.zoom_params.y;
        k.xy = rot(1.2) * k.xy;
        k.xz = rot(0.8) * k.xz;
    }
    let debris = length(k) - 0.1;

    // Blend debris into the tornado but keep it separate further out
    let final_dist = min(tornado, debris);

    return final_dist;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(id.xy) / texSize;
    if (uv.x > 1.0 || uv.y > 1.0) { return; }

    let res = vec2<f32>(u.config.z, u.config.w);
    let nuv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    var ro = vec3<f32>(0.0, 0.0, -8.0);
    var rd = normalize(vec3<f32>(nuv, 1.0));

    // Mouse camera sweep
    let mx = (u.zoom_config.y - 0.5) * 3.14 * 0.5;
    let my = (u.zoom_config.z - 0.5) * 3.14 * 0.5;
    rd.yz = rot(-my) * rd.yz;
    rd.xz = rot(-mx) * rd.xz;
    ro.yz = rot(-my) * ro.yz;
    ro.xz = rot(-mx) * ro.xz;

    var t = 0.0;
    var d = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > 40.0) { break; }
        t += d * 0.6; // Slightly slower march for detail
        glow += 0.005 / (0.01 + abs(d)) * (1.0 + u.config.y * u.zoom_params.w);
    }

    var col = vec4<f32>(0.0);
    if (t < 40.0) {
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
        col = vec4<f32>(rgb * glow, 1.0);
    } else {
        // Stellar background
        let bg = fract(sin(dot(rd, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
        let star = step(0.995, bg) * bg;
        col = vec4<f32>(vec3<f32>(star) + vec3<f32>(0.02, 0.01, 0.05) * glow, 1.0);
    }

    textureStore(writeTexture, vec2<i32>(id.xy), col);
}