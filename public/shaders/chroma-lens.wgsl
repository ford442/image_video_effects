// ═══════════════════════════════════════════════════════════════════
//  Chroma Lens
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-04
//  Ideas: 7-tap spectral dispersion (continuous rainbow fringes); astigmatic sagittal + tangential edge blur
//  A packing: pre-tone-map lens colour RGBA (C is not read back); writeTexture is ACES
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

// ─────────────────────────────────────────────────────────────────────────────
// ACES Tone Mapping
// ─────────────────────────────────────────────────────────────────────────────
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    let m2 = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    let v = m1 * color;
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Approximate visible-spectrum colour of a wavelength in nm.
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let r = select(select(1.0, (lambda - 510.0) / 70.0, lambda < 580.0), (440.0 - lambda) / 60.0, lambda < 440.0);
    let g = select(select(select(0.0, (645.0 - lambda) / 65.0, lambda < 645.0), 1.0, lambda < 580.0), (lambda - 440.0) / 50.0, lambda < 490.0);
    let b = select(select(0.0, (510.0 - lambda) / 20.0, lambda < 510.0), 1.0, lambda < 490.0);
    return clamp(vec3<f32>(r, select(g, 0.0, lambda < 440.0), b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Params — bass breathes the lens, mids widen the chroma split
    let mag = u.zoom_params.x * (1.0 + bass * 0.4);        // Magnification (0-1)
    let aberration = u.zoom_params.y * (1.0 + mids * 0.5); // Chroma Separation (0-1)
    let radius = u.zoom_params.z * (1.0 + bass * 0.3);     // Lens Radius (0-1)
    let blurEdges = u.zoom_params.w;      // Blur Amount (0-1)

    // Mouse
    var mouse = u.zoom_config.yz;
    let heldLens = step(0.5, u.zoom_config.w);
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let dVec = (uv - mouse) * aspectVec;
    let dist = length(dVec);
    let activeRadius = max(0.001, radius * (1.0 + heldLens * 0.18));

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let delta = (uv - ripple.xy) * aspectVec;
            clickFront += smoothstep(0.022, 0.0, abs(length(delta) - age * 0.44)) * exp(-age * 1.5);
        }
    }

    // Barrel magnification (unchanged curve) and edge-weighted aberration.
    var lensCurve = 1.0;
    var abbStrength = 0.0;
    var ndist = 1.0;
    if (dist < activeRadius) {
        ndist = dist / activeRadius;
        lensCurve = 1.0 - (1.0 - ndist * ndist) * mag;
        abbStrength = aberration * 0.05 * ndist * (1.0 + clickFront);
    }
    let edgeBand = smoothstep(activeRadius * 0.55, activeRadius, dist) * (1.0 - smoothstep(activeRadius, activeRadius + 0.02, dist));
    let tangent = vec2<f32>(-dVec.y, dVec.x) / max(dist, 0.001);
    let blurOffset = tangent * blurEdges * edgeBand * 0.006;
    // Idea 2: astigmatism. Off-axis a real lens focuses radial (sagittal) and
    // tangential detail at different depths, so the edge blur is a cross: the
    // existing tangential smear plus a shorter radial one growing with ndist².
    let radialDir = dVec / max(dist, 0.001);
    let sagittalOffset = vec2<f32>(radialDir.x / aspect, radialDir.y) * blurEdges * edgeBand * 0.0035 * ndist * ndist;

    // Idea 1: spectral dispersion. Seven wavelengths from red to violet each
    // get their own scale factor (red spreads out, violet pulls in, as the old
    // R/B taps did) and are recombined by their spectral colour, so the fringe
    // is a continuous rainbow instead of three offset copies.
    var spectral = vec3<f32>(0.0);
    var weightSum = vec3<f32>(0.0);
    for (var i = 0; i < 7; i = i + 1) {
        let t = f32(i) / 6.0;
        let lambda = mix(650.0, 420.0, t);
        let w = wavelengthToRGB(lambda) + vec3<f32>(0.02);
        let factor = lensCurve + abbStrength * mix(-1.0, 1.0, t);
        var tapUV = mouse + (uv - mouse) * factor;
        let phase = i % 3;
        tapUV = tapUV + select(select(-sagittalOffset, blurOffset, phase == 1), vec2<f32>(0.0), phase == 0);
        let tap = textureSampleLevel(readTexture, u_sampler, clamp(tapUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        spectral = spectral + tap * w;
        weightSum = weightSum + w;
    }
    let lensRGB = spectral / max(weightSum, vec3<f32>(0.0001));
    let r = lensRGB.r;
    let g = lensRGB.g;
    let b = lensRGB.b;
    let safeG = clamp(mouse + (uv - mouse) * lensCurve, vec2<f32>(0.0), vec2<f32>(1.0));
    // Source alpha follows the green (undisplaced) channel's sample point
    let srcAlpha = textureSampleLevel(readTexture, u_sampler, safeG, 0.0).a;

    // Add a rim/glass reflection effect at the edge
    var color = vec4<f32>(r, g, b, srcAlpha);

    let rim = smoothstep(activeRadius * 0.88, activeRadius, dist) * (1.0 - smoothstep(activeRadius, activeRadius + 0.012, dist));
    let angle = atan2(dVec.y, dVec.x);
    let rimRunner = pow(max(0.0, sin(angle * 14.0 - time * 15.0)), 12.0) * rim;
    color = mix(color, vec4<f32>(1.0, 0.75 + mids * 0.2, 1.0, 1.0), clamp(rim * blurEdges * 0.3 + rimRunner * 0.35 + clickFront * 0.4, 0.0, 0.8));

    // Antialiased circle edge — glass body reads slightly more solid than the plate
    let mask = 1.0 - smoothstep(activeRadius, activeRadius + 0.01, dist);
    color.a = clamp(color.a + mask * 0.15, 0.0, 1.0);

    // If we are outside the lens, just show original
    // But we computed lens distortion inside.
    // The if(dist < radius) handled the UV modification.
    // Outside that, finalUV is original UV.
    // So this is seamless.

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(aces_tonemap(color.rgb), color.a));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), color);

    // Passthrough Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
