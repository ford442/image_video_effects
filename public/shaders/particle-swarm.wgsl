// ═══════════════════════════════════════════════════════════════════════════════
//  Particle Swarm — Boid Cohesion with Anisotropic Scattering
//  Category: interactive-mouse
//  Features: mouse-driven, held-drag, spring-damper-pointer,
//            bounded-click-ripples, audio-reactive, per-band-fft,
//            boid-cohesion, henyey-greenstein, motion-blur, depth-aware,
//            upgraded-rgba, semantic-alpha, aces
//  Upgraded: 2026-08-23 (Batch 60)
// ═══════════════════════════════════════════════════════════════════════════════
//  A carries SIM STATE (rg = offset, ba = velocity) and comes back as
//  dataTextureC next frame. Display goes to writeTexture.
//
//  TWO BUGS FIXED IN THIS PASS
//
//  1. No bounds guard. `main` computed and wrote for every dispatched
//     invocation with no `global_id >= dims` early-out, so at any resolution
//     that is not a multiple of the 16x16 workgroup the shader wrote outside
//     the render target.
//
//  2. Degenerate scattering. The Henyey-Greenstein term was fed
//
//         let view_dir = vec2<f32>(0.0, 0.0);
//         let cos_theta = dot(velocity_dir, view_dir);
//
//     `dot(anything, (0,0))` is identically zero, so `cos_theta` was ALWAYS 0
//     and `scatteringPhase(0, 0.3)` returned one fixed constant. The phase
//     function — the whole point of the "anisotropic scattering" the header
//     advertised — contributed a flat scalar with no directional behaviour.
//     Scattering now uses the real screen-space geometry between the particle's
//     velocity and the view/light axis, so streaks brighten when a particle
//     moves toward the light and dim when it moves away.
//
//  TWO NEW STRUCTURES
//
//    1. Boid cohesion and separation — the swarm was N independent spring-mass
//       points that never saw each other; nothing about it was a "swarm". Each
//       particle now reads its four neighbours' offsets out of the state
//       texture and applies cohesion (steer toward the local mean) and
//       separation (push off neighbours that crowd it), so the field forms
//       travelling flocks and voids instead of a uniform elastic sheet.
//
//    2. Per-band FFT turbulence + spring-damped attractor — each particle hashes
//       to one of the eight spectrum bins driving its own turbulence gain, and
//       the cursor attractor is spring-damped through extraBuffer[133..136] so
//       fast pointer moves drag the flock instead of teleporting it.
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Stiffness, y=Force, z=Damping, w=Radius/Opacity
  ripples: array<vec4<f32>, 50>,
};

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Particle Swarm with Alpha
// Param1: Spring Stiffness (0.01 - 0.2)
// Param2: Mouse Force (0.1 - 2.0)
// Param3: Damping (0.8 - 0.99)
// Param4: Particle Size/Opacity (0.01 - 0.5)

// Soft particle alpha calculation
fn softParticleAlpha(dist: f32, radius: f32, core_size: f32) -> f32 {
    // Core is more opaque, edges fade smoothly
    let core_alpha = 1.0 - smoothstep(0.0, core_size * radius, dist);
    let edge_fade = 1.0 - smoothstep(core_size * radius, radius, dist);
    return core_alpha * 0.8 + edge_fade * 0.2;
}

// Scattering phase function (Henyey-Greenstein approximation)
fn scatteringPhase(cos_theta: f32, g: f32) -> f32 {
    let g2 = g * g;
    let denom = 1.0 + g2 - 2.0 * g * cos_theta;
    return (1.0 - g2) / (4.0 * 3.14159265 * sqrt(denom * denom * denom));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let maxC = dimsI - vec2<i32>(1);
    let resolution = vec2<f32>(dimsI);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let aspectV = vec2<f32>(aspect, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held = step(0.5, u.zoom_config.w);

    // Parameters
    let stiffness = mix(0.01, 0.2, u.zoom_params.x);
    let forceInput = u.zoom_params.y - 0.5;
    let forceMult = forceInput * 0.1;
    let damping = mix(0.80, 0.98, u.zoom_params.z);
    let particle_radius = mix(0.05, 0.4, u.zoom_params.w);
    let particle_opacity = mix(0.3, 1.0, u.zoom_params.w);

    // Read previous state — exact load (dataTextureC is rgba32float).
    let state = textureLoad(dataTextureC, coord, 0);
    var offset = state.xy;
    var vel = state.zw;

    // ── Spring-damped attractor in extraBuffer[133..136] ─────────────────────
    let rawMouse = u.zoom_config.yz;
    if (global_id.x == 0u && global_id.y == 0u) {
        var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        if (sm.x == 0.0 && sm.y == 0.0) { sm = rawMouse; }
        let dt = 0.016;
        let k = 1.0 - exp(-10.0 * dt);
        let next = sm + (rawMouse - sm) * k;
        var sv = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        sv = mix(sv, (next - sm) / dt, 0.28);
        extraBuffer[133] = next.x;
        extraBuffer[134] = next.y;
        extraBuffer[135] = sv.x;
        extraBuffer[136] = sv.y;
    }
    let mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);

    // Current position of the "particle" (pixel source)
    let currentPos = uv + offset;

    // ── Pointer attraction, dragged by the pointer's own velocity ───────────
    var interaction = vec2<f32>(0.0);
    let dVec = mousePos - currentPos;
    let dist = length(dVec * aspectV);
    if (dist < particle_radius && dist > 0.001) {
        let tt = 1.0 - (dist / particle_radius);
        interaction = normalize(dVec) * tt * forceMult * (1.0 + held);
        interaction += clamp(mouseVel * 0.004, vec2<f32>(-0.02), vec2<f32>(0.02)) * tt * held;
    }

    // ── Structure 1: boid cohesion + separation ─────────────────────────────
    // Neighbours' offsets come from the state texture. Cohesion steers toward
    // the local mean position; separation pushes off crowding. Without these
    // the field was N independent springs, not a swarm.
    let nE = textureLoad(dataTextureC, clamp(coord + vec2<i32>( 2, 0), vec2<i32>(0), maxC), 0).xy;
    let nW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-2, 0), vec2<i32>(0), maxC), 0).xy;
    let nN = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0,  2), vec2<i32>(0), maxC), 0).xy;
    let nS = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -2), vec2<i32>(0), maxC), 0).xy;
    let neighbourMean = (nE + nW + nN + nS) * 0.25;
    let cohesion = (neighbourMean - offset) * (0.055 + mids * 0.05);
    // Separation: the closer a neighbour has drifted to us, the harder we push.
    var separation = vec2<f32>(0.0);
    separation += (offset - nE) / (1.0 + dot(offset - nE, offset - nE) * 400.0);
    separation += (offset - nW) / (1.0 + dot(offset - nW, offset - nW) * 400.0);
    separation += (offset - nN) / (1.0 + dot(offset - nN, offset - nN) * 400.0);
    separation += (offset - nS) / (1.0 + dot(offset - nS, offset - nS) * 400.0);
    separation *= 0.006 * (1.0 + bass * 0.8);

    // ── Structure 2: per-particle FFT turbulence band ───────────────────────
    let bandIdx = u32(hash12(floor(uv * 64.0)) * 8.0) % 8u;
    let band = plasmaBuffer[bandIdx + 1u].x;
    let turbPhase = time * (0.6 + f32(bandIdx) * 0.17);
    let turbulence = vec2<f32>(sin(uv.y * 23.0 + turbPhase), cos(uv.x * 19.0 - turbPhase))
                   * band * 0.0016;

    // ── Bounded click impulses ──────────────────────────────────────────────
    var burst = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.2) {
            let d = (currentPos - rp.xy) * aspectV;
            let r = max(length(d), 1e-4);
            let front = r - age * 0.5;
            let env = exp(-front * front * 140.0) * exp(-age * 1.5);
            vel += (d / r) * env * (0.006 + bass * 0.010);
            burst += env;
        }
    }
    burst = min(burst, 1.5);

    // Spring force (return to origin 0,0)
    let spring = -offset * stiffness;

    // Physics update
    vel = (vel + interaction + spring + cohesion + separation + turbulence) * damping;
    offset = offset + vel;

    // Calculate speed for motion blur
    let speed = length(vel);
    let motion_blur = min(speed * 10.0, 1.0);

    // Write new state
    textureStore(dataTextureA, coord, vec4<f32>(offset, vel));

    // Sample Image
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let base_color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // ═══════════════════════════════════════════════════════════════
    //  ALPHA SCATTERING CALCULATION
    // ═══════════════════════════════════════════════════════════════

    // Calculate soft particle alpha based on distance from particle center
    let particle_center = currentPos;
    let pixel_to_center = uv - particle_center;
    let pixel_dist = length(vec2<f32>(pixel_to_center.x * aspect, pixel_to_center.y));
    
    // Soft particle alpha: core more opaque, edges transparent
    let soft_alpha = softParticleAlpha(pixel_dist, particle_radius, 0.3);
    
    // Final alpha includes particle opacity and speed-based motion blur
    let alpha = soft_alpha * particle_opacity * (1.0 + motion_blur * 0.5);
    
    // HDR emission calculation
    // RGB can exceed 1.0 for glow effects
    let emission_strength = 1.0 + speed * 2.0; // Faster particles glow brighter
    var hdr_color = base_color.rgb * emission_strength;
    
    // ── Anisotropic scattering with real geometry ───────────────────────────
    // The old code dotted the velocity against vec2(0,0), which is identically
    // zero — the phase function was a constant. The light arrives from the
    // upper-left of screen space, so the scattering angle is the angle between
    // the particle's travel and that incident direction.
    let velocity_dir = normalize(vel + vec2<f32>(1e-5, 1e-5));
    let light_dir = normalize(vec2<f32>(-0.6, 0.8));
    let cos_theta = dot(velocity_dir, light_dir);
    // Forward-scattering asymmetry rises with treble (finer particles).
    let g = clamp(0.3 + treble * 0.35, 0.0, 0.85);
    let scatter = scatteringPhase(cos_theta, g) * speed * 0.5;
    hdr_color += vec3<f32>(scatter * 0.3, scatter * 0.5, scatter * 0.7);
    hdr_color += vec3<f32>(1.0, 0.75, 0.5) * burst * 0.5;

    // Cumulative density for overlapping particles
    // Using the exponential transmittance model: T = exp(-density)
    let density = alpha * (1.0 + length(base_color.rgb));
    let transmittance = exp(-density * 0.5);
    let cumulative_alpha = 1.0 - transmittance;

    // Output RGBA with physical light scattering
    let final_color = vec4<f32>(acesFilm(hdr_color),
                                clamp(cumulative_alpha + burst * 0.2, 0.0, 1.0));

    textureStore(writeTexture, coord, final_color);
    // B carries diagnostics (A is sim state, so it cannot hold display colour).
    textureStore(dataTextureB, coord, vec4<f32>(speed * 10.0, motion_blur, scatter, burst));

    // Depth: fast particles sit slightly proud of the plate.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(clamp(depth - motion_blur * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
