// ----------------------------------------------------------------
// Chromatic Singularity-Loom
// Category: generative
// ----------------------------------------------------------------
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Gravity Mass, y=Thread Density, z=Accretion Glow, w=Chromatic Shift
    ripples: array<vec4<f32>, 50>
};

// --- CONSTANTS & HELPERS ---
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.005;

// Rotate 2D vector
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Map function evaluating the singularity and fractal threads
fn map(p: vec3<f32>, time: f32, audio_intensity: f32, params: vec4<f32>, mousePos: vec2<f32>) -> vec2<f32> {
    var pos = p;

    // Gravitational Lensing effect
    // Mouse offset drives the center of the singularity (mapped to world space)
    let center = vec3<f32>((mousePos.x - 0.5) * 10.0, (mousePos.y - 0.5) * -10.0, 0.0);
    let dist_sq = dot(pos - center, pos - center);

    // Use the mapped zoom_params.x for Gravity Mass, default if 0
    var mass = params.x;
    if (mass == 0.0) { mass = 2.0; }

    if (dist_sq > 0.0) {
        pos += normalize(pos) * (mass / dist_sq);
    }

    // KIFS Fractal for threads
    var iterations_f = params.y;
    if (iterations_f == 0.0) { iterations_f = 4.0; }
    let iterations = i32(iterations_f);

    for (var i = 0; i < iterations; i++) {
        pos = abs(pos) - vec3<f32>(0.5 + audio_intensity * 0.2);
        let r = rot(time * 0.2 + f32(i));
        let x_new = r[0][0]*pos.x + r[0][1]*pos.y;
        let y_new = r[1][0]*pos.x + r[1][1]*pos.y;
        pos.x = x_new;
        pos.y = y_new;
    }

    // Thread SDF
    let d1 = length(pos.xz) - 0.05;

    // Singularity Core SDF
    let d2 = length(p - center) - 1.0;

    return vec2<f32>(min(d1, d2), 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    let time = u.config.x;
    let audio_intensity = u.config.y; // Audio from config

    // Extract mouse params
    var mousePos = u.zoom_config.yz;
    if (mousePos.x == 0.0 && mousePos.y == 0.0) {
        mousePos = vec2<f32>(0.5);
    }

    let params = u.zoom_params; // Using standard zoom_params mapping

    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    var dO = 0.0;
    var hit = false;
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p, time, audio_intensity, params, mousePos);
        dO += dS.x;
        if (dS.x < SURF_DIST) {
            hit = true;
            break;
        }
        if (dO > MAX_DIST) {
            break;
        }
    }

    var col = vec3<f32>(0.0);
    if (hit) {
        let hit_p = ro + rd * dO;
        let center = vec3<f32>((mousePos.x - 0.5) * 10.0, (mousePos.y - 0.5) * -10.0, 0.0);
        let dist_center = length(hit_p - center);
        let plasma_index = min(u32(abs(dist_center) * 10.0 + time * 10.0), 255u);
        let plasma_color = plasmaBuffer[plasma_index].rgb;

        var chromatic_shift = params.w;
        if (chromatic_shift == 0.0) { chromatic_shift = 0.5; }

        // Chromatic Shift applied via a cosine palette based on time and audio
        let phase = hit_p.z * chromatic_shift + time;
        let c_shift = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(phase, phase + 2.09, phase + 4.18));

        var accretion_glow = params.z;
        if (accretion_glow == 0.0) { accretion_glow = 1.0; }
        // Accretion Glow adds to the brightness based on distance and audio
        let bloom = accretion_glow * exp(-dist_center * 2.0) * (1.0 + audio_intensity * 2.0);

        col = plasma_color * c_shift * (1.0 / (1.0 + dO * dO * 0.1)) + plasma_color * bloom;
    }

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
