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

// Polar Warp Interactive
// Param 1: Zoom
// Param 2: Spiral Twist
// Param 3: Repeats
// Param 4: Radial Offset

fn get_mouse() -> vec2<f32> {
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { return vec2<f32>(0.5, 0.5); }
    return mouse;
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

    // Center coordinates on mouse
    // Adjust for aspect to keep circular symmetry
    var diff = uv - mouse;
    diff.x *= aspect;

    // To Polar
    var radius = length(diff);
    var angle = atan2(diff.y, diff.x);

    let zoom = 0.1 + u.zoom_params.x * 2.0; // Avoid division by zero
    let spiral = u.zoom_params.y * 5.0;
    let repeats = max(1.0, u.zoom_params.z);
    let offset = u.zoom_params.w;

    // Distort Polar
    // New Radius mapping
    var r_new = pow(radius, 1.0/zoom);
    r_new = r_new - offset;

    // Spiral: add angle based on radius
    angle = angle + (radius * spiral);

    // Repeat texture radially
    // We map polar (r, theta) back to Cartesian (u, v) for texture lookup?
    // Actually, "Polar Warp" usually means mapping the image *as if* it were polar.
    // Standard effect: UV.x = angle, UV.y = radius
    // Let's implement the tunnel effect:

    let tunnel_u = (angle / 3.14159265) * repeats + u.config.x * 0.1; // Rotate over time
    let tunnel_v = 1.0 / (r_new + 0.001); // Perspective

    // Let's try a different approach: Coordinate Remapping
    // Map (r, theta) back to (x, y) but distorted.

    let distorted_uv = vec2<f32>(
        tunnel_u,
        tunnel_v
    );

    // Wrap UVs
    let final_uv = fract(distorted_uv);

    // Use mirrored repeat for smoother edges
    let mirror_uv = abs(final_uv * 2.0 - 1.0); // 0..1..0 triangle wave
    // Actually fract is fine for tunnel.

    let col = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);

    // Fade out center singularity
    let fade = smoothstep(0.0, 0.1, radius);

    textureStore(writeTexture, global_id.xy, col * fade);
}
