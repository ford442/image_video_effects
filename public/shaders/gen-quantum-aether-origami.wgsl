// ----------------------------------------------------------------
// Quantum Aether-Origami
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    zoom_params: vec4<f32>,  // x=Fold Complexity, y=Crease Glow, z=Audio Reactivity, w=Interference Shift
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// --- Core SDFs & KIFS Folding ---
fn fold(p: vec3<f32>, normal: vec3<f32>, distance: f32) -> vec3<f32> {
    let t = dot(p, normal) - distance;
    return p - 2.0 * min(0.0, t) * normal;
}

fn map(p: vec3<f32>) -> f32 {
    var q = p;

    // Iterative KIFS folding logic
    let audio = u.config.y * u.zoom_params.z;
    let iters = i32(u.zoom_params.x);

    let t1 = u.config.x * 0.2 + audio * 0.5;
    let t2 = u.config.x * 0.15;

    let n1 = normalize(vec3<f32>(1.0, 1.0, 0.0));
    let n2 = normalize(vec3<f32>(0.0, 1.0, 1.0));
    let n3 = normalize(vec3<f32>(1.0, 0.0, 1.0));

    var scale = 1.0;

    for (var i = 0; i < 10; i++) {
        if (i >= iters) { break; }

        q = fold(q, n1, 0.1 * sin(t1));
        q = fold(q, n2, 0.1 * cos(t2));
        q = fold(q, n3, 0.05);

        var xy = rot(0.5) * vec2<f32>(q.x, q.y);
        q.x = xy.x; q.y = xy.y;

        var yz = rot(0.3) * vec2<f32>(q.y, q.z);
        q.y = yz.x; q.z = yz.y;

        q = abs(q) - vec3<f32>(0.2, 0.2, 0.2);

        scale *= 1.2;
        q *= 1.2;
    }

    // Base structure (e.g., thin box)
    return (length(max(abs(q) - vec3<f32>(1.0, 1.0, 0.05), vec3<f32>(0.0))) - 0.01) / scale;
}

// Thin-film interference palette
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

// --- Main Render Loop ---
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = textureDimensions(writeTexture);
    let uv = vec2<f32>(id.xy) / vec2<f32>(texSize);

    if (id.x >= texSize.x || id.y >= texSize.y) { return; }

    let res = vec2<f32>(texSize);
    let centered_uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;
    let mouse = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) - 0.5 * res) / res.y;
    let mouse_dist = length(centered_uv - mouse);
    let fold_factor = smoothstep(0.0, 0.5, mouse_dist);

    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(centered_uv, 1.0));

    var t = 0.0;
    var p = ro;
    var hit = false;
    var min_dist = 999.0;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;

        // Mouse flattening interpolation
        let orig_d = map(p);
        let flat_d = p.z; // Simple plane
        let d = mix(flat_d, orig_d, fold_factor);

        min_dist = min(min_dist, d);

        if (abs(d) < 0.001) {
            hit = true;
            break;
        }
        if (t > 15.0) { break; }
        t += d;
    }

    var color = vec4<f32>(0.0);

    if (hit) {
        // Calculate normal with flattening factor included
        let e = vec2<f32>(0.001, 0.0);
        let d_p = mix(p.z, map(p), fold_factor);
        let n = normalize(vec3<f32>(
            mix(p.z, map(p + vec3<f32>(e.x, e.y, e.y)), fold_factor) - d_p,
            mix(p.z, map(p + vec3<f32>(e.y, e.x, e.y)), fold_factor) - d_p,
            mix(p.z + e.x, map(p + vec3<f32>(e.y, e.y, e.x)), fold_factor) - d_p
        ));

        let v = -rd;

        let view_angle = max(dot(n, v), 0.0);
        let shift = u.zoom_params.w * u.config.x * 0.1;
        let interference = palette(view_angle * 2.0 + shift);

        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let ambient = vec3<f32>(0.02, 0.02, 0.05);

        let base_col = ambient + diff * interference;

        // Intense emissive highlights on sharp edges
        let edge_threshold = 0.05;
        let edge_glow = smoothstep(edge_threshold, 0.0, min_dist);

        let audio_pulse = 1.0 + u.config.y * u.zoom_params.z;
        let emissive = vec3<f32>(1.0, 0.8, 0.2) * edge_glow * u.zoom_params.y * audio_pulse;

        color = vec4<f32>(base_col + emissive, 1.0);
    } else {
        let bg_glow = 0.1 / max(length(centered_uv), 0.01);
        color = vec4<f32>(vec3<f32>(0.05, 0.0, 0.1) * bg_glow, 1.0);
    }

    let fog = 1.0 - exp(-0.05 * t);
    color = mix(color, vec4<f32>(0.0, 0.0, 0.02, 1.0), fog);

    textureStore(writeTexture, id.xy, color);
}