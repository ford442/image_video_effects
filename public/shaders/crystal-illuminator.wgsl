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

// Random hash function
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let cell_density = mix(5.0, 30.0, u.zoom_params.x);
    let refraction_strength = u.zoom_params.y * 0.1;
    let light_power = u.zoom_params.z * 2.0;
    let roughness = u.zoom_params.w;

    // Voronoi Grid
    let uv_scaled = uv * cell_density;
    let uv_id = floor(uv_scaled);
    let uv_st = fract(uv_scaled);

    var min_dist = 100.0;
    var cell_center = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);

    // Search 3x3 neighbors
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let seed = hash22(uv_id + neighbor);

            // Animate seeds slightly for organic feel
            let anim = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * seed);
            let p = neighbor + seed * anim;

            let dist = length(uv_st - p);

            if (dist < min_dist) {
                min_dist = dist;
                cell_center = p;
                cell_id = uv_id + neighbor;
            }
        }
    }

    // Facet Normal Calculation
    // We generate a random normal per cell, effectively making it a flat facet.
    // Map hash to -1..1 range
    let n_hash = hash22(cell_id + vec2<f32>(12.34, 56.78));
    var facet_normal = normalize(vec3<f32>(n_hash.x - 0.5, n_hash.y - 0.5, 0.5)); // Points mostly towards Z

    // Mix with smooth normal (sphere-like) based on distance from center for "gem" look
    let local_uv = uv_st - cell_center;
    let curvature = vec3<f32>(local_uv, sqrt(max(0.0, 1.0 - dot(local_uv, local_uv))));
    facet_normal = normalize(mix(facet_normal, curvature, roughness));

    // Light Calculation
    // Mouse is the light source in UV space (z=0.2 above surface)
    let light_pos = vec3<f32>(mouse, 0.2);
    let pixel_pos = vec3<f32>(uv, 0.0);
    let light_vec = light_pos - pixel_pos;
    let light_dist = length(light_vec);
    let light_dir = normalize(light_vec);

    // Diffuse / Specular
    let diffuse = max(0.0, dot(facet_normal, light_dir));
    let specular = pow(max(0.0, dot(reflect(-light_dir, facet_normal), vec3<f32>(0.0, 0.0, 1.0))), 32.0);

    // Light attenuation
    let attenuation = 1.0 / (1.0 + light_dist * light_dist * 10.0);
    let lighting = (diffuse + specular) * light_power * attenuation;

    // Ambient light
    let ambient = 0.5;

    // Refraction
    // Offset read coordinate based on facet normal xy
    let refract_offset = facet_normal.xy * refraction_strength;
    let read_uv = uv + refract_offset;

    // Sample Texture
    let tex_color = textureSampleLevel(readTexture, u_sampler, read_uv, 0.0);

    // Combine
    var final_color = tex_color * (ambient + lighting);

    // Add extra sparkle for specular
    final_color = final_color + vec4<f32>(specular * attenuation * light_power, specular * attenuation * light_power, specular * attenuation * light_power, 0.0);

    // Debug mouse light
    // if (light_dist < 0.01) { final_color = vec4<f32>(1.0, 1.0, 1.0, 1.0); }

    textureStore(writeTexture, global_id.xy, final_color);

    // Depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
