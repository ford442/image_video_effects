// ═══════════════════════════════════════════════════════════════════
//  crystal-illuminator-iridescence
//  Category: advanced-hybrid
//  Features: voronoi-facets, thin-film-interference, fresnel,
//            mouse-driven, depth-aware
//  Complexity: Very High
//  Chunks From: crystal-illuminator.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-16 — Generative & Cosmic Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Faceted glass/gemstone rendered with thin-film interference on
//  each crystal facet. Each Voronoi cell gets a unique film thickness
//  derived from its normal and depth. Mouse light source creates
//  traveling iridescent caustics across the facet structure.
// ═══════════════════════════════════════════════════════════════════

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

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn fresnelIOR(cosTheta: f32, ior: f32) -> f32 {
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
    return fresnelSchlick(cosTheta, F0);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    let cell_density = mix(5.0, 30.0, u.zoom_params.x);
    let iorMix = u.zoom_params.y;
    let light_power = u.zoom_params.z * 2.0;
    let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.w);
    let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
    let intensity = 1.0;

    let IOR_QUARTZ: f32 = 1.54;
    let IOR_DIAMOND: f32 = 2.42;
    let ior = mix(IOR_QUARTZ, IOR_DIAMOND, iorMix);
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

    // Voronoi grid
    let uv_scaled = uv * cell_density;
    let uv_id = floor(uv_scaled);
    let uv_st = fract(uv_scaled);

    var min_dist = 100.0;
    var second_min_dist = 100.0;
    var cell_center = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);

    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let seed = hash22(uv_id + neighbor);
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

    // Facet normal
    let n_hash = hash22(cell_id + vec2<f32>(12.34, 56.78));
    var facet_normal = normalize(vec3<f32>(n_hash.x - 0.5, n_hash.y - 0.5, 0.5));
    let local_uv = uv_st - cell_center;
    let curvature = vec3<f32>(local_uv, sqrt(max(0.0, 1.0 - dot(local_uv, local_uv))));
    let roughness = 0.2;
    facet_normal = normalize(mix(facet_normal, curvature, roughness));

    // Light from mouse
    let mouse = u.zoom_config.yz;
    let light_pos = vec3<f32>(mouse, 0.2);
    let pixel_pos = vec3<f32>(uv, 0.0);
    let light_vec = light_pos - pixel_pos;
    let light_dist = length(light_vec);
    let light_dir = normalize(light_vec);
    let view_dir = vec3<f32>(0.0, 0.0, 1.0);
    let cosTheta = max(dot(facet_normal, view_dir), 0.0);
    let fresnel = fresnelIOR(cosTheta, ior);

    let edge_dist = second_min_dist - min_dist;
    let edge_factor = smoothstep(0.05, 0.0, edge_dist);

    let diffuse = max(0.0, dot(facet_normal, light_dir));
    let specular = pow(max(0.0, dot(reflect(-light_dir, facet_normal), view_dir)), 32.0);
    let attenuation = 1.0 / (1.0 + light_dist * light_dist * 10.0);
    let lighting = (diffuse + specular) * light_power * attenuation;
    let ambient = 0.5;

    let refract_offset = facet_normal.xy * 0.1 * (ior - 1.0);
    let read_uv = uv + refract_offset;
    var tex_color = textureSampleLevel(readTexture, u_sampler, read_uv, 0.0);

    // ═══ Thin-Film Iridescence per Facet ═══
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let toCenter = uv - vec2<f32>(0.5);
    let distCenter = length(toCenter);
    let viewCosTheta = sqrt(max(1.0 - distCenter * distCenter * 0.5, 0.01));

    // Unique film thickness per facet based on cell hash + depth
    let cellThickness = filmThicknessBase * (0.7 + depth * 0.6 + hash21(cell_id) * 0.3);
    let mouseDist = length(uv - mouse);
    let mouseInfluence = exp(-mouseDist * mouseDist * 800.0) * u.zoom_config.w;
    var thickness = cellThickness + mouseInfluence * 300.0 * sin(time * 3.0 + mouseDist * 30.0);

    let iridescent = thinFilmColor(thickness, viewCosTheta, filmIOR) * intensity;

    // Fresnel blend
    let fresnelBlend = pow(1.0 - viewCosTheta, 3.0);
    let facetColor = mix(tex_color.rgb, iridescent, fresnelBlend * 0.7);

    // Combine lighting
    var final_color = facetColor * (ambient + lighting);
    final_color = final_color + vec3<f32>(specular * attenuation * light_power);
    final_color = final_color + vec3<f32>(fresnel * 0.3);

    // Edge iridescence boost
    final_color = mix(final_color, iridescent * 1.5, edge_factor * 0.5);

    // Transmission alpha
    let path_length = mix(0.05, 0.3, min_dist * 2.0);
    let cell_purity = 0.6 + 0.4 * hash21(cell_id);
    let absorptionCoeff = mix(0.3, 2.0, 1.0 - cell_purity);
    let absorption = exp(-absorptionCoeff * path_length);
    let transmission = absorption * (1.0 - fresnel) * cell_purity;
    let tir = smoothstep(0.3, 0.0, cosTheta) * 0.3;
    let alpha = clamp(transmission + tir, 0.2, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(final_color, alpha));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
}
