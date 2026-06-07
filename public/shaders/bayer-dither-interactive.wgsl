// ═══════════════════════════════════════════════════════════════════
//  Bayer Dither Interactive v2
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Chunks From: bayer-dither-interactive
//  Upgraded: 2026-05-30
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn bayer8(pos: vec2<u32>) -> f32 {
    let x = pos.x & 7u;
    let y = pos.y & 7u;
    let idx = y * 8u + x;
    let table = array<f32, 64>(
        0.0, 32.0, 8.0, 40.0, 2.0, 34.0, 10.0, 42.0,
        48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
        12.0, 44.0, 4.0, 36.0, 14.0, 46.0, 6.0, 38.0,
        60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
        3.0, 35.0, 11.0, 43.0, 1.0, 33.0, 9.0, 41.0,
        51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
        15.0, 47.0, 7.0, 39.0, 13.0, 45.0, 5.0, 37.0,
        63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
    );
    return table[idx] / 64.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let aspect = resolution.x / resolution.y;
    let bitDepthParam = u.zoom_params.x;
    let contrast = mix(0.5, 2.5, u.zoom_params.y);
    let spread = u.zoom_params.z;
    let pixelScaleMax = mix(1.0, 20.0, u.zoom_params.w);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let bitModes = array<f32, 3>(1.0, 3.0, 7.0);
    let modeIdx = clamp(i32(bass * 3.0), 0, 2);
    var levels = bitModes[modeIdx];
    levels = mix(levels, max(2.0, floor(bitDepthParam * 15.0) + 1.0), 0.5);

    let mouseDist = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    let influence = smoothstep(0.5, 0.0, mouseDist);

    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, 0.0, 1.0);
    let depthScale = mix(1.15, 0.75, depth);

    let pixelScale = mix(1.0, pixelScaleMax * depthScale * (1.0 + bass * 0.2), influence);
    let pixelUV = clamp(
        (floor(uv * resolution / pixelScale) * pixelScale + 0.5 * pixelScale) / resolution,
        vec2<f32>(0.001), vec2<f32>(0.999)
    );
    let baseColor = textureSampleLevel(readTexture, u_sampler, pixelUV, 0.0).rgb;
    let contrasted = clamp((baseColor - 0.5) * contrast + 0.5, vec3<f32>(0.0), vec3<f32>(1.0));

    let blueNoise = hash2(vec2<f32>(global_id.xy) + fract(u.config.x * 1.618) * 100.0) * 0.08 - 0.04;
    let threshold = (bayer8(vec2<u32>(global_id.xy)) - 0.5 + blueNoise) * spread * (0.4 + treble * 0.6);

    let texel = vec2<f32>(1.0) / resolution;
    let qR = floor((contrasted.r + threshold) * levels) / levels;
    let qG = floor((contrasted.g + threshold) * levels) / levels;
    let qB = floor((contrasted.b + threshold) * levels) / levels;
    let errVec = contrasted - vec3<f32>(qR, qG, qB);

    let neighbor = textureSampleLevel(readTexture, u_sampler, pixelUV + vec2<f32>(texel.x, texel.y), 0.0).rgb;
    let nQ = floor(neighbor * levels) / levels;
    let errDiff = (neighbor - nQ) * 0.25 * influence;
    let dithered = floor((contrasted + threshold + errDiff) * levels) / levels;

    let paletteMix = clamp(bass * 2.5, 0.0, 1.0);
    let retro1bit = step(vec3<f32>(0.5), dithered);
    let retro4bit = floor(dithered * 15.0) / 15.0;
    let retro8bit = floor(dithered * 255.0) / 255.0;
    var retroColor = mix(dithered, retro8bit, paletteMix * 0.3);
    retroColor = mix(retroColor, retro4bit, smoothstep(0.3, 0.7, paletteMix) * 0.4);
    retroColor = mix(retroColor, retro1bit, smoothstep(0.7, 1.0, paletteMix) * 0.5);

    let phosphorPos = fract(uv * resolution / pixelScale);
    let dotMask = step(0.15, phosphorPos.x) * step(0.15, phosphorPos.y);
    let phosphor = retroColor * dotMask * (0.92 + mids * 0.12);

    let edge = length(dithered - floor(dithered * levels) / levels) * levels;
    let caAmt = smoothstep(0.02, 0.0, edge) * 0.08 * influence;
    let caColor = vec3<f32>(
        phosphor.r * (1.0 + caAmt),
        phosphor.g,
        phosphor.b * (1.0 - caAmt * 0.5)
    );

    let scanline = smoothstep(0.85, 0.2, abs(fract(uv.y * resolution.y / pixelScale) - 0.5));
    let halo = vec3<f32>(1.0, 0.15 + treble * 0.15, 0.65) * scanline * influence * 0.1;

    let finalColor = acesToneMap(caColor + halo);

    let ditherConf = 1.0 - length(errDiff) * 2.0;
    let alpha = clamp(influence * 0.35 + scanline * 0.15 + ditherConf * 0.2 + bass * 0.06, 0.1, 0.92);
    let outDepth = clamp(depth + influence * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(influence, scanline, ditherConf, alpha));
}
