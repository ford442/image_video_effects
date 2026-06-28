// ═══════════════════════════════════════════════════════════════════
//  Chroma Depth Tunnel
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52, 0.50, 0.50) +
           vec3<f32>(0.48, 0.45, 0.42) *
           cos(6.28318 * (vec3<f32>(1.0, 0.68, 0.44) * t + vec3<f32>(0.00, 0.26, 0.57)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) {
        return;
    }

    let resolution = u.config.zw;
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var mousePos = u.zoom_config.yz;
    mousePos = select(mousePos, vec2<f32>(0.5, 0.5), mousePos.x < 0.0);

    let speed = (u.zoom_params.x - 0.5) * 2.0;
    let density = u.zoom_params.y * 5.0 + 1.0;
    let chroma = u.zoom_params.z * 0.05 * (1.0 + bass * 0.3 + mids * 0.15);
    let centerFade = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    let p = uv - mousePos;
    let p_aspect = vec2<f32>(p.x * aspect, p.y);

    let radius = length(p_aspect);
    let angle = atan2(p.y, p.x);

    let u_coord = angle / 3.14159265;
    let v_coord = 1.0 / (radius + 0.001);
    let tunnelUV = vec2<f32>(u_coord, v_coord * density + time * speed);

    let r_uv = clamp(tunnelUV + vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let g_uv = tunnelUV;
    let b_uv = clamp(tunnelUV - vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r_col = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g_col = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
    let b_col = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    var color = vec3<f32>(r_col, g_col, b_col);

    // Branchless center fade: mix with 1.0 fog when centerFade is near zero
    let fog = mix(1.0, smoothstep(0.0, centerFade, radius), step(0.001, centerFade));
    color = color * fog;

    // Cinematic tunnel grade: glowing ribs, spectral core, and audio-hot sparks.
    let rings = 0.5 + 0.5 * sin(v_coord * density * 0.42 + time * (1.4 + bass));
    let rib = pow(smoothstep(0.72, 1.0, rings), 3.0);
    let swirl = 0.5 + 0.5 * sin(angle * 6.0 + v_coord * 0.08 - time * 1.8);
    let spectral = palette(v_coord * 0.035 + angle * 0.12 + time * 0.05 + mids * 0.2);
    var hdr = color * (0.78 + fog * 0.32);
    hdr = hdr + spectral * rib * fog * (1.15 + bass * 1.4);
    hdr = hdr + vec3<f32>(0.25, 0.55, 1.0) * pow(swirl, 5.0) * fog * treble * 0.75;
    hdr = hdr + vec3<f32>(1.0, 0.82, 0.45) * pow(max(0.0, 1.0 - radius * 2.3), 4.0) * (0.35 + mids);

    // Alpha encodes tunnel depth: inner rings (high v_coord) are more opaque
    let tunnel_depth = clamp(v_coord * 0.02, 0.0, 1.0);
    let radial = length(uv - vec2<f32>(0.5)) * 1.414;
    hdr = hdr * mix(1.08, 0.62, smoothstep(0.48, 1.0, radial));
    let dither = (ign(vec2<f32>(global_id.xy) + time * 31.0) - 0.5) / 255.0;
    let mapped = clamp(aces(hdr * 1.18) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));
    let luma = dot(hdr, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(fog * (0.12 + tunnel_depth * 0.28 + pow(max(0.0, luma - 0.5), 2.0) * 2.8), 0.0, 1.0);

    let finalColor = vec4<f32>(mapped * alpha, alpha);

    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(d, 0.0, 0.0, 0.0));
}
