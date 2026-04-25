// ═══════════════════════════════════════════════════════════════════
//  Photonic Caustics Iridescence
//  Category: advanced-hybrid
//  Features: depth-aware, temporal, spectral-render, caustics
//  Complexity: Very High
//  Chunks From: photonic-caustics.wgsl (photon tracing, Fresnel),
//               spec-iridescence-engine.wgsl (thin-film interference)
//  Created: 2026-04-18
//  By: Agent CB-11
// ═══════════════════════════════════════════════════════════════════
//  Backward photon-traced caustics combined with thin-film interference.
//  Caustic intensity modulates film thickness, creating iridescent
//  soap-bubble colors on refractive light concentrations.
//  R,G,B = Iridescent caustic color
//  A = Normalized film thickness (for downstream compositing)
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

const PI: f32 = 3.14159265359;
const PHOTON_COUNT: i32 = 16;

// ═══ CHUNK: hash21 (from photonic-caustics.wgsl) ═══
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: hash31 (from photonic-caustics.wgsl) ═══
fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: noise2D (from photonic-caustics.wgsl) ═══
fn noise2D(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ═══ CHUNK: fbm (from photonic-caustics.wgsl) ═══
fn fbm(p: vec2<f32>, time: f32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 4; i = i + 1) {
        value = value + amplitude * noise2D(p * freq + vec2<f32>(time * 0.2, time * 0.15));
        freq = freq * 2.0;
        amplitude = amplitude * 0.5;
    }
    return value;
}

// ═══ CHUNK: getSurfaceNormal (from photonic-caustics.wgsl) ═══
fn getSurfaceNormal(uv: vec2<f32>, texelSize: vec2<f32>, time: f32) -> vec3<f32> {
    let h = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let hL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texelSize.x, 0.0), 0.0).r;
    let hR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r;
    let hU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texelSize.y), 0.0).r;
    let hD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r;

    let noiseScale = 8.0;
    let noiseAmp = 0.1;
    let nL = fbm(uv * noiseScale + vec2<f32>(-texelSize.x * noiseScale, 0.0), time) * noiseAmp;
    let nR = fbm(uv * noiseScale + vec2<f32>(texelSize.x * noiseScale, 0.0), time) * noiseAmp;
    let nU = fbm(uv * noiseScale + vec2<f32>(0.0, -texelSize.y * noiseScale), time) * noiseAmp;
    let nD = fbm(uv * noiseScale + vec2<f32>(0.0, texelSize.y * noiseScale), time) * noiseAmp;

    let dx = ((hR + nR) - (hL + nL)) * 2.0;
    let dy = ((hD + nD) - (hU + nU)) * 2.0;

    return normalize(vec3<f32>(-dx, -dy, 0.2));
}

// ═══ CHUNK: fresnelSchlick (from photonic-caustics.wgsl) ═══
fn fresnelSchlick(cosTheta: f32, ior: f32) -> f32 {
    let r0 = (1.0 - ior) / (1.0 + ior);
    let r0sq = r0 * r0;
    return r0sq + (1.0 - r0sq) * pow(1.0 - cosTheta, 5.0);
}

// ═══ CHUNK: refractRay (from photonic-caustics.wgsl) ═══
fn refractRay(incident: vec3<f32>, normal: vec3<f32>, eta: f32) -> vec3<f32> {
    let cosi = -dot(normal, incident);
    let sin2t = eta * eta * (1.0 - cosi * cosi);
    if (sin2t > 1.0) {
        return reflect(incident, normal);
    }
    let cost = sqrt(1.0 - sin2t);
    return incident * eta + normal * (eta * cosi - cost);
}

// ═══ CHUNK: wavelengthToRGB (from spec-iridescence-engine.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

// ═══ CHUNK: thinFilmColor (from spec-iridescence-engine.wgsl) ═══
fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;

    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let texelSize = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Parameters
    let baseIOR = mix(1.1, 1.8, u.zoom_params.x);
    let lightSize = mix(0.05, 0.3, u.zoom_params.y);
    let dispersion = mix(0.0, 0.1, u.zoom_params.z);
    let intensity = mix(0.5, 3.0, u.zoom_params.w);

    let lightPos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let lightHeight = mix(0.5, 2.0, u.zoom_config.w);

    // Read previous accumulation
    let prevCaustic = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Surface normal
    let surfaceNormal = getSurfaceNormal(uv, texelSize, time);

    // === PHOTON TRACING ===
    var causticAccum = vec3<f32>(0.0);
    for (var p = 0; p < PHOTON_COUNT; p = p + 1) {
        let seed = vec3<f32>(uv, f32(p) + time * 0.01);
        let randomAngle = hash31(seed) * 2.0 * PI;
        let randomRadius = sqrt(hash31(seed + vec3<f32>(1.0, 0.0, 0.0))) * lightSize;
        let photonOrigin = lightPos + vec2<f32>(cos(randomAngle), sin(randomAngle)) * randomRadius;

        let toPixel = uv - photonOrigin;
        let dist2D = length(toPixel);
        let dir2D = toPixel / max(dist2D, 0.001);
        var lightDir = normalize(vec3<f32>(dir2D, -lightHeight));

        let cosTheta = abs(dot(lightDir, surfaceNormal));

        let iorR = baseIOR - dispersion;
        let iorG = baseIOR;
        let iorB = baseIOR + dispersion;

        let refractR = refractRay(lightDir, surfaceNormal, 1.0 / iorR);
        let refractG = refractRay(lightDir, surfaceNormal, 1.0 / iorG);
        let refractB = refractRay(lightDir, surfaceNormal, 1.0 / iorB);

        let convergenceR = abs(dot(refractR, vec3<f32>(0.0, 0.0, -1.0)));
        let convergenceG = abs(dot(refractG, vec3<f32>(0.0, 0.0, -1.0)));
        let convergenceB = abs(dot(refractB, vec3<f32>(0.0, 0.0, -1.0)));

        let fresnel = 1.0 - fresnelSchlick(cosTheta, baseIOR);
        let attenuation = 1.0 / (1.0 + dist2D * 5.0);

        let causticR = pow(convergenceR, 4.0) * fresnel * attenuation;
        let causticG = pow(convergenceG, 4.0) * fresnel * attenuation;
        let causticB = pow(convergenceB, 4.0) * fresnel * attenuation;

        causticAccum += vec3<f32>(causticR, causticG, causticB);
    }

    causticAccum = causticAccum / f32(PHOTON_COUNT);
    causticAccum = causticAccum * intensity;

    // Ripple caustics
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let rippleAge = time - ripple.z;
            if (rippleAge > 0.0 && rippleAge < 3.0) {
                let toRipple = uv - ripple.xy;
                let dist = length(toRipple);
                let rippleStrength = (1.0 - rippleAge / 3.0) * 0.5;
                let angle = atan2(toRipple.y, toRipple.x);
                let wave = sin(dist * 30.0 - rippleAge * 5.0) * 0.5 + 0.5;
                let causticRing = wave * rippleStrength / (1.0 + dist * 10.0);
                causticAccum += vec3<f32>(causticRing * 0.5, causticRing * 0.7, causticRing * 1.0);
            }
        }
    }

    // Temporal accumulation
    let blendFactor = 0.15;
    let accumulatedCaustic = mix(prevCaustic.rgb, causticAccum, blendFactor);

    // Store accumulated caustics for feedback
    textureStore(dataTextureA, coord, vec4<f32>(accumulatedCaustic, 1.0));

    // === THIN-FILM IRIDESCENCE ===
    let causticIntensity = dot(accumulatedCaustic, vec3<f32>(0.299, 0.587, 0.114));

    let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.x);
    let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
    let iridIntensity = mix(0.3, 1.5, u.zoom_params.z);
    let turbulence = mix(0.0, 1.0, u.zoom_params.w);

    // Viewing angle
    let toCenter = uv - vec2<f32>(0.5);
    let dist = length(toCenter);
    let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

    // Caustic intensity modulates film thickness
    let noiseVal = hash21(uv * 12.0 + time * 0.1) * 0.5
                 + hash21(uv * 25.0 - time * 0.15) * 0.25;
    var thickness = filmThicknessBase * (0.5 + causticIntensity * 2.0 + noiseVal * turbulence);

    // Mouse perturbation
    let isMouseDown = u.zoom_config.w > 0.5;
    if (isMouseDown) {
        let mouseDist = length(uv - lightPos);
        let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
        thickness += mouseInfluence * 300.0 * sin(time * 3.0 + mouseDist * 30.0);
    }

    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * iridIntensity;

    // Fresnel blend
    let fresnelBlend = pow(1.0 - cosTheta, 3.0);

    // Source image
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Refract source through surface
    let refractDisplace = surfaceNormal.xy * 0.02;
    let colorR = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace + vec2<f32>(dispersion * 0.01, 0.0), 0.0).r;
    let colorG = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace, 0.0).g;
    let colorB = textureSampleLevel(readTexture, u_sampler, uv + refractDisplace - vec2<f32>(dispersion * 0.01, 0.0), 0.0).b;
    let refractedChromatic = vec3<f32>(colorR, colorG, colorB);

    // Composite: source -> refracted -> caustics -> iridescence
    var finalColor = mix(sourceColor.rgb, refractedChromatic, 0.3);
    finalColor = finalColor + accumulatedCaustic;
    finalColor = mix(finalColor, iridescent, fresnelBlend * 0.7 * causticIntensity);

    // Specular highlight
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let reflectDir = reflect(-viewDir, surfaceNormal);
    var lightDir3D = normalize(vec3<f32>(lightPos - uv, lightHeight));
    let specular = pow(max(dot(reflectDir, lightDir3D), 0.0), 64.0);
    finalColor += vec3<f32>(specular * 0.5);

    // HDR tone map
    finalColor = finalColor / (1.0 + finalColor * 0.2);
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha = normalized film thickness (meaningful for downstream)
    let filmAlpha = clamp(thickness / 1200.0, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(finalColor, filmAlpha));

    // Depth pass-through
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
