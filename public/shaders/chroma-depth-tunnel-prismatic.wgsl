// ═══════════════════════════════════════════════════════════════════
//  chroma-depth-tunnel-prismatic
//  Category: advanced-hybrid
//  Features: chroma-depth-tunnel, spec-prismatic-dispersion, depth-aware, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Chunks From: chroma-depth-tunnel, spec-prismatic-dispersion
//  Created: 2026-04-18
//  By: Agent CB-12 — Chroma & Spectral Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Deep chromatic tunnel with stylized prismatic dispersion.
//  RGB channels tunnel-map at different depths, then separate through
//  a Cauchy-inspired wavelength curve for an expressive glass look.
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

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn refractUV(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32) -> vec2<f32> {
    let toCenter = uv - center;
    let dist = length(toCenter);
    let lensStrength = curvature * 0.4;
    let offset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + dist * 2.0);
    return uv + offset;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held = step(0.5, u.zoom_config.w);

    let speed = (u.zoom_params.x - 0.5) * 2.0 * (1.0 + bass * 0.45);
    let density = u.zoom_params.y * 5.0 + 1.0;
    let chroma = u.zoom_params.z * 0.05;
    let centerFade = u.zoom_params.w;

    var mousePos = u.zoom_config.yz;
    if (mousePos.x < 0.0) { mousePos = vec2<f32>(0.5, 0.5); }

    let aspect = res.x / res.y;
    var p = uv - mousePos;
    let pointerPull = exp(-dot(p, p) * 18.0) * held;
    p *= 1.0 - pointerPull * 0.16;
    let p_aspect = vec2<f32>(p.x * aspect, p.y);
    let radius = length(p_aspect);
    let angle = atan2(p.y, p.x) + pointerPull * sin(time * 7.0) * 0.18;

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var rippleIndex: u32 = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
        let ripple = u.ripples[rippleIndex];
        let rippleAge = max(time - ripple.z, 0.0);
        let rippleDist = distance(uv, ripple.xy);
        let front = abs(rippleDist - rippleAge * (0.20 + bass * 0.10));
        clickFront += exp(-front * 115.0) * exp(-rippleAge * 1.5);
    }

    let u_coord = angle / 3.14159;
    let v_coord = 1.0 / (radius + 0.001);
    let axialPacket = pow(max(0.0, sin(v_coord * 0.55 - time * (13.0 + bass * 5.0))), 14.0);
    let spectralHelix = 0.5 + 0.5 * sin(angle * (4.0 + density) + radius * 38.0 - time * (9.0 + mids * 6.0));
    let tunnelUV = vec2<f32>(u_coord + spectralHelix * 0.018 + clickFront * 0.025,
                             v_coord * density + time * speed + axialPacket * 0.12);

    // Prismatic dispersion on tunnel-mapped UVs
    let glassCurvature = mix(0.1, 1.2, u.zoom_params.z);
    // `chroma` widens the stylized dispersion; mids push the spectrum apart.
    let cauchyB = mix(0.01, 0.08, u.zoom_params.y) + chroma * (1.0 + mids * 0.6);
    let glassThickness = mix(0.3, 1.5, u.zoom_params.w);
    let spectralSat = mix(0.3, 1.2, u.zoom_params.x);

    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var finalColor = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 4; i = i + 1) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
        let refractedUV = refractUV(tunnelUV, vec2<f32>(0.5), ior, glassCurvature + clickFront * 0.3);
        let wrappedUV = fract(refractedUV);
        let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
        let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.15);
        let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;
        finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
    }

    finalColor = finalColor / (1.0 + finalColor * 0.3);
    finalColor += wavelengthToRGB(470.0 + spectralHelix * 190.0) *
                  (axialPacket * (0.12 + treble * 0.35) + clickFront * 0.22);

    // Dark center / fog
    if (centerFade > 0.0) {
        let fog = smoothstep(0.0, centerFade, radius);
        finalColor = finalColor * fog;
    }

    // Bass fires a bright ring down the tunnel throat
    let throat = exp(-pow(radius * 8.0 - 1.0, 2.0) * 3.0) * bass;
    finalColor += vec3<f32>(0.6, 0.8, 1.0) * throat * 0.7;

    // Alpha: spectral energy — the tunnel core stays transparent
    let alpha = clamp(dot(finalColor, vec3<f32>(0.299, 0.587, 0.114)) * (1.0 + bass * 0.4) + throat, 0.0, 1.0);
    let outColor = vec4<f32>(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0)), alpha);

    textureStore(writeTexture, gid.xy, outColor);
    textureStore(dataTextureA, vec2<i32>(gid.xy), outColor);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
