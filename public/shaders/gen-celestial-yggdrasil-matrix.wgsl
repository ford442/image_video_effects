// ----------------------------------------------------------------
// Celestial Yggdrasil-Matrix
// Category: generative
// ----------------------------------------------------------------
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
    zoom_params: vec4<f32>,  // x=Branch Complexity, y=Plasma Flow, z=Gravity Warp, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// --- Helper Functions ---
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// KIFS Fractal
fn map(p: vec3<f32>) -> f32 {
    var q = p;
    // Apply mouse gravity warp
    let mouse_dist = length(q.xy - vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 5.0);
    q += normalize(q) * smoothstep(5.0, 0.0, mouse_dist) * u.zoom_params.z;

    let branch_complexity = u.zoom_params.x;
    var d = length(q) - 1.0; // Base sphere

    // KIFS Iteration
    var scale = 1.0;
    for (var i = 0u; i < u32(branch_complexity); i = i + 1u) {
        q = abs(q) - vec3<f32>(0.5, 1.0, 0.5) * scale;
        let ry = rot(u.config.x * 0.1 + f32(i) * 0.5);
        let rx = rot(u.config.x * 0.15 + f32(i) * 0.3);
        let rz = rot(u.config.x * 0.2 + f32(i) * 0.4);

        let q_yz = ry * q.yz; q.y = q_yz.x; q.z = q_yz.y;
        let q_xz = rx * q.xz; q.x = q_xz.x; q.z = q_xz.y;
        let q_xy = rz * q.xy; q.x = q_xy.x; q.y = q_xy.y;

        scale *= 0.5;
    }

    // Twist trunk
    let angle = q.y * 2.0;
    let r_twist = rot(angle);
    let q_xz_twist = r_twist * q.xz;
    q.x = q_xz_twist.x;
    q.z = q_xz_twist.y;

    let cyl = length(q.xz) - 0.1 * scale;
    d = smin(d, cyl, 0.5 * scale);

    return d;
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> f32 {
    var dO = 0.0;
    for(var i=0; i<64; i++) {
        let p = ro + rd * dO;
        let dS = map(p);
        dO += dS;
        if(dO > 100.0 || abs(dS) < 0.001) { break; }
    }
    return dO;
}


@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Camera rotation
    let r_cam = rot(u.config.x * 0.1);
    let ro_xz = r_cam * ro.xz; ro.x = ro_xz.x; ro.z = ro_xz.y;
    let rd_xz = r_cam * rd.xz; rd.x = rd_xz.x; rd.z = rd_xz.y;

    let d = raymarch(ro, rd);

    var col = vec3<f32>(0.0);

    // Plasma & Glow
    if(d < 100.0) {
        let p = ro + rd * d;
        let dist = length(p);

        // Volumetric plasma flow
        let flow = sin(p.y * 5.0 - u.config.x * u.zoom_params.y * 2.0) * 0.5 + 0.5;

        // Audio reactive pulse
        let audioPulse = u.config.y * 5.0 * exp(-dist * 0.5);

        // Chromatic dispersion pseudo-effect & Glow
        let baseColor = vec3<f32>(0.2, 0.5, 1.0) * flow;
        let highlight = vec3<f32>(1.0, 0.8, 0.2) * audioPulse;
        col = (baseColor + highlight) * u.zoom_params.w;

        // Simple ambient occlusion / depth darkening
        col *= exp(-d * 0.2);
    } else {
        // Deep cosmic void background
        let bg = vec3<f32>(0.01, 0.0, 0.05) + vec3<f32>(0.1, 0.0, 0.2) * (uv.y * 0.5 + 0.5);
        col = bg;
    }

    // Orbiting particle leaves swarming with mouse
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let m_dist = length(uv - mouse);
    let swarm = smoothstep(0.5, 0.0, m_dist) * u.config.y;

    // Add some noise based stars
    let hash = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if(hash > 0.99) {
        col += vec3<f32>(1.0) * swarm * 2.0;
    }


    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
