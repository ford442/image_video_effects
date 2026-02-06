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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;

    // Params
    let bead_size = mix(10.0, 100.0, u.zoom_params.x);
    let refraction_str = u.zoom_params.y;
    let tension = u.zoom_params.z;

    // Mouse Interaction
    // We displace the UVs used for the grid lookup to simulate the curtain opening

    // Correct mouse position for aspect ratio for distance calculation
    let aspect = resolution.x / resolution.y;
    var center = mouse;
    if (center.x < 0.0) { center = vec2<f32>(0.5, 0.5); } // Default center if no mouse

    let dist_vec = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Repel force
    let repel_radius = 0.3;
    let interact = smoothstep(repel_radius, 0.0, dist);

    // Displacement direction: away from mouse
    // Scale by tension
    let disp = normalize(dist_vec) * interact * tension * 0.2;

    // So active_uv = uv - disp.
    let active_uv = uv - vec2<f32>(disp.x / aspect, disp.y);

    // Now grid logic on active_uv
    let px_active = active_uv * resolution;
    let cell_uv = fract(px_active / bead_size) - 0.5; // -0.5 to 0.5

    // Circular mask for bead
    // We use cell_uv directly which is proportional to bead size
    // cell_uv runs from -0.5 to 0.5
    let r = length(cell_uv);

    var final_uv = active_uv;
    var alpha = 1.0;

    if (r < 0.5) {
        // Inside bead: Refract
        // Sphere height z
        let z = sqrt(0.25 - r*r);
        // Normal of sphere
        let normal = normalize(vec3<f32>(cell_uv, z));

        // Refraction vector (simplified)
        // Offset UV based on xy normal
        final_uv = active_uv - normal.xy * refraction_str * 0.5;
    } else {
        // Gap
        // Dim the gaps
        final_uv = active_uv;
        alpha = 0.0; // Transparent/Black gaps
    }

    var color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);

    // Apply alpha to darken gaps
    color = color * alpha;

    // Add simple specular highlight on beads
    if (r < 0.5) {
        let light_dir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
        let z = sqrt(0.25 - r*r);
        let normal = normalize(vec3<f32>(cell_uv, z));
        let spec = pow(max(dot(normal, light_dir), 0.0), 20.0);
        color = color + vec4<f32>(spec * 0.5);
    }

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
