// ═══════════════════════════════════════════════════════════════════
//  Halftone Reveal v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Chunks From: halftone-reveal
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

fn rotate2d(v: vec2<f32>, a: f32) -> vec2<f32> {
    let s = sin(a);
    let c = cos(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn rgbToCmyk(rgb: vec3<f32>) -> vec4<f32> {
    let k = 1.0 - max(max(rgb.r, rgb.g), rgb.b);
    let c = (1.0 - rgb.r - k) / (1.0 - k + 0.001);
    let m = (1.0 - rgb.g - k) / (1.0 - k + 0.001);
    let y = (1.0 - rgb.b - k) / (1.0 - k + 0.001);
    return vec4<f32>(c, m, y, k);
}

fn cmykToRgb(cmyk: vec4<f32>) -> vec3<f32> {
    return vec3<f32>(
        (1.0 - cmyk.x) * (1.0 - cmyk.w),
        (1.0 - cmyk.y) * (1.0 - cmyk.w),
        (1.0 - cmyk.z) * (1.0 - cmyk.w)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let aspect = resolution.x / resolution.y;
    let dotSizeBase = mix(8.0, 140.0, u.zoom_params.x);
    let baseAngle = u.zoom_params.y * 3.14159265;
    let revealSize = u.zoom_params.z * 0.5 + 0.05;
    let magnify = mix(1.0, 3.5, u.zoom_params.w);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let revealProgress = revealSize + bass * 0.06;
    let mouseDist = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    let revealMask = 1.0 - smoothstep(revealProgress, revealProgress + 0.1, mouseDist);

    let loupe = smoothstep(0.12, 0.0, mouseDist);
    let effectiveDotSize = dotSizeBase * mix(1.0, 0.35, loupe);

    let zoomedUV = clamp((uv - mouse) / magnify + mouse, vec2<f32>(0.001), vec2<f32>(0.999));
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, zoomedUV, 0.0).r, 0.0, 1.0);
    let depthDotSize = effectiveDotSize * mix(1.2, 0.6, depth);

    let baseColor = textureSampleLevel(readTexture, u_sampler, mix(uv, zoomedUV, revealMask), 0.0).rgb;
    let lum = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));

    let cmyk = rgbToCmyk(baseColor);
    let angles = vec4<f32>(baseAngle, baseAngle + 0.5236, baseAngle - 0.5236, baseAngle + 1.5708);
    let gridPos = (uv - mouse) * depthDotSize;

    let stippleScale = mix(1.4, 0.6, lum);

    let cGrid = rotate2d(gridPos * stippleScale, angles.x);
    let mGrid = rotate2d(gridPos * stippleScale, angles.y);
    let yGrid = rotate2d(gridPos * stippleScale, angles.z);
    let kGrid = rotate2d(gridPos * stippleScale, angles.w);

    let cDot = 1.0 - smoothstep(0.2, 0.55, length(fract(cGrid) - 0.5)) * cmyk.x;
    let mDot = 1.0 - smoothstep(0.2, 0.55, length(fract(mGrid) - 0.5)) * cmyk.y;
    let yDot = 1.0 - smoothstep(0.2, 0.55, length(fract(yGrid) - 0.5)) * cmyk.z;
    let kDot = 1.0 - smoothstep(0.2, 0.55, length(fract(kGrid) - 0.5)) * cmyk.w;

    let dotGain = 0.88 + mids * 0.08;
    let overlap = max(0.0, cDot + mDot - 1.0) * 0.08;
    let screened = vec4<f32>(
        clamp(1.0 - (1.0 - cDot) * dotGain, 0.0, 1.0),
        clamp(1.0 - (1.0 - mDot) * dotGain, 0.0, 1.0),
        clamp(1.0 - (1.0 - yDot) * dotGain, 0.0, 1.0),
        clamp(1.0 - (1.0 - kDot) * dotGain, 0.0, 1.0)
    );
    let halftone = cmykToRgb(screened) + vec3<f32>(overlap);

    let paper = vec3<f32>(1.0, 0.98, 0.94) * (0.06 + hash2(uv * 600.0) * 0.03);

    let finalColor = acesToneMap(baseColor * (1.0 - revealMask * 0.5) + halftone * revealMask + paper);

    let dotDensity = (cmyk.x + cmyk.y + cmyk.z + cmyk.w) * 0.25;
    let alpha = clamp(revealMask * 0.35 + dotDensity * 0.3 + depth * 0.2 + bass * 0.05, 0.1, 0.92);
    let outDepth = clamp(depth + revealMask * 0.06, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(revealMask, dotDensity, depth, alpha));
}
