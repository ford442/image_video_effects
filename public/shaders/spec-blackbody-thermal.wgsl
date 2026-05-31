// ═══════════════════════════════════════════════════════════════════
//  Blackbody Thermal
//  Category: advanced-hybrid
//  Features: blackbody-radiation, HDR, physical-color, audio-reactive,
//            temporal-ember-persistence, chromatic-temperature-gradient, depth-output
//  Complexity: High
//  Upgraded: 2026-05-31
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

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.x);
    let tempRangeHigh = mix(4000.0, 15000.0, u.zoom_params.y);
    let thermalIntensity = mix(0.5, 3.0, u.zoom_params.z) * (1.0 + bass * 0.3);
    let glowAmount = mix(0.0, 0.8, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));

    // Audio-driven temperature modulation
    var temperature = mix(tempRangeLow, tempRangeHigh, luma);
    temperature = temperature * (1.0 + mids * 0.2 * sin(time * 3.0));

    if (isMouseDown) {
        let mouseDist = length(uv - mousePos);
        let mouseHeat = exp(-mouseDist * mouseDist * 400.0);
        temperature += mouseHeat * tempRangeHigh * 0.5 * (1.0 + treble * 0.3);
    }

    var thermalColor = blackbodyColor(temperature) * thermalIntensity;

    // Chromatic temperature gradient: cooler = more blue, hotter = more red
    let tempNorm = clamp((temperature - tempRangeLow) / (tempRangeHigh - tempRangeLow), 0.0, 1.0);
    let chromaR = thermalColor * vec3<f32>(1.1, 0.95, 0.85) * (1.0 + treble * 0.15);
    let chromaB = thermalColor * vec3<f32>(0.85, 0.95, 1.1) * (1.0 + bass * 0.15);
    thermalColor = mix(chromaB, chromaR, tempNorm);

    // Temporal ember persistence via dataTextureC
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prevEmber = prev.rgb * prev.a * 15000.0;
    let emberDecay = mix(0.85, 0.98, glowAmount);
    let persistentEmber = blackbodyColor(prevEmber * emberDecay) * thermalIntensity * glowAmount;
    thermalColor = max(thermalColor, persistentEmber);

    // Glow around bright regions with audio reactivity
    if (glowAmount > 0.01) {
        let glowRadius = 0.03;
        var glowAccum = vec3<f32>(0.0);
        let glowSamples = 16;
        for (var i: i32 = 0; i < glowSamples; i = i + 1) {
            let angle = f32(i) * 0.392699 + time * 0.3;
            let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
            let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            let sLuma = dot(s, vec3<f32>(0.299, 0.587, 0.114));
            let sTemp = mix(tempRangeLow, tempRangeHigh, sLuma);
            glowAccum += blackbodyColor(sTemp) * thermalIntensity;
        }
        glowAccum /= f32(glowSamples);
        thermalColor = mix(thermalColor, glowAccum, glowAmount * 0.4 * (1.0 + bass * 0.2));
    }

    let displayColor = toneMapACES(thermalColor);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = clamp(temperature / 15000.0 * (1.0 + bass * 0.1), 0.0, 1.0);

    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, gid.xy, vec4<f32>(displayColor, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(thermalColor, alpha));
}
