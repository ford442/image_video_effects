// ═══════════════════════════════════════════════════════════════
//  Radial Hex Lens - Interactive hexagonal pixelation with lens distortion
//  Category: distortion
//  Features: mouse-driven
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
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Scale, y=Radius, z=Distortion, w=unused
  ripples: array<vec4<f32>, 50>,
};

fn get_hex_center(uv: vec2<f32>, scale: f32) -> vec2<f32> {
    let r = vec2<f32>(1.0, 1.7320508); // 1.0, sqrt(3.0)
    let h = r * 0.5;

    // Divide space into a grid
    let spacing = vec2<f32>(scale, scale * r.y);

    let a = (fract(uv / spacing) - 0.5) * spacing;
    let b = (fract((uv - spacing * 0.5) / spacing) - 0.5) * spacing;

    let center_a = uv - a;
    let center_b = uv - b;

    if (dot(a, a) < dot(b, b)) {
        return center_a;
    } else {
        return center_b;
    }
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    
    var uv_corrected = uv;
    uv_corrected.x = uv_corrected.x * aspect; // Fix aspect for math

    // Mouse position from zoom_config.yz
    let mouse = u.zoom_config.yz;
    let mouse_corrected = vec2<f32>(
        mouse.x * aspect,
        mouse.y
    );

    // Parameters from zoom_params
    let scale_param = u.zoom_params.x;        // Hex scale
    let radius_param = u.zoom_params.y;       // Lens radius
    let distortion_param = u.zoom_params.z;   // Distortion strength

    // Lens Distortion
    let offset = uv_corrected - mouse_corrected;
    let dist = length(offset);

    // Nonlinear zoom: bulge out near mouse
    let effect_radius = radius_param * 1.5; // Scale up a bit to be useful
    let strength = distortion_param;

    let falloff = smoothstep(effect_radius, 0.0, dist);
    let zoom_factor = 1.0 - strength * falloff * 0.5; // Max 0.5x zoom (2x mag)

    let distorted_pos = mouse_corrected + offset * zoom_factor;

    // Hex Pixelate
    // Map 0.0-1.0 slider to useful scale (e.g. 0.01 to 0.1)
    let hex_size = mix(0.01, 0.1, scale_param);

    // Determine hex center in aspect-corrected space
    let center = get_hex_center(distorted_pos, hex_size);

    // Convert back to UV space
    var sample_uv = center;
    sample_uv.x = sample_uv.x / aspect;

    // Edge darkening for hexes (optional, adds style)
    let dist_to_center = length(distorted_pos - center);
    let hex_mask = smoothstep(hex_size * 0.5, hex_size * 0.45, dist_to_center);

    // Sample texture
    let color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
    var final_color = color.rgb * hex_mask;

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
