// ═══════════════════════════════════════════════════════════════════
//  Quantum Prism
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, hex-prism, upgraded-rgba,
//            hex-grout, held-drag, bounded-click-ripples
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

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let pixel = vec2<i32>(gid.xy);
    if (gid.x >= u32(u.config.z) || gid.y >= u32(u.config.w)) { return; }

    let dims = u.config.zw;
    let uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / max(dims.y, 1.0);
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let held = f32(u.zoom_config.w > 0.5);
    let prev = textureLoad(dataTextureC, pixel, 0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scaleP = u.zoom_params.z;
    let detail = u.zoom_params.w;
    let scale = mix(8.0, 24.0, scaleP);
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let s = vec2<f32>(1.7320508, 1.0);
    let u_scaled = uv_aspect * scale;
    let ga = (fract(u_scaled / s) - 0.5) * s;
    let ida = floor(u_scaled / s);
    let u_off = u_scaled - s * 0.5;
    let gb = (fract(u_off / s) - 0.5) * s;
    let idb = floor(u_off / s);
    let pickB = f32(dot(gb, gb) < dot(ga, ga));
    let localUV = mix(ga, gb, pickB);
    let cellID = mix(ida, idb + 0.5, pickB);
    let center = mix((ida + 0.5) * s, (idb + 0.5) * s + s * 0.5, pickB);
    let centerUV = vec2<f32>(center.x / scale / aspect, center.y / scale);

    let mouseVec = (mouse - centerUV) * vec2<f32>(aspect, 1.0);
    let dist = length(mouseVec);
    let influence = smoothstep(0.45, 0.0, dist) * (0.55 + intensity * 0.7 + held * 0.25);
    let rotAngle = influence * 3.14159 + time * (speed - 0.5) * 1.6;
    let zoom = 1.0 - influence * 0.5;
    let rotatedLocal = rotate(localUV, rotAngle);
    let finalUV_scaled = center + rotatedLocal * zoom;
    let finalUV = clamp(vec2<f32>(finalUV_scaled.x / scale / aspect, finalUV_scaled.y / scale), vec2<f32>(0.0), vec2<f32>(1.0));

    let ca = influence * mix(0.008, 0.03, detail);
    let rOffset = rotate(vec2<f32>(ca, 0.0), rotAngle);
    let bOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 2.094);
    let gOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 4.188);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + gOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var color = vec3<f32>(r, g, b);

    let hexEdge = max(abs(localUV.x), abs(localUV.x) * 0.5 + abs(localUV.y) * 0.866);
    let grout = smoothstep(0.46, 0.5, hexEdge);
    let runners = smoothstep(0.09, 0.0, abs(fract(hexEdge * 6.0 - time * (1.9 + bass * 2.0)) - 0.5));
    let packets = smoothstep(0.08, 0.0, abs(fract(dot(cellID, vec2<f32>(0.17, 0.31)) + time * (0.7 + speed)) - 0.5));
    var click = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.4) {
            click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.48) * 64.0) * (1.0 - age / 1.4));
        }
    }

    let hue = fract(dot(cellID, vec2<f32>(0.07, 0.13)) + time * 0.1 + mids * 0.2);
    let slick = hsv2rgb(vec3<f32>(hue, 0.72 + treble * 0.2, 0.95));
    color = mix(color, vec3<f32>(0.0), grout * influence);
    color = mix(color, color * slick * 1.3, 0.28 + treble * 0.2);
    color += slick * (runners * 0.28 + packets * 0.22 + click * 0.55 + influence * 0.12);

    let srcA = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).a;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(mix(srcA, 0.3 + luma * 0.7, 0.65) + click * 0.1, 0.0, 1.0);
    let outCol = vec4<f32>(mix(color, prev.rgb * 0.87, 0.24), mix(alpha, prev.a * 0.87, 0.24));
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + grout * 0.08 + click * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
