// ═══════════════════════════════════════════════════════════════
//  Kimi Flock Symphony with Alpha Scattering
//  Advanced particle flocking with musical visualization
//  With Physical Light Transport and Cumulative Alpha
//
//  Dataflow (single-pass feedback sim):
//  The renderer only ever dispatches entry point `main`, so the
//  flocking state lives in the data-texture feedback channel:
//  previous frame state is read from dataTextureC (binding 9) and
//  new state is written to dataTextureA (binding 7); the renderer
//  copies A→C after each frame. One boid per texel in row 0:
//  rgba = (pos.x, pos.y, vel.x, vel.y), pos normalized 0..1,
//  vel in normalized units per second. Per-boid hue is derived
//  deterministically from the boid index; per-boid energy is
//  derived from speed plus the audio bands in plasmaBuffer[0]
//  (bass / mids / treble). The first BOID_COUNT flattened
//  invocations integrate one boid each; ALL invocations then
//  splat the boids read from dataTextureC.
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
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}


const BOID_COUNT: u32 = 256u;
const MAX_SPEED: f32 = 0.30;          // normalized units per second
const PERCEPTION_RADIUS: f32 = 0.06;  // normalized
const DT: f32 = 0.016;                // fixed integration step (60 fps)

// Soft particle alpha
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 1.5);
}

// Exponential transmittance
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// HDR emission
fn hdrEmission(base: vec3<f32>, intensity: f32) -> vec3<f32> {
    return base * (0.5 + intensity * 2.0);
}

fn hash(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i.x + i.y * 57.0), hash(i.x + 1.0 + i.y * 57.0), u.x),
               mix(hash(i.x + (i.y + 1.0) * 57.0), hash(i.x + 1.0 + (i.y + 1.0) * 57.0), u.x), u.y);
}

// HSL to RGB conversion
fn hsl_to_rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs(fract(h * 6.0) * 2.0 - 1.0));
    let m = l - c * 0.5;

    var rgb: vec3<f32>;
    if (h < 1.0 / 6.0) {
        rgb = vec3<f32>(c, x, 0.0);
    } else if (h < 2.0 / 6.0) {
        rgb = vec3<f32>(x, c, 0.0);
    } else if (h < 3.0 / 6.0) {
        rgb = vec3<f32>(0.0, c, x);
    } else if (h < 4.0 / 6.0) {
        rgb = vec3<f32>(0.0, x, c);
    } else if (h < 5.0 / 6.0) {
        rgb = vec3<f32>(x, 0.0, c);
    } else {
        rgb = vec3<f32>(c, 0.0, x);
    }
    return rgb + vec3<f32>(m);
}

// Procedural seed for boid i: position + random heading
fn seedBoid(i: u32) -> vec4<f32> {
    let fi = f32(i);
    let pos = vec2<f32>(hash(fi + 0.13), hash(fi * 1.7 + 91.7));
    let ang = hash(fi * 3.1 + 17.3) * 6.28318530718;
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

// Flocking integration for boid `idx`; writes new state to dataTextureA.
fn updateBoid(idx: u32, bass: f32, mids: f32) {
    var state = textureLoad(dataTextureC, vec2<i32>(i32(idx), 0), 0);
    if (stateInvalid(state)) { state = seedBoid(idx); }
    var pos = state.xy;
    var vel = state.zw;
    let time = u.config.x;

    // ═══ Separation, Alignment, Cohesion ═══
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

        if (d < PERCEPTION_RADIUS && d > 0.0001) {
            sep += diff / (d * d);
            ali += other.zw;
            coh += diff;
            count += 1.0;
        }
    }

    var acc = vec2<f32>(0.0);
    if (count > 0.0) {
        acc += safeNormalize(sep) * 0.8;
        acc += safeNormalize(ali / count - vel) * 0.5;
        // Mids drive how strongly the flock pulls together
        acc -= safeNormalize(coh / count) * (0.25 + mids * 0.5);
    }

    // ═══ Mouse attraction with spiral ═══
    let mouse_pos = u.zoom_config.yz;
    let to_mouse = wrapDelta(mouse_pos - pos);
    let dist_to_mouse = length(to_mouse);
    let mouse_dir = safeNormalize(to_mouse);
    let perp = vec2<f32>(-mouse_dir.y, mouse_dir.x);
    let spiral_strength = u.zoom_config.w * 2.0 + 0.5;
    let spiral_force = perp * spiral_strength * smoothstep(0.5, 0.0, dist_to_mouse);
    acc += mouse_dir * 0.3 * smoothstep(0.7, 0.05, dist_to_mouse) + spiral_force * 0.4;

    // ═══ Noise wandering (agitated by bass) ═══
    let noise_force = vec2<f32>(
        noise(pos * 10.0 + time),
        noise(pos * 10.0 + time + 100.0)
    ) * (0.4 + bass * 1.2);
    acc += noise_force;

    // ═══ Integrate ═══
    vel += acc * 1.4 * DT;
    // Bass pumps the flock's top speed
    let max_speed = MAX_SPEED * (1.0 + bass * 0.8);
    let speed = length(vel);
    if (speed > max_speed) {
        vel = vel / speed * max_speed;
    } else if (speed < MAX_SPEED * 0.15) {
        vel = safeNormalize(vel) * MAX_SPEED * 0.15;
    }
    pos = fract(pos + vel * DT);

    textureStore(dataTextureA, vec2<i32>(i32(idx), 0), vec4<f32>(pos, vel));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dim = textureDimensions(writeTexture);
    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dim);
    var uv = vec2<f32>(global_id.xy) / resolution;
    var time = u.config.x;

    // Audio bands (FFT): bass / mids / treble
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ═══ Phase 1: sim update — one boid per flattened invocation ═══
    let flat = global_id.y * dim.x + global_id.x;
    if (flat < BOID_COUNT && flat < dim.x) {
        updateBoid(flat, bass, mids);
    }

    if (global_id.x >= dim.x || global_id.y >= dim.y) { return; }

    // ═══ Phase 2: render — splat all boids with musical coloring ═══

    // Parameters
    let glow_radius = u.zoom_params.y * 8.0 + 2.0;
    let color_shift = u.zoom_params.z + treble * 0.25;
    let density = u.zoom_params.w;
    let particle_opacity = 0.6;

    var accumulated_color = vec3<f32>(0.0);
    var accumulated_density: f32 = 0.0;
    var total_energy: f32 = 0.0;

    // Sample boids
    for (var i: u32 = 0u; i < BOID_COUNT; i = i + 1u) {
        let bstate = textureLoad(dataTextureC, vec2<i32>(i32(i), 0), 0);
        if (stateInvalid(bstate)) { continue; }

        let boid_pos = bstate.xy * resolution;
        let vel = bstate.zw;
        let pixel_pos = vec2<f32>(f32(coord.x), f32(coord.y));

        // Toroidal distance keeps splats visible across edges
        let raw_delta = pixel_pos - boid_pos;
        let wrap_delta = raw_delta - floor(raw_delta / resolution + vec2<f32>(0.5)) * resolution;
        var d = length(wrap_delta);

        if (d < glow_radius) {
            // Speed (normalized units/sec) for energy and emission
            let speed = length(vel);
            let speed_norm = clamp(speed / MAX_SPEED, 0.0, 1.5);
            // Musical energy: smoothed speed plus bass pulse
            let b_energy = clamp(speed_norm * 0.7 + bass * 0.5, 0.05, 1.5);

            // Soft particle alpha
            let alpha = softParticleAlpha(d, glow_radius) * particle_opacity * b_energy;

            // Per-boid hue is a deterministic "instrument voice", swept by
            // time, treble, and the user's color-shift control
            let b_hue = fract(hash(f32(i) * 1.61803398875 + 200.0) + time * 0.03 + speed_norm * 0.05);

            // HSL color with shift
            var rgb = hsl_to_rgb(fract(b_hue + color_shift), 0.8, 0.5);

            // HDR emission based on energy and speed
            let emission = 1.0 + b_energy * 2.0 + speed_norm * 0.5;
            let hdr_rgb = hdrEmission(rgb, emission);

            // Accumulate
            accumulated_color += hdr_rgb * alpha * density;
            accumulated_density += alpha;
            total_energy += alpha * emission;
        }
    }

    // Center glow at mouse (pulses with bass)
    var mouse = u.zoom_config.yz * resolution;
    let mouse_dist = distance(vec2<f32>(f32(coord.x), f32(coord.y)), mouse);
    let mouse_alpha = softParticleAlpha(mouse_dist, 100.0) * (0.3 + bass * 0.4);
    accumulated_color += vec3<f32>(1.0, 0.9, 0.7) * mouse_alpha;
    accumulated_density += mouse_alpha;

    // Tone mapping
    accumulated_color = accumulated_color / (1.0 + accumulated_color);
    accumulated_color = pow(accumulated_color, vec3<f32>(0.8));

    // Cumulative alpha using exponential transmittance
    let trans = transmittance(accumulated_density * 0.5);
    let final_alpha = 1.0 - trans;

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    accumulated_color *= vignette;

    // Output RGBA
    let output = vec4<f32>(accumulated_color, clamp(final_alpha, 0.0, 1.0));
    textureStore(writeTexture, coord, applyGenerativePrimaryControls(output));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
