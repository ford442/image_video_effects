// ═══════════════════════════════════════════════════════════════════
//  glass-refraction-prismatic
//  Category: advanced-hybrid
//  Features: raymarched, spectral-dispersion, physical-refraction, mouse-driven
//  Complexity: Very High
//  Chunks From: glass_refraction_alpha (SDF, Fresnel, raymarch), spec-prismatic-dispersion (Cauchy IOR, CIE matching)
//  Created: 2026-04-18
//  By: Agent CB-6 — Alpha & Post-Process Enhancer
// ═══════════════════════════════════════════════════════════════════
//  3D Glass Refraction with 4-Band Spectral Dispersion
//  Raymarches animated glass blobs and refracts four physical wavelength
//  bands (450nm, 520nm, 600nm, 680nm) through each surface using
//  Cauchy's equation. Color is reconstructed with CIE 1931 matching.
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

// ═══ CHUNK: SDF primitives (from glass_refraction_alpha.wgsl) ═══
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn smoothUnion(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>, time: f32) -> f32 {
    let blob1 = sdSphere(p - vec3<f32>(sin(time * 0.5) * 0.2, 0.0, 0.0), 0.25);
    let blob2 = sdSphere(p - vec3<f32>(cos(time * 0.3) * 0.2, sin(time * 0.4) * 0.15, 0.1), 0.2);
    let blob3 = sdSphere(p - vec3<f32>(0.0, cos(time * 0.6) * 0.15, sin(time * 0.5) * 0.1), 0.18);
    return smoothUnion(smoothUnion(blob1, blob2, 0.1), blob3, 0.08);
}

fn calcNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let eps = 0.001;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(eps, 0.0, 0.0), time) - map(p - vec3<f32>(eps, 0.0, 0.0), time),
        map(p + vec3<f32>(0.0, eps, 0.0), time) - map(p - vec3<f32>(0.0, eps, 0.0), time),
        map(p + vec3<f32>(0.0, 0.0, eps), time) - map(p - vec3<f32>(0.0, 0.0, eps), time)
    ));
}

// ═══ CHUNK: Fresnel (from glass_refraction_alpha.wgsl) ═══
fn fresnel(cosTheta: f32, eta: f32) -> f32 {
    let c = abs(cosTheta);
    let g = sqrt(eta * eta - 1.0 + c * c);
    let gmc = g - c;
    let gpc = g + c;
    let a = (gmc / gpc) * (gmc / gpc);
    let b = (c * gpc - 1.0) / (c * gmc + 1.0);
    return 0.5 * a * (1.0 + b * b);
}

fn refractRay(I: vec3<f32>, N: vec3<f32>, eta: f32) -> vec3<f32> {
    let NdotI = dot(N, I);
    let k = 1.0 - eta * eta * (1.0 - NdotI * NdotI);
    if (k < 0.0) {
        return vec3<f32>(0.0);
    }
    return eta * I - (eta * NdotI + sqrt(k)) * N;
}

// ═══ CHUNK: Cauchy IOR (from spec-prismatic-dispersion.wgsl) ═══
fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

// ═══ CHUNK: CIE 1931 wavelength-to-RGB (from spec-prismatic-dispersion.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn calculateAdvancedAlpha(color: vec3<f32>, baseAlpha: f32, enterT: f32, normal: vec3<f32>, hit: bool) -> f32 {
    let transparency = 0.3 + u.zoom_params.x * 0.5;
    let thicknessScale = 0.5 + u.zoom_params.z;
    let roughness = u.zoom_params.w * 0.1;
    if (!hit) {
        return 0.0;
    }
    let absorptionCoeff = vec3<f32>(0.12, 0.06, 0.18);
    let opticalDepth = thicknessScale * enterT * 0.5;
    let absorption = exp(-absorptionCoeff * opticalDepth);
    let viewDotNormal = abs(normal.z);
    let F0 = pow((1.5 - 1.0) / (1.5 + 1.0), 2.0);
    let fresnel = F0 + (1.0 - F0) * pow(1.0 - viewDotNormal, 5.0);
    let density = (1.0 - transparency) * thicknessScale;
    let volumetricAlpha = 1.0 - exp(-density * opticalDepth * 3.0);
    let transmittanceAlpha = baseAlpha * dot(absorption, vec3<f32>(0.333)) * (1.0 - fresnel * 0.5);
    let alpha = mix(transmittanceAlpha, volumetricAlpha, 0.5) + roughness * 0.1;
    return clamp(alpha, 0.0, 0.98);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let transparency = 0.3 + u.zoom_params.x * 0.5;
    let cauchyB = mix(0.01, 0.08, u.zoom_params.y);
    let thicknessScale = 0.5 + u.zoom_params.z;
    let roughness = u.zoom_params.w * 0.1;

    let mousePos = (u.zoom_config.yz - 0.5) * 2.0;
    let audioPulse = u.zoom_config.w;
    let isMouseDown = audioPulse > 0.5;
    let mouseUV = u.zoom_config.yz;
    let distToMouse = length(uv - mouseUV);
    let mouseGravity = 1.0 - smoothstep(0.0, 0.35, distToMouse);
    let clickRipple = sin(distToMouse * 40.0 - time * 8.0) * exp(-distToMouse * 4.0) * select(0.0, 1.0, isMouseDown);

    let ro = vec3<f32>(mousePos.x * 0.5, mousePos.y * 0.5, -1.5);
    let rd = normalize(vec3<f32>(uv.x - 0.5, uv.y - 0.5, 1.0));

    var t = 0.0;
    var hit = false;
    var enterT = 0.0;
    var normal = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 64; i = i + 1) {
        let p = ro + rd * t;
        let d = map(p, time);
        if (!hit && d < 0.001) {
            hit = true;
            enterT = t;
            normal = calcNormal(p, time);
            break;
        }
        t += max(d * 0.5, 0.001);
        if (t > 3.0) { break; }
    }

    var bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    var finalRGB = bgColor;
    var finalAlpha = 0.0;

    if (hit) {
        let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
        var spectralColor = vec3<f32>(0.0);

        let viewDotNormal = dot(-rd, normal);
        let baseEta = 1.0 / (1.5 + audioPulse * 0.1);

        for (var w: i32 = 0; w < 4; w = w + 1) {
            let ior = cauchyIOR(WAVELENGTHS[w], 1.5, cauchyB);
            let eta = 1.0 / ior;
            let refracted = refractRay(rd, normal, eta);
            let refractUV = refracted.xy * 0.3 + uv;
            let sampleColor = textureSampleLevel(readTexture, u_sampler, fract(refractUV), 0.0).rgb;
            let absorption = exp(-thicknessScale * (4.0 - f32(w)) * 0.15);
            let bandIntensity = dot(sampleColor, wavelengthToRGB(WAVELENGTHS[w])) * absorption;
            spectralColor += wavelengthToRGB(WAVELENGTHS[w]) * bandIntensity;
        }

        let fresnelFactor = fresnel(viewDotNormal, baseEta);
        let glassTint = vec3<f32>(0.95, 0.98, 1.0);
        let absorption = exp(-vec3<f32>(0.1, 0.05, 0.15) * thicknessScale);
        finalRGB = mix(spectralColor * absorption * glassTint, bgColor, fresnelFactor * 0.3);

        let lightDir = normalize(vec3<f32>(0.5, 1.0, 0.5));
        let halfDir = normalize(lightDir - rd);
        let specAngle = max(dot(normal, halfDir), 0.0);
        let specular = pow(specAngle, 128.0) * (1.0 - roughness) * (1.0 + mouseGravity * 2.0);
        finalRGB += vec3<f32>(1.0) * specular;

        finalAlpha = (1.0 - transparency) + fresnelFactor * transparency;
        finalAlpha = clamp(finalAlpha * 0.8, 0.0, 0.95);
    } else {
        finalAlpha = 0.0;
    }

    var edgeGlow = smoothstep(0.02, 0.0, map(ro + rd * enterT, time)) * audioPulse;
    edgeGlow = edgeGlow + mouseGravity * 0.3;
    finalRGB += vec3<f32>(0.8, 0.9, 1.0) * edgeGlow * 0.5;
    finalAlpha = max(finalAlpha, edgeGlow * 0.5);

    finalRGB = finalRGB / (1.0 + finalRGB * 0.3);
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    let alpha = calculateAdvancedAlpha(finalRGB, finalAlpha, enterT, normal, hit);

    textureStore(writeTexture, coord, vec4<f32>(finalRGB * vignette, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(alpha, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(normal * 0.5 + 0.5, alpha));
}
