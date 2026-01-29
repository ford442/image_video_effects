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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ZoomSpeed, y=SpiralTwist, z=Branches, w=CenterOffset
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;

    // Normalize coordinates
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Mouse position
    let mouse = u.zoom_config.yz;

    // Parameters
    let zoom_speed = (u.zoom_params.x - 0.5) * 4.0; // -2.0 to 2.0
    let twist = (u.zoom_params.y - 0.5) * 3.14159; // -PI/2 to PI/2
    let branches = floor(u.zoom_params.z * 5.0) + 1.0; // 1 to 6
    let offset_val = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;

    // Vector from mouse to pixel
    var p = uv - mouse;
    p.x *= aspect;

    // Avoid singularity
    let r = length(p);
    if (r < 0.001) {
        textureStore(writeTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 1.0));
        return;
    }

    let angle = atan2(p.y, p.x);

    // Log-Polar Transformation
    // u = log(r)
    // v = angle

    var u_coord = log(r);
    var v_coord = angle / 6.28318; // 0 to 1 range approx (actually -0.5 to 0.5)

    // Apply twist (shear in log-polar space)
    v_coord += u_coord * twist * 0.2;

    // Apply zoom (movement along log-r axis)
    u_coord -= time * zoom_speed;

    // Scale for tiling
    let uv_mapped = vec2<f32>(u_coord, v_coord * branches);

    // Convert back to wrapping UVs (fract for tiling)
    var final_uv = fract(uv_mapped);

    // Add center offset distortion to make it look less like a tunnel and more like Droste
    // This is a stylistic choice to break the perfect symmetry slightly
    final_uv += vec2<f32>(offset_val * 0.1 * sin(v_coord * 10.0), 0.0);
    final_uv = fract(final_uv);

    let color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);

    textureStore(writeTexture, global_id.xy, color);

    // Preserve depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, final_uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
