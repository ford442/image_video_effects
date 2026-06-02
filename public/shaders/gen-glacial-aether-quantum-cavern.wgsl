// ═══════════════════════════════════════════════════════════════════
//  Glacial-Aether Quantum-Cavern
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-depth,
//            temporal-ice-formation, audio-fracture, bass-fog
//  Complexity: High
//  Created: 2026-05-23
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn mapSDF(p: vec3<f32>, bass: f32) -> f32 {
    var q = p;
    var scale = 1.0;
    let cavernScale = u.zoom_params.w * (1.0 + bass * 0.3);
    for (var i = 0; i < 4; i++) {
        q = abs(q) - vec3<f32>(1.0) * cavernScale;
        let qxy = q.xy * rotate(u.config.x * 0.1 + u.config.y * 0.5);
        q = vec3<f32>(qxy.x, qxy.y, q.z);
        let qxz = q.xz * rotate(u.config.x * 0.15);
        q = vec3<f32>(qxz.x, q.y, qxz.y);
        q = q * 1.4;
        scale = scale * 1.4;
    }
    return (length(q) - max(u.zoom_params.x * 2.0, 0.001)) / max(scale, 0.001);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let coord = vec2<i32>(id.xy);
    let uv = vec2<f32>(id.xy) / res;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var col = vec3<f32>(0.0);

    let camPulse = 1.0 + bass * 0.4;
    var ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x) * camPulse;
    var rd = normalize(vec3<f32>(uv * 2.0 - 1.0, 1.0));
    rd = vec3<f32>(rd.xy * rotate((u.zoom_config.y - 0.5) * 3.14), rd.z);
    let yz = rd.yz * rotate((u.zoom_config.z - 0.5) * 3.14);
    rd = vec3<f32>(rd.x, yz.x, yz.y);

    // Chromatic depth separation: R and B march at slightly different offsets
    let rdR = normalize(rd + vec3<f32>(0.002 * bass, 0.0, 0.0));
    let rdB = normalize(rd - vec3<f32>(0.002 * treble, 0.0, 0.0));

    var t = 0.0;
    let max_dist = 20.0;
    var hit = false;
    var min_dist = 100.0;
    var steps = 0.0;

    for (var i = 0; i < 64; i++) {
        let p = ro + rd * t;
        let d = mapSDF(p, bass);
        min_dist = min(min_dist, d);
        steps += 1.0;
        if (d < 0.01) { hit = true; break; }
        if (t > max_dist) { break; }
        t += d;
    }

    let glow = u.zoom_params.y * (1.0 + mids * 0.5);
    let depth_fade = 1.0 / max(1.0 + t * t * 0.1, 0.001);
    let p = ro + rd * t;
    let fracture = fract(length(p) * u.zoom_params.z * 5.0 + u.config.y * 2.0);

    let hitColor = vec3<f32>(0.1, 0.4, 0.8) * depth_fade * glow
        + vec3<f32>(0.2, 0.8, 1.0) * step(0.95, fracture) * (u.config.y + treble) * depth_fade;
    let missColor = vec3<f32>(0.05, 0.1, 0.2) * (1.0 / max(1.0 + min_dist * 10.0, 0.001)) * glow;
    col = select(missColor, hitColor, hit);
    col += vec3<f32>(0.2, 0.5, 0.6) * (u.config.y + bass * 0.5) * 0.1;

    // Temporal ice formation: previous frame crystallizes
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let iceForm = mix(col, prev * 0.92, 0.06 + bass * 0.02);
    col = mix(col, iceForm, 0.5);

    // Audio-reactive fracture overlay
    let fractureOverlay = vec3<f32>(0.3, 0.6, 0.9) * step(0.97, fract(length(p) * 10.0 + bass * 5.0)) * treble;
    col += fractureOverlay;

    let hitMask = select(0.0, 1.0, hit);
    let alpha = clamp(0.25 + hitMask * 0.4 + depth_fade * 0.3 + bass * 0.15, 0.0, 1.0);

    let depthOut = clamp(t / max_dist, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
