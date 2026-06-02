// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Chrono-Mycelium Engine
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-31
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
    zoom_params: vec4<f32>,  // x=Mycelial Density, y=Plasma Glow, z=Temporal Warp, w=Unused
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

fn rotate3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let ic = 1.0 - c;
    let a = normalize(axis);
    return mat3x3<f32>(
        vec3<f32>(a.x * a.x * ic + c, a.y * a.x * ic - a.z * s, a.z * a.x * ic + a.y * s),
        vec3<f32>(a.x * a.y * ic + a.z * s, a.y * a.y * ic + c, a.z * a.y * ic - a.x * s),
        vec3<f32>(a.x * a.z * ic - a.y * s, a.y * a.z * ic + a.x * s, a.z * a.z * ic + c)
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var pos = p;
    for(var i = 0; i < 4; i++) {
        v += sin(pos.x + sin(pos.y + sin(pos.z))) * amp;
        pos *= 2.0;
        amp *= 0.5;
    }
    return v;
}

fn sdf_gear(p: vec3<f32>) -> f32 {
    var pos = p;
    pos = rotate3D(vec3<f32>(0.0, 1.0, 0.0), u.config.x * 0.5) * pos;
    for(var i = 0; i < 4; i++) {
        pos = vec3<f32>(abs(pos.x), abs(pos.y), abs(pos.z)) - vec3<f32>(0.2);
        pos = rotate3D(vec3<f32>(1.0, 1.0, 1.0), 0.5) * pos;
    }
    return length(pos) - 0.5;
}

fn sdf_mycelium(p: vec3<f32>) -> f32 {
    var pos = p;
    let density = u.zoom_params.x; // Mycelial Density
    let audio_react = plasmaBuffer[0].x * 0.5; // bass swells the hyphae

    let warp = u.zoom_params.z;
    let mouse_offset = vec2<f32>((u.zoom_config.y - 0.5) * 2.0, (u.zoom_config.z - 0.5) * 2.0);
    pos.x += sin(pos.y * warp + u.config.x) * mouse_offset.x;
    pos.y += sin(pos.x * warp + u.config.x) * mouse_offset.y;

    let noise = fbm(pos * density + vec3<f32>(u.config.x)) * (0.5 + audio_react);
    return length(vec2<f32>(pos.x, pos.z)) - 0.1 - noise * 0.2;
}

fn smooth_min(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn map(p: vec3<f32>) -> f32 {
    let d_gear = sdf_gear(p);
    let d_mycelium = sdf_mycelium(p);
    return smooth_min(d_gear, d_mycelium, 0.5);
}

fn calc_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    // Audio reactivity: mids brighten plasma glow, treble adds shimmer
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = (fragCoord - 0.5 * res) / res.y;
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var d = 0.0;
    var p = ro;

    for(var i = 0; i < 100; i++) {
        p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    let plasma_glow = u.zoom_params.y * (1.0 + mids * 0.6); // Plasma Glow, mid-reactive
    let hit = t < 20.0;
    var lum = 0.0;

    if (hit) {
        let n = calc_normal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let glow = fbm(p * 5.0 - vec3<f32>(u.config.x * 2.0)) * plasma_glow;

        let gear_color = vec3<f32>(0.2, 0.2, 0.3) * diff;
        let mycelium_color = vec3<f32>(0.0, 1.0, 1.0) * glow * diff + vec3<f32>(1.0, 0.0, 1.0) * (1.0-glow) * diff;

        col = mix(gear_color, mycelium_color, smoothstep(0.0, 1.0, length(p)));
        col += vec3<f32>(0.8, 0.9, 1.0) * abs(glow) * treble * 0.15; // treble sparkle
        lum = clamp(diff + abs(glow) * 0.5, 0.0, 1.0);
    }

    // Alpha: lit mycelium/gear coverage over the void, never flat 1.0
    let alpha = clamp(select(0.0, 0.3, hit) + lum * 0.6, 0.0, 1.0);
    let out = vec4<f32>(col, alpha);

    // Depth: ray-march hit distance (near = closer)
    let depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    let coord = vec2<i32>(id.xy);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
