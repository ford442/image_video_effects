// ═══════════════════════════════════════════════════════════════════
//  kimi-flock-symphony-em
//  Category: advanced-hybrid
//  Features: flocking-particles, electromagnetic-fields,
//            mouse-driven, chromatic, audio-reactive
//  Complexity: Very High
//  Chunks From: kimi_flock_symphony.wgsl, mouse-electromagnetic-aurora.wgsl
//  Created: 2026-04-18
//  By: Agent CB-16 — Generative & Cosmic Enhancer
// ═══════════════════════════════════════════════════════════════════
//  A symphony of pseudo-flocking particles whose trajectories are
//  bent by electromagnetic field lines generated from mouse motion.
//  Electric fields displace UVs; magnetic fields rotate particle
//  hues. Ripple clicks spawn orbiting charge pairs that disturb
//  the flock with vortex forces.
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

fn hash(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i.x + i.y * 57.0), hash(i.x + 1.0 + i.y * 57.0), u.x),
               mix(hash(i.x + (i.y + 1.0) * 57.0), hash(i.x + 1.0 + (i.y + 1.0) * 57.0), u.x), u.y);
}

fn hsl_to_rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs(fract(h * 6.0) * 2.0 - 1.0));
    let m = l - c * 0.5;
    var rgb: vec3<f32>;
    if (h < 1.0 / 6.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0 / 6.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0 / 6.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0 / 6.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0 / 6.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(m);
}

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn electricField(pos: vec2<f32>, chargePos: vec2<f32>, charge: f32) -> vec2<f32> {
    let r = pos - chargePos;
    let dist = max(length(r), 0.001);
    return charge * normalize(r) / (dist * dist);
}

fn magneticField(pos: vec2<f32>, chargePos: vec2<f32>, velocity: vec2<f32>, charge: f32) -> f32 {
    let r = pos - chargePos;
    let dist = max(length(r), 0.001);
    return charge * (velocity.x * r.y - velocity.y * r.x) / (dist * dist * dist);
}

fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 1.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let resolution = vec2<f32>(textureDimensions(readTexture));
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    let chargeStrength = u.zoom_params.x * 2.0;
    let glow_radius = u.zoom_params.y * 8.0 + 2.0;
    let color_shift = u.zoom_params.z;
    let density = u.zoom_params.w;

    // ═══ EM Fields from Mouse ═══
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
    let mousePos = u.zoom_config.yz;
    let mouseVel = (mousePos - prevMouse) * 60.0;
    let mouseDown = u.zoom_config.w;

    if (gid.x == 0u && gid.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
    }

    let eField = electricField(uv, mousePos, chargeStrength);
    let bField = magneticField(uv, mousePos, mouseVel, chargeStrength);

    var totalE = eField;
    var totalB = bField;

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 3.0) {
            let orbitAngle = elapsed * 2.0 + f32(i) * 1.256;
            let orbitRadius = 0.05 + 0.1 * smoothstep(0.0, 1.0, elapsed);
            let orbitPos = mousePos + vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * orbitRadius;
            let secondaryCharge = -chargeStrength * exp(-elapsed * 0.8);
            let secVel = vec2<f32>(-sin(orbitAngle), cos(orbitAngle)) * 2.0;
            totalE += electricField(uv, orbitPos, secondaryCharge);
            totalB += magneticField(uv, orbitPos, secVel, secondaryCharge);
        }
    }

    let fieldMag = length(totalE);
    let fieldDir = select(vec2<f32>(0.0), normalize(totalE), fieldMag > 0.0001);

    // ═══ Pseudo-Flock Particles with EM Influence ═══
    var accumulated_color = vec3<f32>(0.0);
    var accumulated_density = 0.0;
    let particle_opacity = 0.6;
    let sample_count = 2048u;

    for (var i: u32 = 0u; i < sample_count; i = i + 1u) {
        // Deterministic pseudo-particle from hash
        let seed = f32(i) * 1.61803398875;
        var b_pos = vec2<f32>(hash(seed), hash(seed + 100.0));

        // Apply EM field displacement to particle position
        let emDisp = fieldDir * fieldMag * 0.02 + vec2<f32>(-totalE.y, totalE.x) * totalB * 0.01;
        b_pos = fract(b_pos + emDisp + vec2<f32>(
            noise(b_pos * 10.0 + time + f32(i)),
            noise(b_pos * 10.0 + time + f32(i) + 100.0)
        ) * 0.02);

        let bx = b_pos.x * resolution.x;
        let by = b_pos.y * resolution.y;
        let pixel_pos = vec2<f32>(f32(coord.x), f32(coord.y));

        let vel = vec2<f32>(
            noise(b_pos * 20.0 + time * 0.5),
            noise(b_pos * 20.0 + time * 0.5 + 50.0)
        );

        var d = distance(pixel_pos, vec2<f32>(bx, by));

        if (d < glow_radius) {
            let speed = length(vel);
            let alpha = softParticleAlpha(d, glow_radius) * particle_opacity;

            // Hue rotated by magnetic field
            var b_hue = fract(hash(seed + 200.0) + color_shift + totalB * 0.1);
            var rgb = hsl_to_rgb(b_hue, 0.8, 0.5);

            // EM field color shift
            rgb = hueShift(rgb, totalB * color_shift * 0.5);

            let emission = 1.0 + speed * 0.5;
            let hdr_rgb = rgb * (0.5 + emission * 2.0);

            accumulated_color += hdr_rgb * alpha * density;
            accumulated_density += alpha;
        }
    }

    // Center glow at mouse
    let mousePixel = mousePos * resolution;
    let mouse_dist = distance(vec2<f32>(f32(coord.x), f32(coord.y)), mousePixel);
    let mouse_alpha = softParticleAlpha(mouse_dist, 100.0) * 0.5;
    accumulated_color += vec3<f32>(1.0, 0.9, 0.7) * mouse_alpha;
    accumulated_density += mouse_alpha;

    // Tone mapping
    accumulated_color = accumulated_color / (1.0 + accumulated_color);
    accumulated_color = pow(accumulated_color, vec3<f32>(0.8));

    // Exponential transmittance alpha
    let trans = exp(-accumulated_density * 0.5);
    let final_alpha = 1.0 - trans;

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    accumulated_color *= vignette;

    // Field line overlay on background
    let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
    let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
    let streamline = smoothstep(0.4, 0.6, streamNoise) * smoothstep(0.0, 0.5, fieldMag);
    let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
    accumulated_color = mix(accumulated_color, fieldColor, streamline * 0.3);

    // Core glow
    let coreGlow = exp(-mouse_dist * mouse_dist * 0.0001) * chargeStrength;
    accumulated_color += vec3<f32>(0.6, 0.9, 1.0) * coreGlow * 0.5;

    textureStore(writeTexture, coord, vec4<f32>(accumulated_color, clamp(final_alpha, 0.0, 1.0)));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
}
