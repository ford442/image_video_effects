// ═══════════════════════════════════════════════════════════════════
//  energy-shield-blackbody
//  Category: advanced-hybrid
//  Features: hex-grid, blackbody-thermal, mouse-driven, HDR
//  Complexity: High
//  Chunks From: energy-shield.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-19 — Lighting & Energy Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Hexagonal energy shield with physically-correct blackbody thermal
//  coloring. Shield impacts heat up cells from deep red embers through
//  white-hot to blue plasma, creating a thermal energy barrier effect.
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

// ═══ CHUNK: blackbodyColor (from spec-blackbody-thermal.wgsl) ═══
fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
    let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
    var r: f32;
    var g: f32;
    var b: f32;
    if (t <= 6.5) {
        r = 1.0;
        g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
        b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
    } else {
        r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
        g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
        b = 1.0;
    }
    let radiance = pow(t / 6.5, 4.0);
    return vec3<f32>(r, g, b) * radiance;
}

// ═══ CHUNK: toneMapACES (from spec-blackbody-thermal.wgsl) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

fn hexDist(p: vec2<f32>) -> f32 {
    let p_abs = abs(p);
    return max(p_abs.x, p_abs.x * 0.5 + p_abs.y * 0.866025);
}

fn modulo(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
    return x - y * floor(x / y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    // Params
    let hexScale = 5.0 + u.zoom_params.x * 45.0;
    let rippleSpeed = u.zoom_params.y * 5.0;
    let impactStrength = u.zoom_params.z;
    let decay = u.zoom_params.w;
    let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.x);
    let tempRangeHigh = mix(4000.0, 15000.0, u.zoom_params.y);
    let thermalIntensity = mix(0.5, 3.0, u.zoom_params.z);

    // Hex grid
    let r = vec2<f32>(1.0, 1.73);
    let h = r * 0.5;
    var scaledUV = uv * hexScale;
    scaledUV.x = scaledUV.x * aspect;

    let a = modulo(scaledUV, r) - h;
    let b = modulo(scaledUV - h, r) - h;
    let gv = select(b, a, dot(a, a) < dot(b, b));
    let hexCenter = scaledUV - gv;
    var hexCenterUV = hexCenter / hexScale;
    hexCenterUV.x = hexCenterUV.x / aspect;

    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let distVec = (hexCenterUV - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let wave = sin(dist * 20.0 - time * rippleSpeed);
    let mouseIntensity = smoothstep(0.4, 0.0, dist);
    let activeHex = mouseIntensity + wave * 0.2 * impactStrength;

    // Hex edges
    let hexD = hexDist(gv);
    let edge = smoothstep(0.48, 0.5, hexD);
    let glow = smoothstep(0.4, 0.5, hexD) * activeHex;

    // Distort UV
    let distortAmt = activeHex * 0.05 * impactStrength;
    let distortedUV = uv + (gv / hexScale) * distortAmt;
    let color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;

    // ═══ Blackbody thermal coloring on shield cells ═══
    // Map activation to temperature
    let activationTemp = mix(tempRangeLow, tempRangeHigh, activeHex * impactStrength);
    var thermalColor = blackbodyColor(activationTemp) * thermalIntensity;

    // Ripple heat: older ripples cool down
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(hexCenterUV - ripple.xy);
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let heatBoost = smoothstep(0.3, 0.0, rDist) * exp(-age * 0.8);
            thermalColor += blackbodyColor(tempRangeHigh * 0.8) * heatBoost * thermalIntensity;
        }
    }

    thermalColor = toneMapACES(thermalColor);

    let gridColor = mix(vec3<f32>(0.0, 0.8, 1.0), thermalColor, activeHex);
    var finalColor = mix(color, gridColor, glow * 0.8);
    finalColor = finalColor + gridColor * mouseIntensity * 0.2;

    // Trail persistence
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;
    let activation = mouseIntensity;
    let newTrail = max(prev * decay, activation);
    finalColor = finalColor + vec3<f32>(0.0, 0.5, 1.0) * newTrail * 0.5;
    textureStore(dataTextureA, gid.xy, vec4<f32>(newTrail, 0.0, 0.0, 1.0));

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, 1.0));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
