// ═══════════════════════════════════════════════════════════════════
//  spec-spherical-harmonics-light
//  Category: advanced-hybrid
//  Features: spherical-harmonics, SH-lighting, depth-aware, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-31
//  Ideas: cosine-lobe irradiance; specular from L1; Fresnel-Schlick (§12.2F)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Spherical Harmonics Lighting
//  Uses spherical harmonic coefficients derived from the input image
//  to represent the lighting environment. Applies SH lighting to a
//  normal-mapped surface derived from depth.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn schlickFresnel(cosTheta: f32) -> f32 {
    let m = clamp(1.0 - cosTheta, 0.0, 1.0);
    let m2 = m * m;
    return 0.04 + 0.96 * m2 * m2 * m;
}

// Radiance SH, then the cosine-lobe irradiance ratios A1/A0 = 2/3 and A2/A0 = 1/4.
// L0 is left as it was so the ambient term does not jump.
fn evaluateSH(normal: vec3<f32>, coeffs: array<vec3<f32>, 9>) -> vec3<f32> {
    var result = coeffs[0] * 0.282095;
    // ── Idea 1: cosine-lobe irradiance ──────────────────────────────
    result += coeffs[1] * 0.488603 * normal.y * 0.6667;
    result += coeffs[2] * 0.488603 * normal.z * 0.6667;
    result += coeffs[3] * 0.488603 * normal.x * 0.6667;
    result += coeffs[4] * 1.092548 * normal.x * normal.y * 0.25;
    result += coeffs[5] * 1.092548 * normal.y * normal.z * 0.25;
    result += coeffs[6] * 0.315392 * (3.0 * normal.z * normal.z - 1.0) * 0.25;
    result += coeffs[7] * 1.092548 * normal.x * normal.z * 0.25;
    result += coeffs[8] * 0.546274 * (normal.x * normal.x - normal.y * normal.y) * 0.25;
    return result;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let texel = 1.0 / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let shStrength = mix(0.2, 2.0, u.zoom_params.x) * (1.0 + bass * 0.22);
    let normalScale = mix(0.5, 3.0, u.zoom_params.y);
    let specPower = mix(4.0, 64.0, u.zoom_params.z);
    let ambientBoost = mix(0.1, 0.8, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Sample base color and depth
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let baseColor = baseSample.rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Compute normal from depth using Sobel filter
    let dx = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r - depth;
    let dy = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r - depth;
    var normal = normalize(vec3<f32>(-dx * normalScale, -dy * normalScale, 1.0));

    // Mouse perturbs normal
    if (isMouseDown) {
        let toMouse = mousePos - uv;
        let mouseInfluence = exp(-dot(toMouse, toMouse) * 500.0);
        let mouseNormal = normalize(vec3<f32>(toMouse * 2.0, 1.0));
        normal = mix(normal, mouseNormal, mouseInfluence * 0.5);
    }

    // Derive SH coefficients from image content (simplified projection)
    // We approximate by sampling key directions and using the image color
    var coeffs = array<vec3<f32>, 9>();

    // L0 (ambient)
    coeffs[0] = baseColor * 0.5;

    // L1 (dominant light direction from image brightness gradient)
    let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));
    let gradX = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x * 4.0, 0.0), 0.0).rgb - baseColor;
    let gradY = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y * 4.0), 0.0).rgb - baseColor;

    coeffs[1] = gradY * 0.3; // Y
    coeffs[2] = vec3<f32>(luma) * 0.3; // Z (approximate sky/ground)
    coeffs[3] = gradX * 0.3; // X

    // L2 (color variation patterns)
    let chroma = baseColor - vec3<f32>(luma);
    coeffs[4] = chroma * 0.15; // XY
    coeffs[5] = gradY * 0.1;   // YZ
    coeffs[6] = vec3<f32>(depth * 0.2); // ZZ
    coeffs[7] = gradX * 0.1;   // XZ
    coeffs[8] = chroma * 0.1;  // XX-YY

    // Animated time-varying coefficient modulation
    for (var i = 0; i < 9; i = i + 1) {
        let phase = time * 0.2 + f32(i) * 0.7;
        coeffs[i] *= (1.0 + sin(phase) * 0.1);
    }

    // Evaluate SH lighting
    let shLight = evaluateSH(normal, coeffs) * shStrength;

    // ── Idea 2: specular from L1 ─────────────────────────────────────
    // coeffs[3], [1], [2] are the X, Y, Z linear terms already fit above.
    let lum3 = vec3<f32>(0.299, 0.587, 0.114);
    let l1 = vec3<f32>(
        dot(coeffs[3], lum3),
        dot(coeffs[1], lum3),
        abs(dot(coeffs[2], lum3)) + 0.25
    );
    let lightDir = l1 / max(length(l1), 0.001);
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let halfDir = normalize(lightDir + viewDir);
    let spec = pow(max(dot(normal, halfDir), 0.0), specPower);
    // ── Idea 3: Fresnel–Schlick (§12.2F) ────────────────────────────
    let specFres = spec * schlickFresnel(clamp(normal.z, 0.0, 1.0));

    let ambient = baseColor * ambientBoost;
    let litColor = ambient + baseColor * max(shLight, vec3<f32>(0.0)) + vec3<f32>(specFres * 0.3);
    let display = aces(max(litColor, vec3<f32>(0.0)));
    let alpha = clamp(baseSample.a * 0.6 + specFres * 0.45 + clamp(length(shLight), 0.0, 1.0) * 0.25, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(display, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(display, alpha));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
