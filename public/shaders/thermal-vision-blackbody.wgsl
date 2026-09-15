// ═══════════════════════════════════════════════════════════════════
//  Thermal Vision Blackbody
//  Category: advanced-hybrid
//  Features: blackbody-radiation, thermal-vision, mouse-driven, HDR, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-15
//  Ideas: NUC/scanline banding; hot-object lag stored in C.a
//  A packing: raw thermal RGB + normalized T
// ═══════════════════════════════════════════════════════════════════
//  Physically-correct thermal vision using blackbody radiation.
//  Maps image luminance to temperature via Planck's law, replacing
//  the simple gradient with scientifically-grounded thermal colors.
//  Mouse acts as a local heat source with configurable intensity.
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
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn loadC(coord: vec2<i32>, max_coord: vec2<i32>) -> vec4<f32> {
    let c = clamp(coord, vec2<i32>(0), max_coord);
    return textureLoad(dataTextureC, c, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let coord = vec2<i32>(gid.xy);
    let max_coord = vec2<i32>(res) - vec2<i32>(1);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.x);
    let tempRangeHigh = mix(4000.0, 12000.0, u.zoom_params.y);
    let contrast = mix(0.2, 5.0, u.zoom_params.z);
    let shift = u.zoom_params.w;

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var lum = dot(base.rgb, vec3<f32>(0.299, 0.587, 0.114));

    lum = pow(lum, contrast * (1.0 + bass * 0.12));

    // Idea 1 — NUC / scanline banding (row-correlated sensor noise + calibration bars)
    let row = floor(uv.y * res.y);
    let rowNoise = hash(vec2<f32>(row * 0.17, floor(time * 7.0))) - 0.5;
    lum += rowNoise * 0.045 * (0.55 + treble * 0.45);
    let nucBar = step(0.94, fract(uv.y * 18.0 + time * 0.015));
    lum = mix(lum, lum * 0.82 + 0.04, nucBar * 0.4);

    var temperature = mix(tempRangeLow, tempRangeHigh, clamp(lum, 0.0, 1.0));

    let aspect = res.x / max(res.y, 1.0);
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));
    let heatRadius = 0.25;
    let heatIntensity = select(0.0, 1.5, isMouseDown) * (1.0 + bass * 0.2);
    let mouseHeat = smoothstep(heatRadius, 0.0, dist) * heatIntensity;
    temperature += mouseHeat * tempRangeHigh * 0.3;

    temperature = temperature * (0.8 + shift * 0.4);

    // Idea 2 — hot-object lag from exact C (previous Kelvin in .a)
    let prev = loadC(coord, max_coord);
    let prevT = prev.a * 15000.0;
    let lagT = max(temperature, prevT * 0.94);
    temperature = mix(temperature, lagT, 0.65);
    temperature = clamp(temperature, 800.0, 15000.0);

    var thermalColor = blackbodyColor(temperature);

    let glowRadius = 0.03;
    var glowAccum = vec3<f32>(0.0);
    let glowSamples = 12;
    for (var i: i32 = 0; i < glowSamples; i = i + 1) {
        let angle = f32(i) * 0.523599 + time * 0.3;
        let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
        let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
        let sLuma = dot(s, vec3<f32>(0.299, 0.587, 0.114));
        let sTemp = mix(tempRangeLow, tempRangeHigh, sLuma);
        glowAccum += blackbodyColor(sTemp);
    }
    glowAccum /= f32(glowSamples);
    thermalColor = mix(thermalColor, glowAccum, 0.3);

    let displayColor = toneMapACES(thermalColor);
    let noise = hash(uv + fract(time * 0.1)) * 0.03 - 0.015;
    let finalColor = displayColor + noise;

    let heatAmt = clamp((temperature - tempRangeLow) / max(tempRangeHigh - tempRangeLow, 1.0), 0.0, 1.0);
    let alpha = clamp(0.42 + heatAmt * 0.48 + mouseHeat * 0.12 + mids * 0.04, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(thermalColor, temperature / 15000.0));

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
