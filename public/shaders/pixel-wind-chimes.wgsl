// ═══════════════════════════════════════════════════════════════════
//  Pixel Wind Chimes
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: hinge specular; closest-Z strip sort
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

fn rotate(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = (vec2<f32>(pixel) + 0.5) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    let strip_count = mix(10.0, 80.0, u.zoom_params.x);
    let sway_amp = u.zoom_params.y * 1.5 * (1.0 + bass * 0.35);
    let wind_speed = mix(0.5, 5.0, u.zoom_params.z);
    let gap_size = u.zoom_params.w * 0.5;

    let strip_width = 1.0 / strip_count;
    let base_idx = floor(uv.x * strip_count);
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

    var final_color = vec3<f32>(0.05, 0.05, 0.05);
    var srcA = 1.0;
    var found_hit = false;
    var best_z = -1000.0;
    var hinge_amt = 0.0;
    var shade_keep = 0.2;

    for (var i = -2; i <= 2; i = i + 1) {
        let idx = base_idx + f32(i);
        if (idx < 0.0 || idx >= strip_count) { continue; }

        let center_x = (idx + 0.5) * strip_width;
        let dist_x = center_x - mouse.x;
        let push = exp(-pow(dist_x * 5.0, 2.0));
        let dir = sign(dist_x + 0.001);
        let mouse_angle = dir * push * sway_amp;
        let ambient_angle = sin(time * wind_speed + idx * 0.5) * 0.1 * sway_amp;
        let total_angle = ambient_angle + mouse_angle;

        let rel_pos = uv - vec2<f32>(center_x, 0.0);
        let local_pos = rotate(rel_pos, -total_angle);
        let half_w = (strip_width * 0.5) * (1.0 - gap_size);

        if (abs(local_pos.x) < half_w && local_pos.y >= 0.0 && local_pos.y <= 1.0) {
            // Idea 2 — closest-Z: swing into screen is nearer
            let z = local_pos.x * sin(total_angle);
            if (z >= best_z) {
                best_z = z;
                let src_uv = clamp(vec2<f32>(center_x + local_pos.x, local_pos.y), vec2<f32>(0.0), vec2<f32>(1.0));
                let col = textureSampleLevel(readTexture, u_sampler, src_uv, 0.0);
                let shade = cos(total_angle * 2.0) * 0.8 + 0.2;
                final_color = col.rgb * shade;
                srcA = col.a;
                shade_keep = shade;
                found_hit = true;
                // Idea 1 — hinge specular at the top pivot
                hinge_amt = exp(-local_pos.y * 28.0) * (0.45 + treble * 0.4);
            }
        }
    }

    var hdr = final_color;
    if (found_hit) {
        hdr = hdr + vec3<f32>(0.95, 0.92, 0.82) * hinge_amt * shade_keep;
    }
    let mapped = aces(hdr);
    let gapDark = select(0.0, 1.0, found_hit);
    let alpha = clamp(srcA * 0.35 + gapDark * 0.45 + hinge_amt * 0.4, 0.0, 1.0);
    let outCol = vec4<f32>(mapped, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let outDepth = mix(depth, clamp(0.35 + best_z * 0.4, 0.0, 1.0), f32(found_hit) * 0.35);

    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
