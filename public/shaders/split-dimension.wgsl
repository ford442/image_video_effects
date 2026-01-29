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

// Split Dimension
// Param 1: Glitch Intensity
// Param 2: Color Shift
// Param 3: Negative Strength
// Param 4: Split Angle

fn get_mouse() -> vec2<f32> {
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { return vec2<f32>(0.5, 0.5); }
    return mouse;
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = get_mouse();

    let glitch_amt = u.zoom_params.x;
    let color_shift = u.zoom_params.y;
    let neg_str = u.zoom_params.z;
    let angle_param = u.zoom_params.w; // -1 to 1

    let time = u.config.x;

    // Calculate Split Line
    // Use dot product with normal vector
    // angle 0 = vertical split (normal = 1,0)
    let angle = angle_param * 3.14159 * 0.5; // -90 to 90 deg
    let normal = vec2<f32>(cos(angle), sin(angle));

    // Point on line: mouse
    // Distance from line = dot(uv - mouse, normal)
    // Adjust aspect for correct visual angle
    let p_vec = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y);
    let d = dot(p_vec, normal);

    var finalColor = vec4<f32>(0.0);

    if (d < 0.0) {
        // Dimension A: Normal
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    } else {
        // Dimension B: Glitched / Negative

        // Glitch Offset
        var glitch_uv = uv;
        if (glitch_amt > 0.0) {
            let n = noise(vec2<f32>(uv.y * 50.0, time * 20.0)); // Horizontal strips
            if (n > 0.8) {
                glitch_uv.x += (n - 0.5) * glitch_amt * 0.2;
            }
        }

        // RGB Split
        var col = vec3<f32>(0.0);
        let shift = color_shift * 0.05;
        col.r = textureSampleLevel(readTexture, u_sampler, glitch_uv + vec2<f32>(shift, 0.0), 0.0).r;
        col.g = textureSampleLevel(readTexture, u_sampler, glitch_uv, 0.0).g;
        col.b = textureSampleLevel(readTexture, u_sampler, glitch_uv - vec2<f32>(shift, 0.0), 0.0).b;

        // Negative
        col = mix(col, 1.0 - col, neg_str);

        finalColor = vec4<f32>(col, 1.0);

        // Add split line highlight
        if (d < 0.01) {
            finalColor += vec4<f32>(0.5, 0.5, 0.5, 0.0);
        }
    }

    textureStore(writeTexture, global_id.xy, finalColor);
}
