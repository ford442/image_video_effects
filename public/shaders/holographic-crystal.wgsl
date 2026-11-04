// ═══════════════════════════════════════════════════════════════════
//  Holographic Crystal
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, continuous-geometry
//  Complexity: High
//  Upgraded: 2026-09-27, 2026-11-01
//  Ideas: facet grooves at integer crystalR; stepped diffraction orders; lit bevel on the groove; diagonal caustic
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: .xyzw = facets / tilt / interference / dispersion

const PI: f32 = 3.14159265359;

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }

    let coord = vec2<i32>(gid.xy);
    let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
    let dt = min(u.config.y, 0.05);
    let time = u.config.x;

    // Single-writer persistent state strictly in 133..138
    if (gid.x == 0u && gid.y == 0u) {
        let raw_bass = plasmaBuffer[0].x;
        let raw_mid = plasmaBuffer[0].y;
        let raw_treb = plasmaBuffer[0].z;
        extraBuffer[133] = mix(extraBuffer[133], raw_bass, 15.0 * dt);
        extraBuffer[134] = mix(extraBuffer[134], raw_mid, 15.0 * dt);
        extraBuffer[135] = mix(extraBuffer[135], raw_treb, 15.0 * dt);

        let pointer_down = u.zoom_config.w;
        let cur_val = extraBuffer[136];
        let cur_vel = extraBuffer[137];
        let force = (pointer_down - cur_val) * 150.0 - cur_vel * 12.0; // Bounded spring
        let next_vel = cur_vel + force * dt;
        let next_val = cur_val + next_vel * dt;
        extraBuffer[136] = clamp(next_val, -0.5, 1.5);
        extraBuffer[137] = clamp(next_vel, -50.0, 50.0);
    }

    // Live bands and the live button. The smoothed copies in extraBuffer
    // are cleared by the host before this dispatch, so they never moved.
    let s_bass = plasmaBuffer[0].x;
    let s_mid = plasmaBuffer[0].y;
    let s_treb = plasmaBuffer[0].z;
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

    let facets = mix(3.0, 16.0, u.zoom_params.x);
    let tilt = mix(0.0, 1.0, u.zoom_params.y);
    let interference = mix(0.1, 2.0, u.zoom_params.z);
    let dispersion = mix(0.1, 1.5, u.zoom_params.w);

    let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    let mouse_uv = u.zoom_config.yz;
    var mouse_p = mouse_uv * 2.0 - 1.0;
    mouse_p.x *= aspect;
    let to_mouse = p - mouse_p;
    let dist_mouse = length(to_mouse);
    let pull = exp(-dist_mouse * 4.0) * held * 0.15; // Held pointer response
    
    var pp = p - normalize(to_mouse + 1e-5) * pull;

    // Capped click fronts
    var clickFront = 0.0;
    for (var i = 0u; i < 50u; i++) {
        let event = u.ripples[i];
        let age = time - event.z;
        if (age > 0.0 && age < 2.5) {
            var event_p = event.xy * 2.0 - 1.0;
            event_p.x *= aspect;
            let dist = length(pp - event_p);
            let radius = age * 1.5;
            let width = 0.05 + age * 0.05;
            let strength = exp(-age * 2.0);
            let radial = dist - radius;
            let wave = exp(-(radial * radial) / (width * width));
            clickFront += wave * strength;
            pp += normalize(pp - event_p + 1e-5) * wave * strength * 0.1;
        }
    }

    let tilt_angle = tilt * PI * 0.5;
    let ca = cos(tilt_angle); let sa = sin(tilt_angle);
    var crystal_p = vec2<f32>(
        pp.x * ca - pp.y * sa,
        pp.x * sa + pp.y * ca
    );

    let crystalShape = max(abs(crystal_p.x), abs(crystal_p.y));
    
    // Shape picks which band shoves the section. Silence leaves it still.
    let band = mix(s_bass, mix(s_mid, s_treb, smoothstep(0.35, 0.7, crystalShape)), smoothstep(0.0, 0.35, crystalShape));
    crystal_p += normalize(crystal_p + vec2<f32>(1e-5, 0.0)) * band * 0.02;

    let crystalR = crystalShape * facets;

    let bg_color = vec3<f32>(0.002, 0.002, 0.01);
    if (crystalShape > 0.7) {
        let final_bg = bg_color + vec3<f32>(clickFront * 0.1);
        let mapped_bg = acesToneMap(final_bg);
        // Feedback read using exact textureLoad pattern
        let prev = textureLoad(dataTextureC, coord, 0).rgb;
        let blend_bg = mix(mapped_bg, prev, 0.8);
        let out_bg = vec4<f32>(blend_bg, 0.0);
        
        // Write final display RGBA ONLY to dataTextureA and writeTexture
        textureStore(writeTexture, coord, out_bg);
        textureStore(dataTextureA, coord, out_bg);
        textureStore(writeDepthTexture, coord, vec4<f32>(1.0, 0.0, 0.0, 1.0));
        return;
    }

    let local_t = time * 0.5 + s_bass * 0.5;
    let edge_mask = smoothstep(0.7, 0.65, crystalShape);

    // Facet grooves: dark cuts on the integer boundaries of crystalR.
    let groove = 1.0 - smoothstep(0.0, 0.045, abs(fract(crystalR) - 0.0));
    let order = floor(crystalR);
    
    // Truthful three-band audio + bins reactivity integration.
    // Diffraction orders step with facet index; Dispersion spreads each order.
    let phase = order * PI - local_t * 8.0 + clickFront * 8.0;
    let dither = (hash21(vec2<f32>(gid.xy) + time) - 0.5) * 0.1;
    
    let c_spread = dispersion * (1.0 + order * 0.18);
    let phase_r = phase + dither;
    let phase_g = phase + c_spread * 2.094 + dither;
    let phase_b = phase + c_spread * 4.188 + dither;

    let r = 0.5 + 0.5 * cos(phase_r + s_treb * 2.0);
    let g = 0.5 + 0.5 * cos(phase_g + s_mid * 2.0);
    let b = 0.5 + 0.5 * cos(phase_b + s_bass * 2.0);

    var holo_color = vec3<f32>(r, g, b) * interference * (1.0 - groove * 0.72);
    
    // High-end optical specular
    let grad_x = sin(crystal_p.x * 30.0 + time);
    let grad_y = sin(crystal_p.y * 30.0 + time);
    let normal = normalize(vec3<f32>(grad_x, grad_y, 2.0));
    let light_dir = normalize(vec3<f32>(sin(time), cos(time), 1.0));
    let spec = pow(max(dot(normal, light_dir), 0.0), 32.0);
    
    holo_color += vec3<f32>(1.0, 0.9, 0.8) * spec * (0.5 + s_treb) * 2.0;
    holo_color += clickFront * vec3<f32>(0.2, 0.6, 1.0) * 1.5;

    // ── Idea 1: lit bevel ─────────────────────────────────────────────
    // The groove stays a dark cut. The lit side of that cut takes a thin lip.
    let grooveSide = fract(crystalR);
    let bevel = smoothstep(0.0, 0.07, grooveSide) * (1.0 - smoothstep(0.07, 0.16, grooveSide));
    let facing = clamp(dot(normalize(crystal_p + vec2<f32>(1e-5, 0.0)), light_dir.xy), 0.0, 1.0);
    holo_color += vec3<f32>(1.0, 0.95, 0.85) * bevel * facing * (0.35 + s_treb * 0.4);

    // ── Idea 2: diagonal caustic ──────────────────────────────────────
    // A square section focuses along |x| = |y|. Interference is the amount.
    let diag = abs(abs(crystal_p.x) - abs(crystal_p.y));
    let caustic = exp(-diag * diag * 80.0);
    holo_color += vec3<f32>(0.65, 0.85, 1.0) * caustic * interference * 0.28;

    var final_color = mix(bg_color, holo_color, edge_mask);

    let mapped_color = acesToneMap(final_color);
    
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    let blend_color = mix(mapped_color, prev, 0.6 - s_bass * 0.2);
    
    // Semantic alpha
    let lum = dot(blend_color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(lum * 1.5 + clickFront, 0.0, 1.0);
    let out_rgba = vec4<f32>(blend_color, alpha);

    textureStore(writeTexture, coord, out_rgba);
    textureStore(dataTextureA, coord, out_rgba);
    textureStore(writeDepthTexture, coord, vec4<f32>(1.0 - edge_mask, 0.0, 0.0, 1.0));
}
