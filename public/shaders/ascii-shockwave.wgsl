// ═══════════════════════════════════════════════════════════════════
//  ASCII Shockwave
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, depth-aware,
//            glyph-cells, held-drag, bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-08-23
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

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
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
    let src = textureSampleLevel(readTexture, u_sampler, clamp(grid + 0.5 / cells, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let lum = dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let box = 1.0 - smoothstep(0.08, 0.16, min(min(local.x, 1.0 - local.x), min(local.y, 1.0 - local.y)));
    let cross = 1.0 - smoothstep(0.04, 0.11, min(abs(local.x - local.y), abs(local.x - (1.0 - local.y))));
    let dotm = 1.0 - smoothstep(0.12 + detail * 0.12, 0.28, distance(local, vec2<f32>(0.5)));
    let fill = smoothstep(0.55, 0.92, lum);
    let glyph = mix(mix(dotm, cross, smoothstep(0.18, 0.55, lum)), mix(box, fill, fill), smoothstep(0.45, 0.82, lum));

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
    let trail = vec4<f32>(mix(color, prev.rgb * 0.86, 0.28), mix(alpha, prev.a * 0.86, 0.28));
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let outDepth = clamp(depth + glyph * asciiAmt * 0.08 + click * 0.06, 0.0, 1.0);

    textureStore(writeTexture, pixel, trail);
    textureStore(dataTextureA, pixel, trail);
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
