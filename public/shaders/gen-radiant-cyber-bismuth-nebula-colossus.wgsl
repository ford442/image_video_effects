// ----------------------------------------------------------------
// Radiant Cyber-Bismuth Nebula-Colossus
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// Complex 3D rotation matrix
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// Main SDF Mapping
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;
    let mouse = u.zoom_config.yz;
    p = p - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);

    // IFS Bismuth Folding
    for (var i = 0; i < 5; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.8, 0.5) * u.zoom_params.x;
        p = p * rotX(u.config.x * 0.1) * rotY(u.config.x * 0.15);
    }

    let base_dist = length(max(abs(p) - vec3<f32>(1.0), vec3<f32>(0.0))) - 0.2;
    return base_dist;
}

// Compute Normals
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

// Main Compute Shader
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(u.config.zw);
    if (coords.x >= res.x || coords.y >= res.y) { return; }

    let uv = (vec2<f32>(coords) - u.config.zw * 0.5) / u.config.zw.y;

    let ro = vec3<f32>(0.0, 0.0, -5.0 + 0.5 * 2.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var max_d = 10.0;
    var d = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > max_d) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    if (t < max_d) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);

        let audio_react = plasmaBuffer[0].x * u.zoom_params.z;

        // Iridescent coloring
        col = vec3<f32>(0.5) + 0.5 * cos(u.config.x + p.xyx * 2.0 + vec3<f32>(0.0, 2.0, 4.0));
        col *= diff;
        col += vec3<f32>(1.0, 0.2, 0.8) * audio_react * 2.0; // Emissive glow
    } else {
        // Volumetric background
        col = vec3<f32>(0.05, 0.02, 0.1) * (1.0 - length(uv));
    }

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
