// ═══════════════════════════════════════════════════════════════════
//  Crystalline Mandala Bloom
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, aces-tone-map
//  Complexity: Medium
//  Upgraded: 2026-06-06
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

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Polar kaleidoscope fold
fn kaleido(p: vec2<f32>, segments: f32) -> vec2<f32> {
    let segAngle = 6.28318530718 / max(segments, 1.0);
    var a = atan2(p.y, p.x);
    let r = length(p);
    a = abs(a - segAngle * floor(a / segAngle + 0.5));
    return vec2<f32>(cos(a), sin(a)) * r;
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params: x=symmetry segments, y=facet zoom, z=bloom strength, w=hue rotation
    let segments = floor(4.0 + u.zoom_params.x * 16.0);
    let facetZoom = 1.0 + u.zoom_params.y * 4.5;
    let bloomStrength = 0.5 + u.zoom_params.z * 2.5;
    let hueRot = u.zoom_params.w * 6.28318530718;

    // Mouse moves the mandala center
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let aspect = resolution.x / max(resolution.y, 1.0);
    var p = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y);

    // Audio-modulated rotation and scale (technique 1: rotating polar fold)
    let spinRate = 0.2 + mids * 0.5;
    p = rotate(time * spinRate + bass * 1.2) * p;
    p = p * facetZoom * (1.0 + bass * 0.25);

    // Kaleidoscopic symmetry
    let k = kaleido(p, segments);

    // Sample original image through the folded coordinate (technique 2: image-into-mandala)
    let sampleUV = clamp(k * 0.5 + vec2<f32>(0.5), vec2<f32>(0.0), vec2<f32>(1.0));
    let folded = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Radial crystalline facets (technique 3: SDF petals)
    let r = length(k);
    let a = atan2(k.y, k.x);
    let petalCount = floor(segments * 0.5 + 3.0);
    let petalPhase = cos(a * petalCount + time * (0.6 + mids * 0.8));
    let petalRadius = 0.35 + 0.18 * petalPhase + treble * 0.04;
    let petalSDF = smoothstep(petalRadius + 0.02, petalRadius - 0.02, r);

    // Concentric rings pulsing with bass
    let ringPhase = sin(r * 18.0 - time * 2.5 * (1.0 + bass * 0.5));
    let ring = smoothstep(0.85, 1.0, abs(ringPhase));

    // Hue-rotation matrix applied to folded color
    let cosH = cos(hueRot + time * 0.15);
    let sinH = sin(hueRot + time * 0.15);
    let lum = dot(folded.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let chroma = folded.rgb - vec3<f32>(lum);
    let rotChroma = vec3<f32>(
        chroma.r * cosH + chroma.g * (-sinH) + chroma.b * sinH,
        chroma.r * sinH + chroma.g * cosH + chroma.b * (-sinH),
        chroma.r * (-sinH) + chroma.g * sinH + chroma.b * cosH
    );
    let foldedTinted = vec3<f32>(lum) + rotChroma;

    // Crystalline highlight color
    let crystalCold = vec3<f32>(0.6, 0.9, 1.2);
    let crystalWarm = vec3<f32>(1.1, 0.55, 0.85);
    let crystalColor = mix(crystalCold, crystalWarm, 0.5 + 0.5 * sin(time * 0.4 + r * 4.0));

    // Bloom around petals (audio-modulated)
    let bloom = exp(-r * 2.5) * bloomStrength * (1.0 + treble * 0.6);

    // Composite
    var rgb = foldedTinted * (0.45 + petalSDF * 0.9);
    rgb += crystalColor * petalSDF * 0.6;
    rgb += crystalColor * ring * 0.35 * (1.0 + mids * 0.5);
    rgb += vec3<f32>(0.35, 0.5, 0.75) * bloom;

    // Sparkle stars
    let starSeed = hash21(floor(k * 60.0));
    let star = step(0.992, starSeed) * (0.6 + treble * 1.2);
    rgb += vec3<f32>(star);

    let finalRGB = clamp(rgb, vec3<f32>(0.0), vec3<f32>(4.0));

    // Meaningful alpha: petal mask + bloom + ring + base
    let alpha = clamp(folded.a * 0.2 + petalSDF * 0.6 + ring * 0.3 + bloom * 0.25 + bass * 0.1, 0.0, 1.0);

    // Depth: petals are near, surround is far
    let depth = clamp(1.0 - petalSDF * 0.6 - bloom * 0.2, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(acesToneMap((finalRGB) * 1.1), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
}
