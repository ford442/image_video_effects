// ═══════════════════════════════════════════════════════════════
//  Boids Swarm with Alpha Scattering
//  GPU-based flocking with physical light simulation
//
//  Scientific Concepts:
//  - Particles have physical size and opacity
//  - Many small particles = cumulative alpha
//  - Scattering affects perceived transparency
//  - Motion blur affects alpha accumulation
//
//  Dataflow (single-pass feedback sim):
//  The renderer only ever dispatches entry point `main`, so the
//  flocking state lives in the data-texture feedback channel:
//  previous frame state is read from dataTextureC (binding 9) and
//  new state is written to dataTextureA (binding 7); the renderer
//  copies A→C after each frame. One boid per texel in row 0:
//  rgba = (pos.x, pos.y, vel.x, vel.y), pos normalized 0..1,
//  vel in normalized units per second. The first BOID_COUNT
//  flattened invocations integrate one boid each; ALL invocations
//  then splat the boids read from dataTextureC.
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

const BOID_COUNT: u32 = 256u;
const MAX_SPEED: f32 = 0.28;          // normalized units per second
const PERCEPTION_RADIUS: f32 = 0.08;  // normalized
const DT: f32 = 0.016;                // fixed integration step (60 fps)

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 127.1) * 43758.5453);
}

// Procedural seed for boid i: position + random heading
fn seedBoid(i: u32) -> vec4<f32> {
    let fi = f32(i);
    let pos = vec2<f32>(hash11(fi + 0.13), hash11(fi * 1.7 + 91.7));
    let ang = hash11(fi * 3.1 + 17.3) * 6.28318530718;
    let vel = vec2<f32>(cos(ang), sin(ang)) * MAX_SPEED * 0.5;
    return vec4<f32>(pos, vel);
}

// First frame / corrupted feedback detection (NaN, out of range, all-zero)
fn stateInvalid(s: vec4<f32>) -> bool {
    if (s.x != s.x || s.y != s.y || s.z != s.z || s.w != s.w) { return true; }
    if (s.x < 0.0 || s.x > 1.0 || s.y < 0.0 || s.y > 1.0) { return true; }
    if (all(s == vec4<f32>(0.0))) { return true; }
    return false;
}

// Shortest signed delta on the torus (world wraps with fract)
fn wrapDelta(d: vec2<f32>) -> vec2<f32> {
    return d - floor(d + vec2<f32>(0.5));
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
    let l = length(v);
    if (l < 0.00001) { return vec2<f32>(0.0); }
    return v / l;
}

// Soft particle alpha based on distance
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    // Gaussian-like falloff for soft particles
    let normalized_dist = dist / radius;
    return exp(-normalized_dist * normalized_dist * 2.0);
}

// Exponential transmittance for cumulative density
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// HDR tone mapping helper
fn toneMap(hdr: vec3<f32>) -> vec3<f32> {
    // Reinhard tone mapping
    return hdr / (1.0 + hdr);
}

// Flocking integration for boid `idx`; writes new state to dataTextureA.
fn updateBoid(idx: u32) {
    var state = textureLoad(dataTextureC, vec2<i32>(i32(idx), 0), 0);
    if (stateInvalid(state)) { state = seedBoid(idx); }
    var pos = state.xy;
    var vel = state.zw;
    let time = u.config.x;
    let tex_size = vec2<f32>(textureDimensions(readTexture));

    // ═══ Separation / Alignment / Cohesion ═══
    var sep = vec2<f32>(0.0);
    var ali = vec2<f32>(0.0);
    var coh = vec2<f32>(0.0);
    var count: f32 = 0.0;
    for (var j: u32 = 0u; j < BOID_COUNT; j = j + 1u) {
        if (j == idx) { continue; }
        let other = textureLoad(dataTextureC, vec2<i32>(i32(j), 0), 0);
        if (stateInvalid(other)) { continue; }
        let diff = wrapDelta(pos - other.xy);
        let d = length(diff);
        if (d > 0.0001 && d < PERCEPTION_RADIUS) {
            sep += diff / (d * d);   // push away, weighted by proximity
            ali += other.zw;
            coh += diff;             // sum of (pos - other); toward = -coh
            count += 1.0;
        }
    }
    var acc = vec2<f32>(0.0);
    if (count > 0.0) {
        acc += safeNormalize(sep) * 0.9;
        acc += safeNormalize(ali / count - vel) * 0.5;
        acc -= safeNormalize(coh / count) * 0.4;
    }

    // ═══ Mouse position as attractor ═══
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let to_mouse = wrapDelta(mouse_pos - pos);
    let dist_to_mouse = length(to_mouse);
    if (dist_to_mouse > 0.01) {
        acc += safeNormalize(to_mouse) * 0.35 * smoothstep(0.6, 0.05, dist_to_mouse);
    }

    // ═══ Ripples as attractor seeds ═══
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let ripple_age = time - ripple.z;
            if (ripple_age > 0.0 && ripple_age < 4.0) {
                let to_ripple = wrapDelta(ripple.xy - pos);
                let dist_to_ripple = length(to_ripple);
                if (dist_to_ripple > 0.01 && dist_to_ripple < 0.3) {
                    acc += safeNormalize(to_ripple) * 0.3 * (1.0 - ripple_age / 4.0);
                }
            }
        }
    }

    // ═══ Drift towards brighter areas of the source image ═══
    let brightness = textureSampleLevel(readTexture, u_sampler, fract(pos), 0.0).r;
    if (brightness > 0.5) {
        acc += safeNormalize(vel) * 0.1;
    }

    // Gentle wander so the flock never freezes
    let wander_ang = hash11(f32(idx) * 7.7 + floor(time * 8.0) * 0.913) * 6.28318530718;
    acc += vec2<f32>(cos(wander_ang), sin(wander_ang)) * 0.15;

    // ═══ Integrate ═══
    vel += acc * 1.2 * DT;
    let speed = length(vel);
    if (speed > MAX_SPEED) {
        vel = vel / speed * MAX_SPEED;
    } else if (speed < MAX_SPEED * 0.2) {
        vel = safeNormalize(vel) * MAX_SPEED * 0.2;
    }
    pos = fract(pos + vel * DT);

    textureStore(dataTextureA, vec2<i32>(i32(idx), 0), vec4<f32>(pos, vel));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dim = textureDimensions(writeTexture);
    let coord = vec2<u32>(gid.xy);
    let tex_size = vec2<f32>(dim);
    let time = u.config.x;

    // ═══ Phase 1: sim update — one boid per flattened invocation ═══
    let flat = gid.y * dim.x + gid.x;
    if (flat < BOID_COUNT && flat < dim.x) {
        updateBoid(flat);
    }

    if (gid.x >= dim.x || gid.y >= dim.y) { return; }

    // ═══ Phase 2: render — splat all boids with alpha scattering ═══

    // Accumulate particle density and color
    var accumulated_color = vec3<f32>(0.0);
    var accumulated_density: f32 = 0.0;
    var total_energy: f32 = 0.0;

    // Particle parameters
    let particle_radius = 3.0 + u.zoom_params.x * 5.0;
    let particle_opacity = 0.6 + u.zoom_params.y * 0.4;
    let glow_intensity = 0.5 + u.zoom_params.z * 1.5;

    // Sample boids for rendering
    for (var i: u32 = 0u; i < BOID_COUNT; i = i + 1u) {
        let bstate = textureLoad(dataTextureC, vec2<i32>(i32(i), 0), 0);
        if (stateInvalid(bstate)) { continue; }

        let boid_pos = bstate.xy * tex_size;
        // Velocity in pixels per frame, for motion-blur aesthetics
        let vel = bstate.zw * tex_size * DT;
        let pixel_pos = vec2<f32>(f32(coord.x), f32(coord.y));

        // Distance to boid (toroidal wrap keeps splats visible across edges)
        let raw_delta = pixel_pos - boid_pos;
        let wrap_delta = raw_delta - floor(raw_delta / tex_size + vec2<f32>(0.5)) * tex_size;
        let dist = length(wrap_delta);

        if (dist < particle_radius * 3.0) {
            // Speed for motion blur and emission
            let speed = length(vel);

            // Soft particle alpha
            let soft_alpha = softParticleAlpha(dist, particle_radius);

            // Motion blur stretches particle along velocity
            let vel_dir = safeNormalize(vel + vec2<f32>(0.001, 0.001));
            let along_vel = dot(wrap_delta, vel_dir);
            let perp_vel = length(wrap_delta - vel_dir * along_vel);

            // Elongated particle shape for motion blur
            let blur_alpha = soft_alpha * exp(-(perp_vel * perp_vel) / (particle_radius * 0.5));

            // Boid color based on velocity direction
            let velocity_hue = atan2(vel.y, vel.x) / 6.28318530718 + 0.5;
            let boid_color = vec3<f32>(
                0.5 + 0.5 * cos(velocity_hue * 6.28318530718),
                0.5 + 0.5 * cos(velocity_hue * 6.28318530718 + 2.094),
                0.5 + 0.5 * cos(velocity_hue * 6.28318530718 + 4.189)
            );

            // HDR emission based on speed
            let emission = 1.0 + speed * glow_intensity;
            let hdr_color = boid_color * emission;

            // Accumulate with alpha
            let alpha = blur_alpha * particle_opacity;
            accumulated_color += hdr_color * alpha;
            accumulated_density += alpha;
            total_energy += alpha * emission;
        }
    }

    // Tone mapping
    accumulated_color = toneMap(accumulated_color * 0.5);

    // Cumulative alpha using exponential transmittance
    // More particles = higher density = lower transmittance
    let trans = transmittance(accumulated_density * 0.1);
    let final_alpha = 1.0 - trans;

    // Boost alpha with energy for glowing effect
    let energy_boost = min(total_energy * 0.01, 0.5);
    let final_alpha_boosted = min(final_alpha + energy_boost, 1.0);

    // Sample background with inverse alpha
    let bg_color = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0).rgb;
    let final_color = mix(bg_color * 0.1, accumulated_color, final_alpha_boosted);

    let output = vec4<f32>(final_color, final_alpha_boosted);
    textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), output);
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(gid.xy) / vec2<f32>(textureDimensions(readTexture)), 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
