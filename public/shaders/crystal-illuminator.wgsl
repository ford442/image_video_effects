// ═══════════════════════════════════════════════════════════════
//  Crystal Illuminator - Physical Light Transmission with Alpha
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, alpha-transmission, physical-refraction
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: Snell vector refraction through the facet (§12.2F); total internal reflection past the critical angle (ior sets the TIR share); arris bevel glints along facet seams; click glint front per whole facet
//  A packing: ACES display RGBA (C not read)
//  Simulates faceted glass/gemstone with physical transmission
//  Rescue: HEAD did not compile (duplicate `aspect`, `__finalRGB`); full-screen rainbow clock rings cut (not a crystal artifact)
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    // ═══════════════════════════════════════════════════════════════
    // Parameters:
    // x: cell_density (facet size)
    // y: refraction_strength + IOR mix
    // z: light_power
    // w: crystal purity
    // ═══════════════════════════════════════════════════════════════
    let cell_density = mix(5.0, 30.0, u.zoom_params.x);
    let iorMix = u.zoom_params.y; // 0 = quartz, 1 = diamond
    let light_power = u.zoom_params.z * 2.0 * (1.0 + bass * 0.3);
    let purity = u.zoom_params.w;
    let roughness = (1.0 - purity) * 0.5;

    // Calculate IOR
    let ior = mix(IOR_QUARTZ, IOR_DIAMOND, iorMix);

    // Voronoi Grid
    let uv_scaled = uv * cell_density;
    let uv_id = floor(uv_scaled);
    let uv_st = fract(uv_scaled);

    var min_dist = 100.0;
    var second_min_dist = 100.0;
    var cell_center = vec2<f32>(0.0);
    var second_center = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);

    // Search 3x3 neighbors (also remember the 2nd-nearest site: it gives the seam direction)
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let seed = hash22(uv_id + neighbor);

            // Animate seeds slightly for organic feel
            let anim = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * seed);
            let p = neighbor + seed * anim;

            let dist = length(uv_st - p);

            if (dist < min_dist) {
                second_min_dist = min_dist;
                second_center = cell_center;
                min_dist = dist;
                cell_center = p;
                cell_id = uv_id + neighbor;
            } else if (dist < second_min_dist) {
                second_min_dist = dist;
                second_center = p;
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

    // Distance to the seam between this facet and its neighbour
    let edge_dist = second_min_dist - min_dist;

    // ── Idea 3: arris bevel ───────────────────────────────────────────
    // A cut gem's facets meet in chamfered ridges (arrises). Inside a narrow band
    // of edge_dist the normal tilts toward the neighbouring site, so each seam is
    // a small V-groove: it refracts hard and one slope catches the lamp.
    let seam_dir = normalize(second_center - cell_center + vec2<f32>(1e-5, 0.0));
    let bevel = 1.0 - smoothstep(0.0, 0.16, edge_dist);
    let bevel_n = normalize(vec3<f32>(seam_dir * 0.95, 1.0));
    facet_normal = normalize(mix(facet_normal, bevel_n, bevel * 0.85));

    // ═══════════════════════════════════════════════════════════════
    // Light & Physical Transmission Calculation
    // ═══════════════════════════════════════════════════════════════

    // Mouse is the light source (z=0.2 above surface); aspect-corrected so the pool is round
    let light_vec = vec3<f32>((mouse.x - uv.x) * aspect, mouse.y - uv.y, 0.2);
    let light_dist = length(light_vec);
    let light_dir = light_vec / max(light_dist, 1e-4);

    // View direction
    let view_dir = vec3<f32>(0.0, 0.0, 1.0);

    // Angle between view and facet normal for Fresnel
    let cosTheta = max(dot(facet_normal, view_dir), 0.0);

    // Fresnel reflection at surface
    let fresnel = fresnelIOR(cosTheta, ior);

    // Diffuse / Specular lighting
    let diffuse = max(0.0, dot(facet_normal, light_dir));
    let mirror_dir = reflect(-light_dir, facet_normal);
    let specular = pow(max(0.0, dot(mirror_dir, view_dir)), 32.0);

    // Light attenuation
    let attenuation = 1.0 / (1.0 + light_dist * light_dist * 10.0);
    let lighting = (diffuse + specular) * light_power * attenuation;

    // Ambient light
    let ambient = 0.5;

    // ── Idea 1: Snell vector refraction through the facet (§12.2F) ───
    // The view ray enters the facet with eta = 1/ior and travels a slab
    // thickness; where it comes out is the sample point. Facet slope and ior
    // both bend it the way glass does (HEAD used one small-angle tap).
    let in_ray = refract(vec3<f32>(0.0, 0.0, -1.0), facet_normal, 1.0 / ior);
    let slab = 0.16;
    let refract_offset = in_ray.xy / max(-in_ray.z, 0.3) * slab;
    let read_uv = clamp(uv + refract_offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let tex_rgb = textureSampleLevel(readTexture, u_sampler, read_uv, 0.0).rgb;

    // ── Idea 2: total internal reflection at the critical angle ──────
    // The refracted ray inside meets a pavilion facet (second hash of the same
    // cell). Past sin(theta_c) = 1/ior it is mirrored back out instead of
    // leaving: quartz theta_c = 40.5 deg, diamond 24.4 deg, so the ior slider sets
    // how many facets go bright-and-dark (brilliance) rather than clear.
    let pav_h = hash22(cell_id + vec2<f32>(91.7, 13.3));
    let pav_n = normalize(vec3<f32>(pav_h.x - 0.5, pav_h.y - 0.5, 0.5));
    let cos_inc = clamp(-dot(in_ray, pav_n), 0.0, 1.0);
    let cos_crit = sqrt(max(1.0 - 1.0 / (ior * ior), 0.0));
    let tir = 1.0 - smoothstep(cos_crit - 0.05, cos_crit + 0.05, cos_inc);
    // the mirrored ray leaves through another part of the crystal: a second,
    // energy-reduced sample, plus a second lamp glint off the pavilion facet
    let bounce = reflect(in_ray, pav_n);
    let bounce_uv = clamp(read_uv + bounce.xy / max(bounce.z, 0.5) * 0.06, vec2<f32>(0.0), vec2<f32>(1.0));
    let bounce_rgb = textureSampleLevel(readTexture, u_sampler, bounce_uv, 0.0).rgb * 0.55;
    let pav_spec = pow(max(0.0, dot(reflect(-light_dir, pav_n), view_dir)), 24.0);
    let tir_glint = tir * (0.15 + 0.85 * pav_spec) * attenuation * light_power * 0.6;

    // ═══════════════════════════════════════════════════════════════
    // Transmission & Alpha Calculation
    // ═══════════════════════════════════════════════════════════════

    // Path length through facet (thicker at center)
    let path_length = mix(0.05, 0.3, clamp(min_dist * 2.0, 0.0, 1.0)) / max(purity, 0.1);

    // Per-cell purity variation
    let cell_purity = purity * (0.6 + 0.4 * hash21(cell_id));

    // Absorption based on path length and purity
    let absorptionCoeff = mix(0.3, 2.0, 1.0 - cell_purity);
    let absorption = exp(-absorptionCoeff * path_length);

    // Transmission coefficient (alpha)
    // Face-on: mostly transmitted (high alpha)
    // Edge-on/grazing and TIR facets: mostly reflected (low alpha)
    let transmission = absorption * (1.0 - fresnel) * cell_purity * (1.0 - 0.3 * tir);

    // Combine lighting with transmission
    var rgb = mix(tex_rgb, bounce_rgb, tir) * (ambient + lighting);

    // Add specular highlight
    rgb = rgb + vec3<f32>(specular * attenuation * light_power);

    // Add edge reflections
    rgb = rgb + vec3<f32>(fresnel * 0.3);

    // second glint of the TIR facets
    rgb = rgb + vec3<f32>(tir_glint);

    // arris glint: the seam slope that faces the lamp (treble sharpens it)
    let arris_spec = pow(max(0.0, dot(mirror_dir, view_dir)), 12.0);
    rgb = rgb + vec3<f32>(1.0, 0.97, 0.9) * bevel * arris_spec * attenuation * light_power * (0.6 + treble * 1.2);

    // ── Idea 4: a click strikes the gem, facet by facet ──────────────
    // HEAD painted a rainbow ring over the picture here. The same front (timing and
    // decay kept) is now evaluated at each cell's SITE, so a whole facet flashes once
    // as the front passes it, with a per-facet strength.
    let site_uv = (uv_id + cell_center) / cell_density;
    var click = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        let d = length((site_uv - event.xy) * vec2<f32>(aspect, 1.0));
        click += exp(-age * 1.8) * exp(-abs(d - age * 0.38) * 14.0) * step(age, 3.5);
    }
    let facet_flash = min(click, 1.5) * (0.55 + 0.45 * hash21(cell_id + vec2<f32>(3.1, 7.7)));
    rgb = rgb + vec3<f32>(1.0, 0.97, 0.92) * facet_flash * 0.5;

    // Apply transmission as alpha (a flashing facet is lit from within: more opaque)
    let alpha = clamp(transmission + facet_flash * 0.25, 0.2, 1.0);

    let display = acesToneMap(clamp(rgb, vec3<f32>(0.0), vec3<f32>(4.0)));
    let outCol = vec4<f32>(display, alpha);
    textureStore(writeTexture, coord, outCol);
    textureStore(dataTextureA, coord, outCol);

    // Depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
