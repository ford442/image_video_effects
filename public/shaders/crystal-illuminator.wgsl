// ═══════════════════════════════════════════════════════════════
//  Crystal Illuminator - Physical Light Transmission with Alpha
//  Category: interactive-mouse
//  Features: mouse-driven, voronoi facets, facet lighting
//  Simulates faceted glass/gemstone with physical transmission
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Refractive indices
const IOR_QUARTZ: f32 = 1.54;
const IOR_DIAMOND: f32 = 2.42;
const IOR_SAPPHIRE: f32 = 1.77;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Fresnel-Schlick approximation
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Fresnel reflectance with IOR
fn fresnelIOR(cosTheta: f32, ior: f32) -> f32 {
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
    return fresnelSchlick(cosTheta, F0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // ═══════════════════════════════════════════════════════════════
    // Parameters:
    // x: cell_density (facet size)
    // y: refraction_strength + IOR mix
    // z: light_power
    // w: crystal purity
    // ═══════════════════════════════════════════════════════════════
    
    let cell_density = mix(5.0, 30.0, u.zoom_params.x);
    let iorMix = u.zoom_params.y; // 0 = quartz, 1 = diamond
    let light_power = u.zoom_params.z * 2.0;
    let purity = u.zoom_params.w;
    let roughness = (1.0 - purity) * 0.5;

    // Calculate IOR
    let ior = mix(IOR_QUARTZ, IOR_DIAMOND, iorMix);
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

    // Voronoi Grid
    let uv_scaled = uv * cell_density;
    let uv_id = floor(uv_scaled);
    let uv_st = fract(uv_scaled);

    var min_dist = 100.0;
    var second_min_dist = 100.0;
    var cell_center = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);

    // Search 3x3 neighbors
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let seed = hash22(uv_id + neighbor);

            // Animate seeds slightly for organic feel
            let anim = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * seed);
            var p = neighbor + seed * anim;

            let dist = length(uv_st - p);

            if (dist < min_dist) {
                second_min_dist = min_dist;
                min_dist = dist;
                cell_center = p;
                cell_id = uv_id + neighbor;
            } else if (dist < second_min_dist) {
                second_min_dist = dist;
            }
        }
    }

    // Facet Normal Calculation
    let n_hash = hash22(cell_id + vec2<f32>(12.34, 56.78));
    var facet_normal = normalize(vec3<f32>(n_hash.x - 0.5, n_hash.y - 0.5, 0.5));

    // Mix with smooth normal based on distance from center
    let local_uv = uv_st - cell_center;
    let curvature = vec3<f32>(local_uv, sqrt(max(0.0, 1.0 - dot(local_uv, local_uv))));
    facet_normal = normalize(mix(facet_normal, curvature, roughness));

    // ═══════════════════════════════════════════════════════════════
    // Light & Physical Transmission Calculation
    // ═══════════════════════════════════════════════════════════════
    
    // Mouse is the light source in UV space (z=0.2 above surface)
    let light_pos = vec3<f32>(mouse, 0.2);
    let pixel_pos = vec3<f32>(uv, 0.0);
    let light_vec = light_pos - pixel_pos;
    let light_dist = length(light_vec);
    let light_dir = normalize(light_vec);

    // View direction
    let view_dir = vec3<f32>(0.0, 0.0, 1.0);
    
    // Angle between view and facet normal for Fresnel
    let cosTheta = max(dot(facet_normal, view_dir), 0.0);
    
    // Fresnel reflection at surface
    let fresnel = fresnelIOR(cosTheta, ior);
    
    // Distance to cell edge (for edge effects)
    let edge_dist = second_min_dist - min_dist;
    let edge_factor = smoothstep(0.05, 0.0, edge_dist);

    // Diffuse / Specular lighting
    let diffuse = max(0.0, dot(facet_normal, light_dir));
    let specular = pow(max(0.0, dot(reflect(-light_dir, facet_normal), view_dir)), 32.0);

    // Light attenuation
    let attenuation = 1.0 / (1.0 + light_dist * light_dist * 10.0);
    let lighting = (diffuse + specular) * light_power * attenuation;

    // Ambient light
    let ambient = 0.5;

    // Refraction
    let refract_offset = facet_normal.xy * 0.1 * (ior - 1.0);
    let read_uv = uv + refract_offset;

    // Sample Texture
    var tex_color = textureSampleLevel(readTexture, u_sampler, read_uv, 0.0);

    // ═══════════════════════════════════════════════════════════════
    // Transmission & Alpha Calculation
    // ═══════════════════════════════════════════════════════════════
    
    // Path length through facet (thicker at center)
    let path_length = mix(0.05, 0.3, min_dist * 2.0) / max(purity, 0.1);
    
    // Per-cell purity variation
    let cell_purity = purity * (0.6 + 0.4 * hash21(cell_id));
    
    // Absorption based on path length and purity
    let absorptionCoeff = mix(0.3, 2.0, 1.0 - cell_purity);
    let absorption = exp(-absorptionCoeff * path_length);
    
    // Transmission coefficient (alpha)
    // Face-on: mostly transmitted (high alpha)
    // Edge-on/grazing: mostly reflected (low alpha)
    let transmission = absorption * (1.0 - fresnel) * cell_purity;
    
    // Edge darkening (total internal reflection at steep angles)
    let tir = smoothstep(0.3, 0.0, cosTheta) * 0.3;
    
    // Combine lighting with transmission
    var final_color = tex_color * (ambient + lighting);
    
    // Add specular highlight
    final_color = final_color + vec4<f32>(specular * attenuation * light_power);
    
    // Add edge reflections
    final_color = final_color + vec4<f32>(fresnel * 0.3);
    
    // Apply transmission as alpha
    let alpha = clamp(transmission, 0.2, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color.rgb, alpha));

    // Depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
