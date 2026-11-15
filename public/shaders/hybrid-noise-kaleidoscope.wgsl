// ═══════════════════════════════════════════════════════════════════
//  Hybrid Noise Kaleidoscope
//  Category: generative
//  Features: hybrid, fbm-noise, kaleidoscope, chromatic-aberration, hue-shift, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: second domain warp; chromatic domain split; mirror joint
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {
    let angle = atan2(uv.y, uv.x);
    let radius = length(uv);
    let segmentAngle = 6.2831853 / max(segments, 1.0);
    let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
    return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let noiseScale = mix(1.0, 8.0, u.zoom_params.x) * (1.0 + bass * 0.3);
    let segments = mix(3.0, 16.0, u.zoom_params.y) * (1.0 + mids * 0.25);
    let chromaticStrength = u.zoom_params.z * 0.05 * (1.0 + treble * 0.8);
    let hueSpeed = mix(0.1, 1.0, u.zoom_params.w);

    let centered = (uv - 0.5) * 2.0;
    let aspect = resolution.x / max(resolution.y, 0.001);
    var p = centered;
    p.x = p.x * aspect;

    let noiseVal = fbm2(p * noiseScale + time * 0.2, 5);
    let noiseDisplacement = vec2<f32>(
        fbm2(p * noiseScale + vec2<f32>(5.2, 1.3), 4),
        fbm2(p * noiseScale + vec2<f32>(1.7, 9.2), 4)
    ) * 0.3;
    let warpedP = p + noiseDisplacement;

    // ── Idea 1: second domain warp — noise of the already-warped coordinate
    let warp2 = vec2<f32>(
        fbm2(warpedP * 1.7 + vec2<f32>(3.1, 8.4), 3),
        fbm2(warpedP * 1.7 + vec2<f32>(8.9, 2.2), 3)
    ) - 0.5;
    let domain = warpedP + warp2 * 0.28;

    let kaled = kaleidoscope(domain, segments);

    // ── Idea 2: chromatic domain split — the old unused RGB offsets now move the fbm
    let split = chromaticStrength * 18.0;
    let pR = fbm2((domain + vec2<f32>(split, 0.0)) * 2.0, 4);
    let pG = fbm2(domain * 2.0, 4);
    let pB = fbm2((domain - vec2<f32>(split, 0.0)) * 2.0, 4);
    var color = vec3<f32>(pR, pG * 0.8, pB * 0.6);

    let angle = atan2(kaled.y, kaled.x);
    color.r = color.r + sin(angle * segments) * chromaticStrength * 5.0;
    color.b = color.b + cos(angle * segments) * chromaticStrength * 5.0;

    color = hueShift(color, time * hueSpeed + noiseVal * 0.5);

    // ── Idea 3: mirror joint — dark where the fold sits on a segment boundary
    let segmentAngle = 6.2831853 / max(segments, 1.0);
    let foldAngle = atan2(domain.y, domain.x);
    let seamFrac = abs(fract(foldAngle / segmentAngle + 0.5) - 0.5);
    let seam = smoothstep(0.045, 0.0, seamFrac);
    color = color * (1.0 - seam * 0.62);

    let vignette = clamp(1.0 - length(centered) * 0.3, 0.0, 1.0);
    color = color * vignette;

    let display = aces(max(color, vec3<f32>(0.0)));
    let luma = dot(display, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.55, 1.0, luma);
    let outColor = vec4<f32>(display, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(noiseVal, 0.0, 1.0), 0.0, 0.0, 0.0));
}
