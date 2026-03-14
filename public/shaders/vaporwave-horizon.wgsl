// ═══════════════════════════════════════════════════════════════
//  Vaporwave Horizon - Volumetric Alpha Upgrade
//  
//  Scientific Implementation:
//  - Distance-based fog with optical depth
//  - Atmospheric perspective using Beer-Lambert law
//  - Grid rendered as emissive surface with volumetric fog overlay
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
  config: vec4<f32>,       // x=Time, y=Ripples, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
  ripples: array<vec4<f32>, 50>,
};

// Atmospheric extinction coefficients
const SIGMA_T_ATMOSPHERE: f32 = 0.6;    // Atmospheric extinction
const SIGMA_T_FOG: f32 = 1.2;           // Purple fog extinction

// Pseudo-random hash
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let grid_speed = u.zoom_params.x; // Grid movement speed
    let glow_intensity = u.zoom_params.y; // Brightness of grid
    let grid_scale = u.zoom_params.z; // Size of grid squares
    let warp_amt = u.zoom_params.w;   // Curvature of grid/sky

    // Mouse Interaction
    let mouse_y = u.zoom_config.z;
    let horizon = mouse_y;
    let mouse_x = u.zoom_config.y;
    let curve = (mouse_x - 0.5) * 4.0 * warp_amt;

    var final_color = vec3<f32>(0.0, 0.0, 0.0);
    var alpha = 0.0;

    if (uv.y < horizon) {
        // ═══════════════════════════════════════════════════════════════
        //  SKY (The Image) with Volumetric Sunset Haze
        // ═══════════════════════════════════════════════════════════════
        
        // Map UV y from [0, horizon] to [0, 1]
        let sky_uv_y = uv.y / max(horizon, 0.01);
        var sky_uv = vec2<f32>(uv.x, sky_uv_y);

        // Sample source image
        let img_color = textureSampleLevel(readTexture, u_sampler, sky_uv, 0.0).rgb;
        
        // Sunset gradient (volumetric scattering simulation)
        let gradient = smoothstep(0.0, 1.0, sky_uv_y);
        let sunset_color = vec3<f32>(0.8, 0.2, 0.5); // Pink/magenta sunset
        
        // Atmospheric optical depth (more haze near horizon)
        let heightFactor = 1.0 - sky_uv_y;
        let opticalDepth = heightFactor * 0.5 * SIGMA_T_ATMOSPHERE;
        let transmittance = exp(-opticalDepth);
        
        // Blend image with sunset haze
        final_color = mix(img_color * transmittance, sunset_color, gradient * 0.3 * glow_intensity * (1.0 - transmittance));
        
        // Sky alpha (slightly transparent to blend with potential background)
        alpha = 0.95;

    } else {
        // ═══════════════════════════════════════════════════════════════
        //  FLOOR (The Grid) with Volumetric Distance Fog
        // ═══════════════════════════════════════════════════════════════
        
        // Perspective projection
        let dy = uv.y - horizon;
        let z_depth = 1.0 / max(dy, 0.001); // Distance from camera

        // Apply curve
        let x_offset = curve * dy * dy;
        let grid_u = (uv.x - 0.5 - x_offset) * z_depth * (0.5 + grid_scale) + 0.5;
        let grid_v = z_depth * (0.5 + grid_scale) + u.config.x * grid_speed;

        // Draw Grid Lines
        let grid_x = abs(fract(grid_u) - 0.5);
        let grid_y = abs(fract(grid_v) - 0.5);
        let line_mask = step(0.45, grid_x) + step(0.45, grid_y);
        let grid_val = clamp(line_mask, 0.0, 1.0);

        // Reflection of Sky/Image
        let refl_y = horizon - dy;
        let refl_uv = vec2<f32>(uv.x, clamp(refl_y, 0.0, 1.0));
        let refl_color = textureSampleLevel(readTexture, u_sampler, refl_uv, 0.0).rgb;

        // Grid Color (Cyan/Magenta vaporwave colors)
        let grid_col = vec3<f32>(0.0, 1.0, 1.0) * grid_val * glow_intensity * 2.0;

        // Fade grid into horizon
        let fade = smoothstep(0.0, 0.2, dy);
        
        // Base floor color with reflection
        var floor_color = mix(refl_color * 0.5, grid_col, grid_val * fade);

        // ═══════════════════════════════════════════════════════════════
        //  Volumetric Distance Fog on Floor
        // ═══════════════════════════════════════════════════════════════
        
        // Fog increases with distance (z_depth)
        // τ = density * distance * extinction_coeff
        let fogDensity = 0.15;
        let fogDistance = z_depth * 0.3;
        let fogOpticalDepth = fogDensity * fogDistance * SIGMA_T_FOG;
        let fogTransmittance = exp(-fogOpticalDepth);
        
        // Vaporwave fog color (purple/pink)
        let fogColor = vec3<f32>(0.4, 0.1, 0.4);
        
        // Apply volumetric fog
        final_color = mix(fogColor, floor_color, fogTransmittance);
        
        // Alpha based on fog density (more fog = higher alpha)
        alpha = 0.8 + (1.0 - fogTransmittance) * 0.2;
    }

    // ═══════════════════════════════════════════════════════════════
    //  Final Output with Volumetric Alpha
    // ═══════════════════════════════════════════════════════════════
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, alpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, alpha));
}
