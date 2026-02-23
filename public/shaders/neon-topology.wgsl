@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<f32, 20>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let coords = vec2<i32>(global_id.xy);

    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) {
        return;
    }

    let uv = vec2<f32>(coords) / dims;

    // Parameters
    let line_density = 10.0 + u.zoom_params.x * 90.0; // 10-100
    let height_scale = u.zoom_params.y * 3.0; // 0-3
    let mouse_influence = u.zoom_params.z; // 0-1
    let glow_strength = u.zoom_params.w * 2.0; // 0-2

    let time = u.config.x;
    let mouse_pos = u.zoom_config.yz;

    // Base color
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    // Luminance for height
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Mouse interaction: localized bulge
    let aspect = dims.x / dims.y;
    let dist_vec = (uv - mouse_pos) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Create a smooth ripple/bulge around mouse
    let mouse_bump = exp(-dist * 5.0) * mouse_influence * sin(dist * 20.0 - time * 5.0);

    let total_height = luma * height_scale + mouse_bump;

    // Isolines
    // Use sine wave of height to create bands
    let contour = sin(total_height * line_density - time);
    let line_width = 0.1; // Sharpness
    // Create sharp lines from sine wave
    let line_val = smoothstep(1.0 - line_width, 1.0, abs(contour));

    // Gradient calculation for psuedo-lighting
    let eps = 1.0 / dims;
    let luma_r = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(eps.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let luma_u = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, eps.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let grad = vec2<f32>(luma_r - luma, luma_u - luma);
    let normal_intensity = length(grad) * 10.0;

    // Neon coloring
    // Map height to hue
    let hue = total_height * 0.5 + 0.1;
    let neon = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
    );

    // Composite
    // Dark background + Lines + Glow
    var final_color = vec3<f32>(0.0);

    // Add lines
    final_color += neon * line_val;

    // Add glow
    final_color += neon * total_height * glow_strength * 0.3;

    // Add original video faintly for context
    final_color += color.rgb * 0.1;

    // Add edge lighting
    final_color += vec3<f32>(normal_intensity) * neon * 0.5;

    // Clamp
    final_color = clamp(final_color, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coords, vec4<f32>(final_color, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
