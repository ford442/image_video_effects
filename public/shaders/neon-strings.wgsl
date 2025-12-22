// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Thickness, y=Vibration, z=Radius, w=Neon
  ripples: array<vec4<f32>, 50>,
};

fn get_luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn sobel(uv: vec2<f32>) -> f32 {
    let texel = vec2<f32>(1.0 / u.config.z, 1.0 / u.config.w);
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;

    let gx = -1.0 * get_luminance(l) + 1.0 * get_luminance(r);
    let gy = -1.0 * get_luminance(t) + 1.0 * get_luminance(b);

    return sqrt(gx * gx + gy * gy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uv_corrected, mouse_corrected);

  // Params
  let thickness = max(0.01, u.zoom_params.x); // Edge Threshold (lower is more edges)
  let vibration_amp = u.zoom_params.y;
  let radius = u.zoom_params.z;
  let neon_intensity = u.zoom_params.w;

  // Vibration logic
  // Create a standing wave pattern that gets stronger near mouse
  let freq = 50.0;
  let wave = sin(uv.y * freq + time * 10.0);
  let influence = smoothstep(radius, 0.0, dist);

  // Displace UVs for sampling to simulate vibrating strings
  let displacement = vec2<f32>(wave * vibration_amp * influence * 0.02, 0.0);
  let distorted_uv = uv + displacement;

  // Sobel Edge Detection on distorted UV
  let edge = sobel(distorted_uv);

  // Thresholding
  // Smoothstep for anti-aliased edge
  let edge_val = smoothstep(thickness, thickness + 0.1, edge);

  // Color mapping
  // Sample original color at distorted UV to get the hue
  let original_color = textureSampleLevel(readTexture, u_sampler, distorted_uv, 0.0).rgb;

  // Boost saturation/brightness for Neon look
  let neon_color = original_color * (1.0 + neon_intensity) * 2.0;

  // Mix background (dimmed) with neon edges
  let bg_color = original_color * 0.1; // Dark background
  let final_color = mix(bg_color, neon_color, edge_val);

  // Update depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

  textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
}
