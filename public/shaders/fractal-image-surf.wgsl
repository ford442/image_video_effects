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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Complex Number Math
fn cMul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cAdd(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x + b.x, a.y + b.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let iterations = i32(mix(1.0, 10.0, u.zoom_params.x));
    let zoom = mix(0.5, 3.0, u.zoom_params.y);
    let offset = vec2<f32>(u.zoom_params.z, u.zoom_params.w) * 2.0 - 1.0;

    // Map UV to Complex Plane
    // Center at (0,0)
    var z = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 4.0 / zoom + offset;

    // C is determined by Mouse
    // Map mouse (0..1) to Complex Plane (-2..2)
    var c = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 4.0;

    // If mouse is at default (-1,-1), use a nice preset
    if (mouse.x < 0.0) {
        c = vec2<f32>(-0.4, 0.6);
    }

    // Julia Set Iteration
    // z = z^2 + c

    // We want to track the "trap" or just use the final z as a UV lookup
    // Using final Z for lookup creates the fractal "droste" effect

    for (var i = 0; i < iterations; i++) {
        z = cAdd(cMul(z, z), c);

        // Escape condition (optional for image mapping, but good for stability)
        if (length(z) > 4.0) {
            // z = normalize(z) * 2.0; // clamp?
        }
    }

    // Map Z back to UV
    // Z is in range approx -2..2 (or larger if escaped)
    // Wrap it into 0..1

    // Option A: fract(z)
    var finalUV = fract(z * 0.5 + 0.5);

    // Option B: smooth wrap
    // finalUV = vec2<f32>(sin(z.x), cos(z.y)) * 0.5 + 0.5;

    // Sample Texture
    // Add time based shift
    let time = u.config.x;
    // finalUV += vec2<f32>(time * 0.05, 0.0);

    let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Mix with iteration count?
    // Not needed for pure image warp

    textureStore(writeTexture, global_id.xy, color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
