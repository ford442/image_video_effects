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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Complexity, y=Speed, z=Glow Intensity, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

// --- GLOBALS & STRUCTS ---
const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 100.0;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// --- MATH & SDF HELPERS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(vec2<f32>(p.x, p.z)) - t.x, p.y);
    return length(q) - t.y;
}

// --- MAIN MAPPING ---
fn map(p: vec3<f32>) -> f32 {
    var d = MAX_DIST;
    var q = p;
    // Apply mouse rotation (pointer)
    let rot_yz = rot2D(u.zoom_config.z * 3.14) * vec2<f32>(q.y, q.z);
    q.y = rot_yz.x;
    q.z = rot_yz.y;

    let rot_xz = rot2D(u.zoom_config.y * 3.14) * vec2<f32>(q.x, q.z);
    q.x = rot_xz.x;
    q.z = rot_xz.y;

    // Add rings
    let complexity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let audio_react = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;

    let loop_count = i32(clamp(complexity, 1.0, 10.0));
    let speed_mult = 1.0 + bass * audio_react;

    for(var i = 0; i < loop_count; i++) {
        let fi = f32(i);

        let rot_xy = rot2D(u.config.x * 0.2 * speed * (fi + 1.0) * speed_mult + bass * audio_react * 3.14) * vec2<f32>(q.x, q.y);
        q.x = rot_xy.x;
        q.y = rot_xy.y;

        let rot_yz_inner = rot2D(0.5) * vec2<f32>(q.y, q.z);
        q.y = rot_yz_inner.x;
        q.z = rot_yz_inner.y;

        let ring = sdTorus(q, vec2<f32>(2.0 + fi * 0.5, 0.05));
        d = min(d, ring);
    }
    return d;
}

// --- COMPUTE MAIN ---
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let uv = (vec2<f32>(id.xy) * 2.0 - dims) / dims.y;
    let screen_uv = (vec2<f32>(id.xy) + 0.5) / dims;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if(d < SURF_DIST || t > MAX_DIST) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var alpha = 0.0;
    let glow = u.zoom_params.z;
    if(t < MAX_DIST) {
        // Base coloring with hue shift from param3 (Glow Intensity)
        let hue_shift = glow * 0.3;
        let base_col = hsv2rgb(vec3<f32>(0.12 + hue_shift, 0.8, 1.0));
        let falloff = 1.0 - t / MAX_DIST;
        col = base_col * falloff * glow;
        alpha = falloff * glow;
    }

    textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screen_uv, 0.0).r;
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
