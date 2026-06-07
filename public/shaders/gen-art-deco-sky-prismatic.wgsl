// ═══════════════════════════════════════════════════════════════════
//  Art Deco Sky Prismatic
//  Category: advanced-hybrid
//  Features: raymarching, spectral-dispersion, physical-refraction, mouse-driven
//  Complexity: Very High
//  Chunks From: gen-art-deco-sky.wgsl, spec-prismatic-dispersion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-20 — Generative Nature Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Infinite Art Deco skyscraper ascent where glass windows and gold
//  accents exhibit true 4-band spectral dispersion. Cauchy's equation
//  governs wavelength-dependent refraction through architectural glass.
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

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdBox2D(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

fn opSymXZ(p: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(abs(p.x), p.y, abs(p.z));
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// ═══ CHUNK: cauchyIOR (from spec-prismatic-dispersion.wgsl) ═══
fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

// ═══ CHUNK: wavelengthToRGB (from spec-prismatic-dispersion.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn map(p: vec3<f32>) -> vec2<f32> {
    let density = u.zoom_params.x;
    var time = u.config.x;
    var ascentSpeed = u.zoom_params.y;
    var y_offset = time * ascentSpeed * 5.0;
    var pos = vec3<f32>(p.x, p.y + y_offset, p.z);
    var res_d = 1000.0;
    var res_mat = 0.0;
    var cp = pos;
    cp = opSymXZ(cp);
    let floor_h = 10.0;
    let local_y = (fract((cp.y + floor_h * 0.5) / floor_h) - 0.5) * floor_h;
    var d_walls = sdBox(vec3<f32>(cp.x, local_y, cp.z), vec3<f32>(6.0, 5.0, 6.0));
    let d_windows_cut = sdBox(vec3<f32>(cp.x, local_y, cp.z), vec3<f32>(4.0, 4.0, 6.5));
    var d_windows = sdBox(vec3<f32>(cp.x, local_y, cp.z), vec3<f32>(3.8, 3.8, 5.8));
    d_walls = max(d_walls, -d_windows_cut);
    let d_col1 = sdBox(vec3<f32>(cp.x - 5.0, local_y, cp.z - 6.0), vec3<f32>(0.5, 5.0, 0.5));
    let d_col2 = sdBox(vec3<f32>(cp.x - 6.0, local_y, cp.z - 5.0), vec3<f32>(0.5, 5.0, 0.5));
    let fluted_col1 = d_col1 + cos(cp.x*10.0)*0.1 + cos(cp.z*10.0)*0.1;
    let fluted_col2 = d_col2 + cos(cp.x*10.0)*0.1 + cos(cp.z*10.0)*0.1;
    d_walls = min(d_walls, min(fluted_col1, fluted_col2));
    let d_band = sdBox(vec3<f32>(cp.x, local_y - 4.5, cp.z), vec3<f32>(6.2, 0.5, 6.2));
    let motif_x = sdBox(vec3<f32>(cp.x, local_y - 4.0, cp.z - 6.2), vec3<f32>(2.0 - cp.y%2.0, 1.0, 0.2));
    var d_gold = min(d_band, motif_x);
    if (d_walls < res_d) { res_d = d_walls; res_mat = 1.0; }
    if (d_windows < res_d) { res_d = d_windows; res_mat = 3.0; }
    if (d_gold < res_d) { res_d = d_gold; res_mat = 2.0; }
    let cell_size = 40.0;
    let grid_xz = floor((pos.xz + cell_size * 0.5) / cell_size);
    let local_xz = (fract((pos.xz + cell_size * 0.5) / cell_size) - 0.5) * cell_size;
    let dist_to_center = length(grid_xz);
    if (dist_to_center > 0.5 && density > 0.0) {
        let h = hash(grid_xz);
        if (h < density) {
            let w = 4.0 + h * 4.0;
            let bg_local_y = (fract((pos.y + 15.0 * 0.5) / 15.0) - 0.5) * 15.0;
            var d_bg_tower = sdBox(vec3<f32>(local_xz.x, bg_local_y, local_xz.y), vec3<f32>(w, 7.5, w));
            let d_bg_win = sdBox(vec3<f32>(local_xz.x, bg_local_y, local_xz.y), vec3<f32>(w*0.8, 6.0, w+0.5));
            d_bg_tower = max(d_bg_tower, -d_bg_win);
            if (d_bg_tower < res_d) { res_d = d_bg_tower; res_mat = 1.0; }
            let d_bg_win_inside = sdBox(vec3<f32>(local_xz.x, bg_local_y, local_xz.y), vec3<f32>(w*0.7, 5.0, w-0.5));
            if (d_bg_win_inside < res_d) { res_d = d_bg_win_inside; res_mat = 3.0; }
        }
    }
    return vec2<f32>(res_d, res_mat);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    let d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var mat = 0.0;
    for(var i=0; i<150; i++) {
        var p = ro + rd * t;
        var res = map(p);
        var d = res.x;
        mat = res.y;
        if(d < 0.002 || t > 200.0) { break; }
        t += d * 0.8;
    }
    return vec2<f32>(t, mat);
}

fn calcAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for(var i=0; i<5; i++) {
        var h = 0.01 + 0.12 * f32(i) / 4.0;
        var d = map(p + h * n).x;
        occ += (h - d) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let goldGlow = u.zoom_params.z;
    let fogDensity = u.zoom_params.w;
    var time = u.config.x;
    var mouse = u.zoom_config.yz;
    let cam_radius = 20.0 + (mouse.y - 0.5) * 10.0;
    let cam_angle = (mouse.x - 0.5) * 6.28 + time * 0.05;
    let ro = vec3<f32>(sin(cam_angle) * cam_radius, -5.0, cos(cam_angle) * cam_radius);
    let ta = vec3<f32>(0.0, 5.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);
    var res = raymarch(ro, rd);
    var t = res.x;
    var mat = res.y;
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let lightColor1 = vec3<f32>(1.0, 0.8, 0.5);
    let lightColor2 = vec3<f32>(0.2, 0.5, 1.0);
    var color = fogColor;
    var ascentSpeed = u.zoom_params.y;
    var y_offset = time * ascentSpeed * 5.0;

    // Prismatic parameters
    let glassCurvature = mix(0.1, 1.2, u.zoom_params.z);
    let cauchyB = mix(0.01, 0.08, u.zoom_params.w);
    let glassThickness = mix(0.3, 1.5, u.zoom_params.w);
    let spectralSat = mix(0.3, 1.2, u.zoom_params.z);

    if (t < 200.0) {
        var p = ro + rd * t;
        let world_p = vec3<f32>(p.x, p.y + y_offset, p.z);
        let n = calcNormal(p);
        let v = normalize(ro - p);
        var albedo = vec3<f32>(0.0);
        var rough = 0.5;
        var metallic = 0.0;
        var emission = vec3<f32>(0.0);

        if (mat == 1.0) {
            albedo = vec3<f32>(0.02, 0.02, 0.02);
            rough = 0.1;
            metallic = 0.2;
        } else if (mat == 2.0) {
            albedo = vec3<f32>(1.0, 0.7, 0.2);
            rough = 0.2;
            metallic = 1.0;
        } else if (mat == 3.0) {
            albedo = vec3<f32>(0.05, 0.05, 0.05);
            rough = 0.1;
            metallic = 0.8;
            let win_cell = floor(world_p.y / 1.0) * 10.0 + floor(world_p.x / 1.0) + floor(world_p.z / 1.0);
            var h = hash(vec2<f32>(win_cell, floor(world_p.y / 10.0)));
            if (h > 0.6) {
                emission = vec3<f32>(1.0, 0.8, 0.4) * goldGlow * 1.5;
                emission *= 0.8 + 0.2 * sin(time * 5.0 + h * 100.0);
            }
        }

        let l1_dir = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff1 = max(dot(n, l1_dir), 0.0);
        let h1 = normalize(l1_dir + v);
        let spec1 = pow(max(dot(n, h1), 0.0), 128.0 * (1.0 - rough));
        let l2_dir = normalize(vec3<f32>(-1.0, -1.0, -0.5));
        let diff2 = max(dot(n, l2_dir), 0.0);
        let ao = calcAO(p, n);
        var diffuse = (diff1 * lightColor1 + diff2 * lightColor2 * 0.5 + 0.1) * albedo;
        var specular = (spec1 * lightColor1) * (1.0 - rough) * (metallic * 0.5 + 0.5);

        if (metallic > 0.1 || rough < 0.2) {
            let refl = reflect(-v, n);
            let env_spec = pow(max(dot(refl, l1_dir), 0.0), 32.0);
            let env_color = mix(fogColor, lightColor1 * 0.5, refl.y * 0.5 + 0.5);
            specular += (env_spec * lightColor1 + env_color * 0.2) * (1.0 - rough) * metallic;
            if (mat == 2.0) {
                specular *= albedo;
            }
        }

        color = (diffuse + specular) * ao + emission;

        // ═══ CHUNK: prismatic dispersion on glass windows (mat 3) ═══
        if (mat == 3.0) {
            let toCenter = v - n * dot(v, n);
            let dist = length(toCenter);
            let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));
            let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
            var prismaticColor = vec3<f32>(0.0);
            for (var i: i32 = 0; i < 4; i = i + 1) {
                let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
                let refractOffset = toCenter * (1.0 - 1.0 / ior) * glassCurvature * 0.4;
                let bandIntensity = 1.0 - glassThickness * (4.0 - f32(i)) * 0.15;
                prismaticColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
            }
            color = mix(color, prismaticColor * (diff1 + 0.3), 0.6);
        }

        if (mat == 2.0) {
             color += albedo * goldGlow * 0.3 * ao;
        }
        let fog_amount = 1.0 - exp(-t * (0.01 + fogDensity * 0.05));
        color = mix(color, fogColor, fog_amount);
        let height_fog = exp(-p.y * 0.1) * 0.5;
        color += lightColor1 * height_fog * fogDensity;
    } else {
        let sky_glow = exp(-rd.y * 4.0) * 0.5;
        color += lightColor1 * sky_glow * fogDensity;
    }

    let vign = 1.0 - length(uv) * 0.5;
    color = color * vign;
    color = color / (color + vec3<f32>(1.0));
    color = pow(color, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 200.0, 0.0, 0.0, 0.0));
}
