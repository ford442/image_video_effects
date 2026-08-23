// ═══════════════════════════════════════════════════════════════════
//  Glass Bead Curtain Iridescence
//  Category: advanced-hybrid
//  Features: mouse-driven, refraction, thin-film-interference, spectral-render
//  Complexity: Very High
//  Chunks From: glass-bead-curtain, spec-iridescence-engine
//  Created: 2026-04-18
//  By: Agent CB-24 — Glass & Reflection Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Each glass bead in the curtain acts as a spherical thin-film lens.
//  Combines physical Beer-Lambert transmission with thin-film
//  interference (soap-bubble iridescence) on the bead surface.
//  Mouse interaction parts the curtain while exciting local
//  interference patterns.
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

// ═══ CHUNK: hash12 (from spec-iridescence-engine) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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
    for (var lambda = 380.0; lambda <= 700.0; lambda += 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount += 1.0;
    }
    return color / max(sampleCount, 1.0);
}

fn aces_tone_map(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let dt = u.config.y;
    let time = u.config.x;
    
    // extraBuffer State Update (bounded spring)
    if (global_id.x == 0u && global_id.y == 0u) {
        let mouse_down = f32(u.zoom_config.x > 0.0);
        let curr_val = extraBuffer[133];
        let curr_vel = extraBuffer[134];
        let target = mouse_down;
        let spring_force = (target - curr_val) * 15.0;
        let damping = curr_vel * 5.0;
        var new_vel = curr_vel + (spring_force - damping) * dt;
        var new_val = curr_val + new_vel * dt;
        
        new_val = clamp(new_val, 0.0, 1.0);
        if (new_val == 0.0 || new_val == 1.0) { new_vel = 0.0; }
        
        extraBuffer[133] = new_val;
        extraBuffer[134] = new_vel;
        
        var bass = 0.0;
        var mid = 0.0;
        var treble = 0.0;
        for (var i = 0u; i < 4u; i++) {
            bass += plasmaBuffer[i].x;
        }
        for (var i = 4u; i < 10u; i++) {
            mid += plasmaBuffer[i].x;
        }
        for (var i = 10u; i < 16u; i++) {
            treble += plasmaBuffer[i].x;
        }
        extraBuffer[135] = bass * 0.25;
        extraBuffer[136] = mid * 0.16666;
        extraBuffer[137] = treble * 0.16666;
        extraBuffer[138] = extraBuffer[138] + dt;
    }
    workgroupBarrier();

    let pointer_intensity = extraBuffer[133];
    let audio_bass = extraBuffer[135];
    let audio_mid = extraBuffer[136];
    let audio_treble = extraBuffer[137];
    let global_time = extraBuffer[138];
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { mouse = vec2<f32>(0.5, 0.5); }

    let bead_size = mix(10.0, 100.0, u.zoom_params.x) * (1.0 + audio_bass * 0.1);
    let refraction_str = u.zoom_params.y;
    let iridescence_intensity = mix(0.0, 1.5, u.zoom_params.z) * (1.0 + audio_mid * 0.5);
    let film_thickness_base = mix(200.0, 800.0, u.zoom_params.w) * (1.0 + audio_treble * 0.2);

    let aspect = resolution.x / resolution.y;
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    var ripple_disp = vec2<f32>(0.0);
    for (var i = 0u; i < 50u; i++) {
        let r = u.ripples[i];
        if (r.w > 0.0) {
            let d_vec = (uv - r.xy) * vec2<f32>(aspect, 1.0);
            let d = length(d_vec);
            let phase = r.z - d * 15.0;
            if (phase > 0.0 && phase < 3.14159) {
                let wave = sin(phase) * (1.0 - r.w);
                ripple_disp += normalize(d_vec) * wave * 0.05 * r.w;
            }
        }
    }
    
    let repel_radius = 0.3 * (1.0 + pointer_intensity * 0.5);
    let interact = smoothstep(repel_radius, 0.0, dist) * pointer_intensity;
    let disp = normalize(dist_vec) * interact * 0.3 + ripple_disp;
    let active_uv = uv - vec2<f32>(disp.x / aspect, disp.y);
    
    let px_active = active_uv * resolution;
    let cell_uv = fract(px_active / bead_size) - 0.5;
    let r_cell = length(cell_uv);
    
    var final_uv = active_uv;
    var color = vec3<f32>(0.0);
    var alpha = 0.0;
    
    if (r_cell < 0.5) {
        let z = sqrt(max(0.0, 0.25 - r_cell * r_cell));
        let normal = normalize(vec3<f32>(cell_uv, z));
        let glass_thickness = 2.0 * z;
        
        final_uv = active_uv - normal.xy * refraction_str * 0.5;
        
        let viewDir = vec3<f32>(0.0, 0.0, 1.0);
        let cos_theta = abs(dot(viewDir, normal));
        let R0 = 0.04;
        let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
        
        let glass_color = vec3<f32>(0.95, 0.98, 1.0);
        let absorption = exp(-(vec3<f32>(1.0) - glass_color) * glass_thickness * 1.5);
        let transmission = (1.0 - fresnel) * dot(absorption, vec3<f32>(0.333));
        
        let load_coord = clamp(vec2<i32>(final_uv * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
        let bg_tex = textureLoad(dataTextureC, load_coord, 0).rgb;
        let baseColor = mix(textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).rgb, bg_tex, 0.5);
        color = baseColor * glass_color;
        
        let cosThetaFilm = sqrt(max(1.0 - r_cell * r_cell * 0.5, 0.01));
        let noiseVal = hash12(active_uv * 12.0 + global_time * 0.1) * 0.5
                     + hash12(active_uv * 25.0 - global_time * 0.15) * 0.25;
        let filmThickness = film_thickness_base * (0.7 + noiseVal * 0.6);
        let filmIOR = 1.5;
        let iridescent = thinFilmColor(filmThickness, cosThetaFilm, filmIOR) * iridescence_intensity;
        
        let iridBlend = fresnel * iridescence_intensity;
        color = mix(color, iridescent, iridBlend * 0.7);
        
        let light_dir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
        let spec = pow(max(dot(normal, light_dir), 0.0), 20.0);
        color += spec * 0.5;
        
        alpha = transmission;
    } else {
        color = textureSampleLevel(readTexture, u_sampler, active_uv, 0.0).rgb;
        alpha = 0.0;
    }
    
    let final_color = aces_tone_map(color);
    let out_color = vec4<f32>(final_color, alpha);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), out_color);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), out_color);
    
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
