// ----------------------------------------------------------------
// Glacial-Aether Quantum-Cavern
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
    zoom_params: vec4<f32>,  // x=Ice Density, y=Plasma Glow, z=Fracture Rate, w=Cavern Scale
    ripples: array<vec4<f32>, 50>,
};

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn mapSDF(p: vec3<f32>) -> f32 {
    var q = p;
    var scale = 1.0;
    // Folding space for KIFS
    for (var i = 0; i < 4; i++) {
        q = abs(q) - vec3<f32>(1.0) * u.zoom_params.w; // Cavern Scale
        q.xy = q.xy * rotate(u.config.x * 0.1 + u.config.y * 0.5);
        q.xz = q.xz * rotate(u.config.x * 0.15);
        q = q * 1.4;
        scale = scale * 1.4;
    }
    return (length(q) - u.zoom_params.x * 2.0) / scale; // Ice Density
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let uv = vec2<f32>(id.xy) / res;
    var col = vec3<f32>(0.0);

    // Setup camera
    var ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x);
    var rd = normalize(vec3<f32>(uv * 2.0 - 1.0, 1.0));
    rd.xy = rd.xy * rotate((u.zoom_config.y - 0.5) * 3.14);
    rd.yz = rd.yz * rotate((u.zoom_config.z - 0.5) * 3.14);

    // Raymarching loop
    var t = 0.0;
    let max_dist = 20.0;
    var hit = false;
    var min_dist = 100.0;

    for(var i = 0; i < 64; i++) {
        let p = ro + rd * t;
        let d = mapSDF(p);
        min_dist = min(min_dist, d);
        if(d < 0.01) { hit = true; break; }
        if(t > max_dist) { break; }
        t += d;
    }

    // Basic Shading
    if (hit) {
        let p = ro + rd * t;
        let depth_fade = 1.0 / (1.0 + t * t * 0.1);
        col = vec3<f32>(0.1, 0.4, 0.8) * depth_fade * u.zoom_params.y; // Plasma Glow

        let fracture = fract(length(p) * u.zoom_params.z * 5.0 + u.config.y * 2.0);
        col += vec3<f32>(0.2, 0.8, 1.0) * step(0.95, fracture) * u.config.y * depth_fade;
    } else {
        col = vec3<f32>(0.05, 0.1, 0.2) * (1.0 / (1.0 + min_dist * 10.0)) * u.zoom_params.y;
    }

    col += vec3<f32>(0.2, 0.5, 0.6) * u.config.y * 0.1;

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}