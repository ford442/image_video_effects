// ═══════════════════════════════════════════════════════════════════
//  Double Exposure HDR
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: overlap-only bloom knee; pivot-locked second plate
//  A packing: ACES display RGBA
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

fn rotate2d(uv: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    var uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(gid.xy);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let zoomParam = u.zoom_params.x;
    let zoom = 0.5 + zoomParam * 2.5;
    let rotParam = u.zoom_params.y;
    let angle = (rotParam - 0.5) * 1.57;
    let opacity = u.zoom_params.z;
    let saturation = u.zoom_params.w;

    var mouse = u.zoom_config.yz;
    let aspect = res.x / max(res.y, 1.0);

    let c1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Idea 2 — pivot-locked second plate (mouse is the sandwich pin).
    var p = uv - mouse;
    p.x *= aspect;
    p = rotate2d(p, angle);
    p = p / zoom;
    p.x /= aspect;
    let uv2 = clamp(p + mouse, vec2<f32>(0.0), vec2<f32>(1.0));
    let c2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0);

    var blended = 1.0 - (1.0 - c1.rgb) * (1.0 - c2.rgb * opacity);
    let gray = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
    blended = mix(vec3<f32>(gray), blended, 0.5 + saturation * 0.5);

    let lum1 = max(c1.r, max(c1.g, c1.b));
    let lum2 = max(c2.r, max(c2.g, c2.b));
    // Idea 1 — overlap-only bloom knee (both plates bright).
    let overlapKnee = smoothstep(0.55, 0.92, min(lum1, lum2)) * opacity;

    let bloomRadius = 0.034 * (1.0 + bass * 0.2);
    let bloomSamples = 12;
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;
    for (var i = 0; i < bloomSamples; i = i + 1) {
        let a = f32(i) * 6.283185307 / f32(bloomSamples);
        let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(a), sin(a)) * radius;
        let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let n2 = textureSampleLevel(readTexture, u_sampler, clamp(uv2 + offset * 0.35, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        let pair = min(max(neighbor.r, max(neighbor.g, neighbor.b)), max(n2.r, max(n2.g, n2.b)));
        let neighborExposure = max(0.0, pair - 0.65);
        let weight = exp(-f32(i % 4) * 0.5);
        bloom += (neighbor + n2) * 0.5 * neighborExposure * weight;
        totalWeight += neighborExposure * weight;
    }
    bloom /= max(totalWeight, 0.001);
    bloom *= 1.5 * overlapKnee * (1.0 + mids * 0.25);

    var hdrColor = blended + bloom;

    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mouse);
    let mouseGlow = smoothstep(0.2, 0.0, mouseDist) * mouseDown * 2.0;
    hdrColor += vec3<f32>(mouseGlow * 0.5, mouseGlow * 0.3, mouseGlow * 0.1);

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        let live = f32(age < 0.5 && rDist < 0.1);
        let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0) * live;
        hdrColor += vec3<f32>(flash * 2.0, flash * 1.5, flash);
    }

    let ldrColor = toneMapACES(hdrColor * 1.25);
    let energy = clamp(overlapKnee + treble * 0.08, 0.0, 1.0);
    let alpha = clamp(c1.a * 0.3 + energy * 0.55 + opacity * 0.2, 0.0, 1.0);
    let outColor = vec4<f32>(ldrColor, alpha);

    textureStore(dataTextureA, coord, outColor);
    textureStore(writeTexture, coord, outColor);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
