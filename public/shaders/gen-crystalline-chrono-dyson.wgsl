// ----------------------------------------------------------------
// Crystalline Chrono-Dyson
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
    zoom_params: vec4<f32>,  // x=Panel Density, y=Quasar Glow, z=Flux Speed, w=Swarm Count
    ripples: array<vec4<f32>, 50>,
};

// Custom mod function
fn mod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

// Raymarching map function combining panel repetition and central quasar
fn map(p: vec3<f32>) -> f32 {
    var q = p;
    let time = u.config.x * u.zoom_params.z; // Flux Speed

    // Audio reactivity
    let audio = u.config.y;

    // Rotation for Dyson sphere
    let rot_x = q.x * cos(time * 0.1) - q.z * sin(time * 0.1);
    let rot_z = q.x * sin(time * 0.1) + q.z * cos(time * 0.1);
    q.x = rot_x;
    q.z = rot_z;

    // Domain repetition driven by Panel Density
    let density = u.zoom_params.x;
    var panel_q = q;
    panel_q = fract(panel_q * density) - 0.5;

    // Central Quasar (smooth min with FBM noise simulation)
    let quasar_dist = length(q) - 0.5 - (sin(time * 5.0 + q.x * 10.0) * 0.05 * audio);

    // Panels
    let panel_dist = length(panel_q) - 0.2;

    // Dyson structure: hollow sphere minus KIFS fractal cutouts (approximated here as intersecting the repetition)
    let shell = abs(length(q) - 2.0) - 0.1;
    let panels = max(shell, panel_dist);

    // Combine quasar and panels
    // Using a smooth min for blending the plasma conduits
    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (panels - quasar_dist) / k, 0.0, 1.0);
    return mix(panels, quasar_dist, h) - k * h * (1.0 - h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse tracking (orbital camera)
    let mx = (u.zoom_config.y - 0.5) * 6.28;
    let my = (u.zoom_config.z - 0.5) * 3.14;

    let ro_xz = rotate2D(mx) * vec2<f32>(ro.x, ro.z);
    ro.x = ro_xz.x;
    ro.z = ro_xz.y;

    let ro_yz = rotate2D(my) * vec2<f32>(ro.y, ro.z);
    ro.y = ro_yz.x;
    ro.z = ro_yz.y;

    // Look at origin
    let cw = normalize(-ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    rd = normalize(uv.x * cu + uv.y * cv + 1.0 * cw);

    // Gravity well warp based on distance to cursor (using uv to approximate)
    let warp_factor = 1.0 - smoothstep(0.0, 0.5, length(uv));
    rd = normalize(rd + vec3<f32>(warp_factor * 0.1 * sin(u.config.x), warp_factor * 0.1 * cos(u.config.x), 0.0));

    var t = 0.0;
    var hit = false;
    for (var i = 0; i < 100; i = i + 1) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001) { hit = true; break; }
        if (t > 20.0) { break; }
        t = t + d;
    }

    var col = vec3<f32>(0.0);
    if (hit) {
        let p = ro + rd * t;
        let quasar_glow = u.zoom_params.y;
        let audio_pulse = 1.0 + u.config.y * 0.5;

        // Multi-step gradient: deep ultraviolet to blinding white-gold
        let dist_to_center = length(p);
        let gradient = mix(vec3<f32>(0.2, 0.0, 0.5), vec3<f32>(1.0, 0.8, 0.2), 1.0 - smoothstep(0.0, 2.0, dist_to_center));

        col = gradient * quasar_glow * audio_pulse / (t * 0.5);

        // Swarm Drones
        let swarm_count = u.zoom_params.w;
        col = col + vec3<f32>(0.1, 0.8, 1.0) * smoothstep(0.9, 1.0, sin(t * swarm_count + u.config.x));
    } else {
        // Background starlight
        col = vec3<f32>(0.05, 0.05, 0.1) * hash3(rd).x;
    }

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
