// ═══════════════════════════════════════════════════════════════
// Glass Brick Distortion - Physical glass transmission with Beer-Lambert law
// Category: distortion
// Features: refraction, physically-based alpha, depth-aware
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BrickSize, y=Refraction, z=Grout, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    var mouse = u.zoom_config.yz;

    let brick_count = u.zoom_params.x * 40.0 + 5.0;
    let refraction = u.zoom_params.y * 0.1;
    let grout_width = u.zoom_params.z * 0.1;
    let mouse_clear_radius = 0.2;
    let glass_density = u.zoom_params.w * 3.0 + 0.5; // Beer-Lambert density

    let aspect = resolution.x / resolution.y;
    let uv_scaled = uv * vec2<f32>(brick_count * aspect, brick_count);

    let brick_id = floor(uv_scaled);
    let brick_uv = fract(uv_scaled);

    // Center of the brick in UV space
    let brick_center_uv = (brick_id + 0.5) / vec2<f32>(brick_count * aspect, brick_count);

    // Mouse distance to pixel
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Mask for mouse clearing effect
    let clear_mask = smoothstep(mouse_clear_radius, mouse_clear_radius * 0.5, dist);

    // Grout logic
    var is_grout = 0.0;
    if (brick_uv.x < grout_width || brick_uv.x > 1.0 - grout_width ||
        brick_uv.y < grout_width || brick_uv.y > 1.0 - grout_width) {
        is_grout = 1.0;
    }

    // Calculate normal for lens distortion inside brick
    let b_uv_centered = brick_uv - 0.5;
    let lens = dot(b_uv_centered, b_uv_centered);
    let distort_offset = b_uv_centered * (0.5 - lens) * refraction;

    var sample_uv = brick_center_uv + distort_offset;
    sample_uv = mix(sample_uv, uv, clear_mask);

    // Physical glass properties
    var transmission = 1.0;
    var glass_color = vec3<f32>(0.96, 0.98, 1.0);
    
    if (is_grout < 0.5 && clear_mask < 0.5) {
        // Inside glass brick - calculate physical properties
        // Normal based on lens distortion
        let normal_xy = distort_offset * 10.0; // Approximate normal from distortion
        let normal_z = sqrt(max(0.0, 1.0 - dot(normal_xy, normal_xy)));
        let normal = normalize(vec3<f32>(normal_xy, normal_z));
        
        // View direction
        let viewDir = vec3<f32>(0.0, 0.0, 1.0);
        
        // Fresnel reflection at glancing angles
        let cos_theta = max(dot(viewDir, normal), 0.0);
        let R0 = 0.04; // Glass-air interface
        let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
        
        // Glass thickness approximation based on lens height
        let thickness = 0.1 + lens * 0.2; // Thicker at edges of bulge
        
        // Beer-Lambert absorption
        let absorption = exp(-(1.0 - glass_color) * thickness * glass_density);
        
        // Transmission combines absorption and fresnel
        transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;
    }

    var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);

    // Apply glass tint and alpha for grout vs glass
    if (is_grout > 0.5 && clear_mask < 0.5) {
        // Grout - mostly opaque with some transmission
        color = color * 0.3;
        transmission = 0.3;
    } else if (clear_mask < 0.5) {
        // Glass brick - apply Beer-Lambert tint
        color = vec4<f32>(color.rgb * glass_color, transmission);
    } else {
        // Cleared area - fully transparent
        transmission = 1.0;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Depth pass-through
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, sample_uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
