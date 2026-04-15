// ----------------------------------------------------------------
// Graviton Plasma-Lotus
// Category: generative
// ----------------------------------------------------------------
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
    zoom_params: vec4<f32>,  // x=Rotation Speed, y=Complexity, z=Bloom Intensity, w=Gravity Well Strength
    ripples: array<vec4<f32>, 50>,
};


// Helper: 3D Rotation Matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// KIFS Fold
fn fold(p: vec3<f32>, time: f32) -> vec3<f32> {
    var q = p;
    for(var i = 0; i < 4; i++) {
        q = abs(q) - 0.5;
        // Apply rotation
        let r = rot(time * 0.1 + f32(i));
        q.xy = r * q.xy;
        q.yz = r * q.yz;
    }
    return q;
}

// Signed Distance Field
fn map(p: vec3<f32>) -> vec2<f32> {
    let time = u.config.x * u.zoom_params.x; // Speed param

    // Domain warp
    var q = p;
    q.x += sin(q.z * 2.0 + time) * 0.2;
    q.y += cos(q.x * 2.0 + time) * 0.2;

    // KIFS structure
    let folded_q = fold(q, time);

    // Base lotus petal (distorted sphere)
    let d1 = length(folded_q) - 0.3 * u.zoom_params.y; // Size/complexity param

    // Central Core
    let d2 = length(p) - 0.5;

    // Smooth-min blend
    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    let d = mix(d2, d1, h) - k * h * (1.0 - h);

    var mat = 1.0;
    if (d1 < d2) { mat = 2.0; } // 1.0 = Core, 2.0 = Petals

    return vec2<f32>(d, mat);
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var dO = 0.0;
    var mat = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * dO;
        let dS = map(p);
        dO += dS.x;
        mat = dS.y;
        if(dO > 50.0 || abs(dS.x) < 0.001) { break; }
    }
    return vec2<f32>(dO, mat);
}

// Normal Calculation
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p).x;
    let n = d - vec3<f32>(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return normalize(n);
}

// --- Main Compute ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(id.xy) * 2.0 - res) / res.y;

    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    // Mouse Interaction (Gravity Well Distortion)
    let mouse = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - res) / res.y;
    var rd_uv = uv;
    let dist_to_mouse = length(uv - mouse);
    let gravity_strength = u.zoom_params.w;
    rd_uv += normalize(mouse - uv) * (gravity_strength / (dist_to_mouse * 10.0 + 1.0));

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(rd_uv, 1.0));

    let rm = raymarch(ro, rd);
    let d = rm.x;
    let mat = rm.y;

    var col = vec3<f32>(0.0);

    if (d < 50.0) {
        let p = ro + rd * d;
        let n = getNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(-rd);
        let rim = 1.0 - max(dot(viewDir, n), 0.0);

        // Color mapping
        let time = u.config.x;
        let baseColor = 0.5 + 0.5 * cos(time + p.xyx + vec3<f32>(0.0, 2.0, 4.0));

        if (mat == 1.0) {
            // Core: Audio reactive glow
            let audio = u.config.y;
            col = vec3<f32>(1.0, 0.3, 0.8) * (1.0 + audio * 2.0) * diff + vec3<f32>(0.8, 0.1, 0.4) * rim;
        } else if (mat == 2.0) {
            // Petals: Iridescent subsurface
            col = baseColor * diff + vec3<f32>(0.2, 0.6, 1.0) * smoothstep(0.6, 1.0, rim);
        }

        // Apply Bloom
        col += vec3<f32>(1.0, 0.5, 0.8) * (0.1 / (d * d)) * u.zoom_params.z;

    } else {
        col = vec3<f32>(0.01, 0.01, 0.03); // Deep space background
    }

    // Output
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
