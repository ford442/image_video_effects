// ═══════════════════════════════════════════════════════════════════
//  Aurora Borealis Synthesis
//  Category: generative
//  Features: volumetric-raymarch, audio-reactive, mouse-ripples, upgraded-rgba,
//            chromatic-wavelength-split, temporal-aurora, audio-storm, depth-output
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: altitude emission layers (557nm green / 630nm red / blue-magenta edge); sheared curtain pleats with altitude parallax; click substorm arcs (age-based)
//  A packing: aurora-glow layer (linear, base image excluded) + coverage alpha; writeTexture is ACES display
// ═══════════════════════════════════════════════════════════════════

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


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

fn hash3(p: vec3<f32>) -> f32 {
    let p2 = fract(p * 0.3183099 + vec3<f32>(0.1, 0.1, 0.1));
    let q = p2 * 17.0;
    return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);
    let n = p.x + p.y * 57.0 + 113.0 * p.z;
    let res = mix(
        mix(
            mix(hash3(p), hash3(p + vec3<f32>(1.0, 0.0, 0.0)), f2.x),
            mix(hash3(p + vec3<f32>(0.0, 1.0, 0.0)), hash3(p + vec3<f32>(1.0, 1.0, 0.0)), f2.x),
            f2.y
        ),
        mix(
            mix(hash3(p + vec3<f32>(0.0, 0.0, 1.0)), hash3(p + vec3<f32>(1.0, 0.0, 1.0)), f2.x),
            mix(hash3(p + vec3<f32>(0.0, 1.0, 1.0)), hash3(p + vec3<f32>(1.0, 1.0, 1.0)), f2.x),
            f2.y
        ),
        f2.z
    );
    return res;
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var p2 = p;
    for (var i = 0u; i < 4u; i++) {
        f += amp * noise3(p2);
        p2 *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// IDEA 1: altitude emission palette. alt 0 = lower edge, 1 = top of the volume.
// Replaces the plasmaBuffer[color_index] LUT (only index 0 is ever uploaded).
fn emissionAltitude(alt: f32) -> vec3<f32> {
    let wMag = 1.0 - smoothstep(0.0, 0.22, alt);                                   // blue-magenta lower edge
    let wGrn = smoothstep(0.04, 0.26, alt) * (1.0 - smoothstep(0.46, 0.78, alt));  // 557 nm green base
    let wRed = smoothstep(0.52, 0.92, alt);                                        // 630 nm red upper fringe
    return vec3<f32>(0.62, 0.10, 0.85) * wMag * 0.8
         + vec3<f32>(0.12, 1.00, 0.32) * wGrn
         + vec3<f32>(1.00, 0.07, 0.10) * wRed * 1.7; // boost: the depth fade dims the top layers
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(readTexture);
    let uv = vec2<f32>(id.xy) / vec2<f32>(dims);

    if (id.x >= dims.x || id.y >= dims.y) {
        return;
    }

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let base_color = textureLoad(readTexture, vec2<i32>(id.xy), 0);

    var accumulated_color = vec3<f32>(0.0);
    var accumulated_alpha = 0.0;

    let storm_dir = u.zoom_config.yz;
    let swirl_speed = max(0.1, u.zoom_params.y);
    let volume_height = max(0.5, u.zoom_params.x);
    let brightness_scale = max(0.1, u.zoom_params.z);

    let storm = storm_dir * (u.zoom_params.w * 2.0); // w=0.5 default -> unchanged drift
    let motion_offset = time * swirl_speed * 0.5 + vec3<f32>(storm.x * time, bass * 2.0, storm.y * time);

    let ray_dir = normalize(vec3<f32>(uv * 2.0 - 1.0, 1.0));
    let steps = 20;
    let step_size = volume_height / f32(steps);
    var p = vec3<f32>(uv * 10.0, 0.0) + motion_offset;
    let lift = volume_height * 6.0; // parallax of one full altitude, in noise units

    for (var i = 0; i < steps; i++) {
        p += ray_dir * step_size;
        let alt = f32(i) / f32(steps - 1);

        // IDEA 2: curtain pleats. Fold x by a slow sine of y, compress y so features
        // stretch into vertical rays, and lift y with altitude so each layer sees a
        // different noise slice (parallax) instead of the same 2D pattern.
        let fold = 1.5 * sin(0.4 * p.y + 0.2 * p.x);
        let q = vec3<f32>(p.x + fold, p.y * 0.3 + alt * lift, p.z);
        let rays = 0.65 + 0.7 * noise3(vec3<f32>(q.x * 5.0, 7.3, p.z * 2.0)); // constant in y -> vertical rays

        // Chromatic wavelength splitting: R and B sample at different heights
        let nR = fbm(q + vec3<f32>(0.0, treble * 0.8, 0.0));
        let nG = fbm(q + vec3<f32>(0.0, mids * 0.5, 0.0));
        let nB = fbm(q + vec3<f32>(0.0, bass * 0.3, 0.0));

        var intensityR = smoothstep(0.4, 0.8, nR);
        var intensityG = smoothstep(0.4, 0.8, nG);
        var intensityB = smoothstep(0.4, 0.8, nB);
        let fade = (1.0 - (f32(i) / f32(steps))) * rays;
        intensityR *= fade;
        intensityG *= fade;
        intensityB *= fade;

        if (max(intensityR, max(intensityG, intensityB)) > 0.0) {
            let mapped_color = emissionAltitude(alt); // IDEA 1
            accumulated_color += vec3<f32>(mapped_color.r * intensityR, mapped_color.g * intensityG, mapped_color.b * intensityB) * brightness_scale * step_size * 10.0;
            accumulated_alpha += intensityG * 0.1;
        }

        if (accumulated_alpha >= 1.0) { break; }
    }

    // Temporal aurora persistence: previous frame's aurora glow (A excludes the base image)
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0).rgb;
    accumulated_color = mix(accumulated_color, prev * 0.9, 0.08 + bass * 0.02);

    // IDEA 3: click substorm arcs. Each click launches an east-west brightening
    // front that rises poleward (screen up): sharp lower edge, diffuse upper edge,
    // coloured by the altitude palette (magenta below, green at, red above).
    let aspect = f32(dims.x) / f32(dims.y);
    let rippleCount = min(u32(u.config.y), 50u);
    var arc_light = vec3<f32>(0.0);
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 4.0) {
            let d = uv - ripple.xy;
            let wavy = 0.02 * sin(d.x * aspect * 14.0 + age * 3.0);
            let s = ((ripple.y - age * 0.12 + wavy) - uv.y) / 0.05; // >0 above the front
            let profile = exp(-s * s * select(4.0, 0.5, s > 0.0));   // sharp below, diffuse above
            let width = 0.06 + age * 0.05;
            let extent = exp(-(d.x * aspect) * (d.x * aspect) / (width * width * 4.0));
            let ray = 0.6 + 0.8 * noise3(vec3<f32>(uv.x * 40.0, 3.1, time * 0.3));
            let life = (1.0 - age * 0.25) * smoothstep(0.0, 0.15, age);
            arc_light += emissionAltitude(clamp(0.28 + s * 0.3, 0.0, 1.0)) * profile * extent * ray * life;
        }
    }
    accumulated_color += arc_light * 0.9 * brightness_scale * 2.0;

    let final_color = base_color.rgb + accumulated_color;
    let alpha = clamp(accumulated_alpha + base_color.a * 0.5, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(id.xy), applyGenerativePrimaryControls(vec4<f32>(final_color, alpha)));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(accumulated_color, clamp(accumulated_alpha, 0.0, 1.0)));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(clamp(accumulated_alpha, 0.0, 1.0), 0.0, 0.0, 0.0));
}
