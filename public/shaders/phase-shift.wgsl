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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

let PI: f32 = 3.14159265359;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Mouse controls center of rotation shift
    // Default center is screen center (0.5, 0.5)
    // Mouse drags the "phase point"
    let center = u.zoom_config.yz;
    let t = u.zoom_config.x;

    let offset_uv = uv - center;
    offset_uv.x *= aspect; // Correct for aspect in rotation calculation

    let angle = atan2(offset_uv.y, offset_uv.x);
    let radius = length(offset_uv);

    // Calculate phase shift amount based on radius and mouse interaction
    // Further from center -> more shift? Or swirl?
    // Let's do a twist that varies by channel

    // Twist amount controlled by mouse distance from center of screen
    let mouse_dist_from_center = distance(center, vec2<f32>(0.5));
    let twist_strength = mix(0.1, 2.0, mouse_dist_from_center);

    // Animate slightly
    let anim = sin(t) * 0.1;

    let angle_r = angle + twist_strength * radius + anim;
    let angle_g = angle; // Green stays anchor
    let angle_b = angle - twist_strength * radius - anim;

    // Reconstruct UVs
    let uv_r = center + vec2<f32>(cos(angle_r), sin(angle_r)) * radius * vec2<f32>(1.0/aspect, 1.0);
    let uv_g = center + vec2<f32>(cos(angle_g), sin(angle_g)) * radius * vec2<f32>(1.0/aspect, 1.0);
    let uv_b = center + vec2<f32>(cos(angle_b), sin(angle_b)) * radius * vec2<f32>(1.0/aspect, 1.0);

    let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));
}
