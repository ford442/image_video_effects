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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=MeltRadius, y=GridSize, z=Viscosity, w=ColorStrength
  ripples: array<vec4<f32>, 50>,
};

// Hexagon grid function
// Returns vec4: xy = hex center ID, z = distance to center, w = angle/idk
fn hexCoords(uv: vec2<f32>) -> vec4<f32> {
    let r = vec2<f32>(1.0, 1.73);
    let h = r * 0.5;

    let a = mod(uv, r) - h;
    let b = mod(uv - h, r) - h;

    let gv = select(b, a, dot(a, a) < dot(b, b));

    // Calculate distance to edge (approximate for SDF)
    let x = abs(gv.x);
    let y = abs(gv.y);
    // Hexagon sdf approx: max(x, dot(vec2(x,y), normalize(vec2(1, 1.73))))
    let dist = max(x, x * 0.5 + y * 0.866); // 0.866 is sin(60)

    let id = uv - gv;
    return vec4<f32>(id, dist, 0.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Parameters
    let melt_radius = u.zoom_params.x * 0.5 + 0.05; // 0.05 to 0.55
    let grid_size = u.zoom_params.y * 30.0 + 5.0; // 5 to 35
    let viscosity = u.zoom_params.z * 0.1; // Distortion strength
    let color_strength = u.zoom_params.w;

    // Mouse Distance Logic
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist_to_mouse = length(dist_vec);

    // Melt factor: 1.0 = fully melted (clean), 0.0 = fully crystallized (hex)
    let melt = smoothstep(melt_radius, melt_radius * 0.4, dist_to_mouse);

    // Hex Grid Calculation
    // Scale UV for grid
    let grid_uv = uv * grid_size;
    // Adjust aspect for hex regular shape
    let hex_uv = vec2<f32>(grid_uv.x * aspect, grid_uv.y);
    let hex = hexCoords(hex_uv);

    let hex_center = hex.xy;
    let hex_dist = hex.z; // 0 at center, 0.5 at edge (approx)

    // Create "Honey" thickness profile
    // We want the edges to be thick/refracting, center clear
    // Invert dist: 0 at edge, 1 at center?
    // hex_dist is ~0 to 0.5.
    // Normalized edge factor:
    let edge_factor = smoothstep(0.4, 0.5, hex_dist); // 1 at edge, 0 inside

    // Distortion
    // Pull pixels towards hex center or push away?
    // Viscous liquid acts like a convex lens: magnifies center.
    // So pull UV towards hex center.
    // Vector from current pixel to hex center (in hex space)
    let center_vec = vec2<f32>(0.0, 0.0) - (hex_uv - hex_center); // Not quite right, need local coord
    // Actually we computed `gv` inside hexCoords but didn't return it perfectly.
    // Let's recompute local UV
    // Simpler: hex.xy is the center in scaled space.
    let local_uv = hex_uv - hex.xy;

    // Lens distortion
    let lens_offset = local_uv * (hex_dist * 2.0) * viscosity * (1.0 - melt);

    // Apply aspect correction back to offset
    let final_offset = vec2<f32>(lens_offset.x / aspect, lens_offset.y);

    let distorted_uv = uv - final_offset;

    // Sample Texture
    var color = textureSampleLevel(readTexture, u_sampler, distorted_uv, 0.0).rgb;

    // Add Honey Visuals (Specular + Color)
    // Only apply where not melted
    let honey_mix = (1.0 - melt);

    if (honey_mix > 0.01) {
        // 1. Amber Tint at edges
        let amber = vec3<f32>(1.0, 0.7, 0.2);
        // Thicker at edges
        let thick = smoothstep(0.2, 0.5, hex_dist);
        color = mix(color, color * amber, thick * color_strength * honey_mix);

        // 2. Specular Highlight (simulating 3D surface)
        // Normal estimation based on hex_dist gradient
        // Center is high, edge is low? Or Center is low (concave)?
        // Honey surface: Meniscus. Edges high (surface tension), center flat?
        // Or Droplet: Center high.
        // Let's do Droplet: Center High.
        // Normal points up at center, outwards at edges.
        let N = normalize(vec3<f32>(local_uv.x, local_uv.y, 0.5)); // Crude normal

        // Light source (Mouse or fixed?)
        // Let's make light follow mouse for interactivity
        let light_pos = vec3<f32>((mouse.x * aspect - hex_uv.x), (mouse.y - hex_uv.y), 2.0);
        let L = normalize(light_pos);

        // Specular (Blinn)
        let V = vec3<f32>(0.0, 0.0, 1.0);
        let H = normalize(L + V);
        let spec = pow(max(dot(N, H), 0.0), 32.0);

        // Add specular
        color += vec3<f32>(1.0, 0.9, 0.8) * spec * honey_mix * 0.8;

        // Darken borders slightly for separation
        let border = smoothstep(0.48, 0.5, hex_dist);
        color = mix(color, vec3<f32>(0.2, 0.1, 0.0), border * honey_mix * 0.5);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}

fn mod(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
    return x - y * floor(x / y);
}
