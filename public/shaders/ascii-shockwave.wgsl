// ═══════════════════════════════════════════════════════════════════
//  ASCII Shockwave
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware,
//            glyph-cells, held-drag, bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-08-23, 2026-11-15
//  Ideas: mid-ramp bar; cell-average luma
//  A packing: linear display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;
    let held = f32(u.zoom_config.w > 0.5);
    let mouse = u.zoom_config.yz;
    let prev = textureLoad(dataTextureC, pixel, 0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let detail = u.zoom_params.w;

    let uvA = vec2<f32>(uv.x * aspect, uv.y);
    let mouseA = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvA, mouseA);
    let waveSpeed = mix(4.0, 14.0, speed) * (1.0 + bass * 0.4);
    let pulse = sin(dist * mix(10.0, 28.0, scale) - time * waveSpeed);
    let asciiAmt = smoothstep(0.15, 0.72, pulse) * (0.45 + intensity * 0.7 + held * 0.2);

    let cells = mix(36.0, 110.0, scale) * (1.0 + treble * 0.15);
    let local = fract(uv * cells);
    let grid = floor(uv * cells) / cells;
    let centerUV = clamp(grid + 0.5 / cells, vec2<f32>(0.0), vec2<f32>(1.0));
    let src = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);

    // ── Idea 2: cell-average luma ───────────────────────────────────
    // The glyph follows the cell, not a single center pixel.
    // Color still comes from the center sample.
    let half = 0.22 / max(cells, 1.0);
    let l0 = textureSampleLevel(readTexture, u_sampler, clamp(centerUV + vec2<f32>( half,  half), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let l1 = textureSampleLevel(readTexture, u_sampler, clamp(centerUV + vec2<f32>(-half,  half), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let l2 = textureSampleLevel(readTexture, u_sampler, clamp(centerUV + vec2<f32>(-half, -half), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let l3 = textureSampleLevel(readTexture, u_sampler, clamp(centerUV + vec2<f32>( half, -half), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let lum = dot((src.rgb + l0 + l1 + l2 + l3) * 0.2, vec3<f32>(0.299, 0.587, 0.114));

    let box = 1.0 - smoothstep(0.08, 0.16, min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y)));
    let cross = 1.0 - smoothstep(0.04, 0.11, min(abs(local.x - local.y), abs(local.x - (1.0 - local.y))));
    let dotm = 1.0 - smoothstep(0.12 + detail * 0.12, 0.28, distance(local, vec2<f32>(0.5)));
    let fill = smoothstep(0.55, 0.92, lum);

    // ── Idea 1: mid-ramp bar ────────────────────────────────────────
    // A horizontal stroke sits between the cross and the box.
    let bar = 1.0 - smoothstep(0.07, 0.14, abs(local.y - 0.5));
    let mid = mix(cross, max(cross, bar), 0.7);
    let glyph = mix(mix(dotm, mid, smoothstep(0.18, 0.55, lum)), mix(box, fill, fill), smoothstep(0.45, 0.82, lum));

    let conveyor = smoothstep(0.1, 0.0, abs(fract(grid.x * cells * 0.08 - time * (1.8 + speed * 2.4)) - 0.5));
    let packets = smoothstep(0.09, 0.0, abs(fract(dist * mix(6.0, 16.0, scale) - time * (2.2 + bass * 2.0)) - 0.5));

    var click = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.4) {
            click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.52) * 70.0) * (1.0 - age / 1.4));
        }
    }

    let hue = fract(lum * 1.4 + time * 0.11 + mids * 0.25 + dist * 0.35);
    let slick = hsv2rgb(vec3<f32>(hue, 0.78, 0.95));
    let plain = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var color = mix(plain.rgb, src.rgb * glyph * slick * 1.25, asciiAmt);
    color += slick * (conveyor * 0.22 + packets * 0.28 + click * 0.55) * (0.35 + intensity);
    color *= 1.0 + bass * 0.12 + held * 0.1 + click * 0.25;

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.28 + luma * 0.62 + asciiAmt * 0.18 + click * 0.2, 0.0, 1.0);
    let linearRgb = max(mix(color, prev.rgb * 0.86, 0.28), vec3<f32>(0.0));
    let linearA = clamp(mix(alpha, prev.a * 0.86, 0.28), 0.0, 1.0);
    let shown = vec4<f32>(aces(linearRgb), linearA);
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let outDepth = clamp(depth + glyph * asciiAmt * 0.08 + click * 0.06, 0.0, 1.0);

    textureStore(writeTexture, pixel, shown);
    textureStore(dataTextureA, pixel, vec4<f32>(linearRgb, linearA));
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
