// ═══════════════════════════════════════════════════════════════════
//  Gravity Well EM
//  Category: advanced-hybrid
//  Features: gravitational-lensing, electromagnetic-fields, chromatic,
//            mouse-driven, depth-aware
//  Complexity: Very High
//  Chunks From: gravity-well, mouse-electromagnetic-aurora
//  Created: 2026-04-18
//  By: Agent CB-26
// ═══════════════════════════════════════════════════════════════════
//  A massive charged singularity: gravitational pinch distortion
//  combined with electric field displacement and magnetic hue rotation.
//  Mouse controls the charged mass; ripples spawn orbiting secondary
//  charges. Chromatic aberration from both gravity and EM fields.
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

// ═══ CHUNK: hash12 (from mouse-electromagnetic-aurora) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: hueShift (from mouse-electromagnetic-aurora) ═══
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    // Parameters
    let strength = u.zoom_params.x;
    let radius = u.zoom_params.y * 0.4;
    let aberration = u.zoom_params.z * 0.1;
    let density = u.zoom_params.w;
    let chargeStrength = strength * 2.0;
    let colorRotation = aberration * 3.14159;

    let aspect = res.x / res.y;
    let mouse = u.zoom_config.yz;

    // Gravity well vector
    let d_vec_raw = uv - mouse;
    let d_vec_aspect = vec2<f32>(d_vec_raw.x * aspect, d_vec_raw.y);
    let dist = length(d_vec_aspect);

    var finalColor = vec3<f32>(0.0);
    var finalAlpha = 1.0;
    var distortionMag = 0.0;

    if (dist > radius) {
        // === GRAVITATIONAL LENSING ===
        let distSurface = dist - radius;
        let falloff = 1.0 / (pow(distSurface, density) * 10.0 + 1.0);
        let pull = strength * falloff;
        distortionMag = pull;

        var dir = normalize(d_vec_aspect);
        let shift_aspect = dir * pull * 0.1;
        let shift = vec2<f32>(shift_aspect.x / aspect, shift_aspect.y);
        let sample_uv_center = uv - shift;

        // === EM FIELD ===
        let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
        let mouseVel = (mouse - prevMouse) * 60.0;
        let mouseDown = u.zoom_config.w;

        // Store current mouse for next frame
        if (gid.x == 0u && gid.y == 0u) {
            textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mouse, 0.0, 0.0));
        }

        let eField = electricField(uv, mouse, chargeStrength);
        let bField = magneticField(uv, mouse, mouseVel, chargeStrength);

        // Secondary charges from ripples
        var totalE = eField;
        var totalB = bField;
        let rippleCount = min(u32(u.config.y), 50u);
        for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
            let ripple = u.ripples[i];
            let elapsed = time - ripple.z;
            if (elapsed > 0.0 && elapsed < 3.0) {
                let orbitAngle = elapsed * 2.0 + f32(i) * 1.256;
                let orbitRadius = 0.05 + 0.1 * smoothstep(0.0, 1.0, elapsed);
                let orbitPos = mouse + vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * orbitRadius;
                let secondaryCharge = -chargeStrength * exp(-elapsed * 0.8);
                let secVel = vec2<f32>(-sin(orbitAngle), cos(orbitAngle)) * 2.0;
                totalE += electricField(uv, orbitPos, secondaryCharge);
                totalB += magneticField(uv, orbitPos, secVel, secondaryCharge);
            }
        }

        let fieldMag = length(totalE);
        let fieldDir = select(vec2<f32>(0.0), normalize(totalE), fieldMag > 0.0001);

        // Combined UV displacement: gravity + electric field
        let emDisplacement = fieldDir * aberration * smoothstep(0.0, 2.0, fieldMag);
        let uv_r = sample_uv_center + shift * aberration * 5.0 + emDisplacement;
        let uv_b = sample_uv_center - shift * aberration * 5.0 + emDisplacement;
        let uv_g = sample_uv_center + emDisplacement;

        let sampleR = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0);
        let sampleG = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0);
        let sampleB = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0);

        finalColor = vec3<f32>(sampleR.r, sampleG.g, sampleB.b);

        // Magnetic hue rotation
        let hueRot = totalB * colorRotation * 0.5;
        finalColor = hueShift(finalColor, hueRot);

        // Accretion disk glow + EM core glow
        let glow = exp(-distSurface * 20.0) * strength;
        let glowColor = vec3<f32>(0.5, 0.2, 0.8) * glow;
        let coreGlow = exp(-dist * dist * 400.0) * chargeStrength;
        let emGlowColor = vec3<f32>(0.6, 0.9, 1.0);
        finalColor += glowColor + emGlowColor * coreGlow * 0.3;

        // Field line overlay
        let streamUV = uv + fieldDir * hash12(uv * 100.0 + time * 0.5) * 0.02;
        let streamNoise = hash12(streamUV * 200.0 + fieldMag * 10.0);
        let streamline = smoothstep(0.4, 0.6, streamNoise) * smoothstep(0.0, 0.5, fieldMag);
        let fieldColor = mix(vec3<f32>(0.0, 0.6, 1.0), vec3<f32>(1.0, 0.8, 0.0), atan2(fieldDir.y, fieldDir.x) * 0.159 + 0.5);
        finalColor = mix(finalColor, fieldColor, streamline * 0.3);

        // Alpha: combined gravity pinch + EM scattering
        let compressionFactor = 1.0 + distortionMag * 0.2;
        let scatteringLoss = distortionMag * 0.4;
        let chromaticScatter = aberration * distortionMag * 0.5;
        finalAlpha = clamp((sampleR.a + sampleG.a + sampleB.a) / 3.0 * compressionFactor - scatteringLoss - chromaticScatter, 0.4, 1.0);
        finalAlpha = min(finalAlpha + glow * 0.5, 1.0);
    } else {
        // Event horizon - dark with EM aura edge
        let edge = smoothstep(radius, radius * 0.95, dist);
        finalColor = vec3<f32>(0.02, 0.0, 0.05) * (1.0 - edge);
        finalAlpha = 1.0;
    }

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = 1.0 - distortionMag * 0.1;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
