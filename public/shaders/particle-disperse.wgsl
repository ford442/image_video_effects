// ═══════════════════════════════════════════════════════════════════
//  Particle Disperse
//  Category: interactive-mouse
//  Features: mouse-driven, physics, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: motion-blur streaks along vel; neighbour velocity coupling (4-tap Laplacian); dust breakup of displaced regions
//  A packing: raw sim state, no tone map — (offset.xy, vel.xy) in uv / uv-per-frame
// ═══════════════════════════════════════════════════════════════════
//  Wind-force particle dispersion with physical light simulation:
//  particles have size and opacity, overlapping grains give cumulative
//  alpha, scattering and motion blur shape the perceived transparency.

#include "_prelude.wgsl"

// Soft particle alpha calculation
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    return 1.0 - smoothstep(0.0, radius, dist);
}

// Exponential transmittance for cumulative density
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// Motion blur kernel based on velocity
fn motionBlurKernel(vel: vec2<f32>, sample_pos: vec2<f32>, pixel_pos: vec2<f32>) -> f32 {
    let vel_len = length(vel);
    if (vel_len < 0.001) {
        return 1.0;
    }

    let vel_dir = vel / vel_len;
    let to_pixel = pixel_pos - sample_pos;
    let along_motion = dot(to_pixel, vel_dir);
    let perp_motion = length(to_pixel - vel_dir * along_motion);

    // Gaussian along motion direction
    let blur_length = vel_len * 20.0;
    let along_factor = exp(-(along_motion * along_motion) / (blur_length * blur_length + 0.001));
    let perp_factor = exp(-(perp_motion * perp_motion) / 0.001);

    return along_factor * perp_factor;
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Exact C load of the (offset, vel) state, sanitized against NaN or a
// foreign packing left in C by the previously active shader.
fn load_state(c: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    let s = textureLoad(dataTextureC, clamp(c, vec2<i32>(0), dims - vec2<i32>(1)), 0);
    let ok = all(abs(s.xy) < vec2<f32>(1.0)) && all(abs(s.zw) < vec2<f32>(0.25));
    return select(vec4<f32>(0.0), s, ok);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let dims = vec2<i32>(resolution);
    let aspect = resolution.x / resolution.y;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let windForce = mix(0.01, 0.1, u.zoom_params.x);
    let returnSpeed = mix(0.01, 0.2, u.zoom_params.y);
    let damping = mix(0.8, 0.99, u.zoom_params.z);
    let particle_radius = mix(0.05, 0.3, u.zoom_params.w);
    let particle_opacity = mix(0.4, 1.0, u.zoom_params.w);

    let mouse = u.zoom_config.yz;

    // Read state: RG = Offset, BA = Velocity (exact C load)
    let state = load_state(coord, dims);
    var offset = state.xy;
    var vel = state.zw;

    // Calculate current apparent position
    let currentPos = uv + offset;

    // Mouse interaction - repel from mouse position
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let pos_aspect = vec2<f32>(currentPos.x * aspect, currentPos.y);

    let dist = max(distance(pos_aspect, mouse_aspect), 0.001);

    var force = vec2<f32>(0.0);
    if (dist < particle_radius * 2.0) {
        let dir = (pos_aspect - mouse_aspect) / dist;
        let push = (1.0 - dist / (particle_radius * 2.0)) * windForce;
        force = vec2<f32>(dir.x / aspect, dir.y) * push;
    }

    // Update Velocity
    vel = vel + force;

    // Idea 2: neighbour coupling — a 4-tap Laplacian of last frame's velocity
    // (exact C loads) drags each particle toward its neighbours' motion, so the
    // blown region shears into eddies behind the cursor instead of moving as
    // isolated pixels. Coefficient 0.12 < 0.25 keeps the explicit step stable.
    let vR = load_state(coord + vec2<i32>(1, 0), dims).zw;
    let vL = load_state(coord - vec2<i32>(1, 0), dims).zw;
    let vD = load_state(coord + vec2<i32>(0, 1), dims).zw;
    let vU = load_state(coord - vec2<i32>(0, 1), dims).zw;
    let lap = vR + vL + vD + vU - 4.0 * state.zw;
    vel = vel + lap * 0.12;

    // Spring force (return to offset 0)
    let spring = -offset * returnSpeed;
    vel = vel + spring;

    // Damping
    vel = vel * damping;
    let vlen = length(vel);
    vel = vel * min(1.0, 0.05 / max(vlen, 1e-6));          // velocity clamp

    // Update Offset
    offset = offset + vel;
    let olen = length(offset);
    offset = offset * min(1.0, 0.5 / max(olen, 1e-6));

    // Write state (raw — never tone-mapped)
    textureStore(dataTextureA, coord, vec4<f32>(offset, vel));

    // Calculate motion blur and alpha
    let speed = length(vel);
    let motion_blur_amount = min(speed * 15.0, 0.8);

    // Sample Image with inverse semi-lagrangian lookup
    let sampleUV = uv - offset;
    let inBounds = sampleUV.x >= 0.0 && sampleUV.x <= 1.0 && sampleUV.y >= 0.0 && sampleUV.y <= 1.0;

    // Idea 1: motion-blur streaks — 6 taps trail along vel from the sample
    // point, weighted by the (formerly unused) motionBlurKernel.
    var base_color = vec4<f32>(0.0);
    var wsum = 0.0;
    let vdir = select(vec2<f32>(0.0), vel / max(speed, 1e-6), speed > 0.001);
    let streak = min(speed * 20.0 * 0.6, 0.08);
    for (var i: i32 = 0; i < 6; i = i + 1) {
        let tapPos = sampleUV + vdir * streak * (f32(i) / 5.0);
        let tapUV = clamp(tapPos, vec2<f32>(0.0), vec2<f32>(1.0));
        let wk = motionBlurKernel(vel, tapPos, sampleUV);
        base_color = base_color + textureSampleLevel(readTexture, u_sampler, tapUV, 0.0) * wk;
        wsum = wsum + wk;
    }
    base_color = base_color / max(wsum, 1e-4);
    base_color = select(vec4<f32>(0.0), base_color, inBounds);

    // ═══════════════════════════════════════════════════════════════
    //  ALPHA SCATTERING CALCULATION
    // ═══════════════════════════════════════════════════════════════

    // Distance the particle has travelled from its home (aspect-correct)
    let pixel_to_center = uv - currentPos;
    let pixel_dist = length(vec2<f32>(pixel_to_center.x * aspect, pixel_to_center.y));

    // Soft particle alpha: grains thin as they leave home
    let soft_alpha = softParticleAlpha(pixel_dist, particle_radius);

    // Idea 3: dust breakup — a per-pixel grain threshold against the
    // transmittance of the displacement: displaced regions crumble into
    // separate grains, and the gaps between them fall to a dim, sparse dust.
    // The grain hash rides on the source texel, so grains travel with the material.
    let T = transmittance(pixel_dist * 8.0 / mix(0.6, 1.4, u.zoom_params.w));
    // 3-px grains; gated on displacement so pixels at rest never speckle (T = 1 there).
    let grain = hash12(floor(sampleUV * resolution / 3.0) + vec2<f32>(17.0, 3.0));
    let survive = 1.0 - smoothstep(T - 0.08, T, grain) * smoothstep(0.0, 0.01, pixel_dist);

    // HDR emission based on displacement speed (faster grains emit more light)
    let emission = 1.0 + speed * 3.0;
    var hdr_rgb = base_color.rgb * emission;

    // Add velocity-colored streaks (clamped — HEAD could go negative)
    let velocity_color = clamp(vec3<f32>(0.5 + vel.x * 2.0, 0.5 + vel.y * 2.0, 0.5 + speed), vec3<f32>(0.0), vec3<f32>(1.0));
    hdr_rgb = hdr_rgb + velocity_color * motion_blur_amount * 0.3;
    hdr_rgb = hdr_rgb * mix(0.35, 1.0, survive);

    // Cumulative density using exponential transmittance: coverage of the
    // grain sheet. Luminance no longer drives it, so dark pixels stay opaque.
    let particle_density = (0.6 + soft_alpha * 2.4) * particle_opacity * mix(0.25, 1.0, survive);
    let cumulative_alpha = 1.0 - transmittance(particle_density * 2.0);
    let final_alpha = cumulative_alpha * (1.0 - motion_blur_amount * 0.3) * select(0.0, 1.0, inBounds);

    let output_color = vec4<f32>(aces_tonemap(max(hdr_rgb, vec3<f32>(0.0))), clamp(final_alpha * base_color.a, 0.0, 1.0));
    textureStore(writeTexture, coord, output_color);

    // Depth travels with the dispersed content; gaps fall back
    let srcDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(srcDepth * mix(0.6, 1.0, survive) * select(0.0, 1.0, inBounds), 0.0, 0.0, 0.0));
}
