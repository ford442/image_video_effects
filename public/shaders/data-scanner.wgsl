// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn get_luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn sobel(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;

    let gx = length(r - l);
    let gy = length(b - t);

    return sqrt(gx*gx + gy*gy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(gid.xy) / resolution;
    let texel = 1.0 / resolution;

    let mouse = u.zoom_config.yz;
    let scan_x = mouse.x;
    let scan_width = 0.15; // Width of the bar

    let dist = abs(uv.x - scan_x);
    let in_scan = smoothstep(scan_width, scan_width - 0.01, dist);

    // Normal color
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    if (in_scan > 0.0) {
        // Analysis Mode
        let edge = sobel(uv, texel);
        let lum = get_luminance(color);

        // Grid
        let grid_uv = fract(uv * 40.0);
        let grid = step(0.95, grid_uv.x) + step(0.95, grid_uv.y);

        // Processed look: Green/Blue tint + Edges
        let scan_color = vec3<f32>(0.0, lum * 0.5, lum * 0.8); // Blue-ish base
        let edge_color = vec3<f32>(0.0, 1.0, 0.8); // Cyan edges
        let grid_color = vec3<f32>(0.0, 0.5, 0.0);

        var analyzed = mix(scan_color, edge_color, edge * 4.0);
        analyzed = max(analyzed, grid_color * grid);

        // Highlight the scan bar edges
        let border_line = smoothstep(scan_width - 0.005, scan_width, dist) * (1.0 - smoothstep(scan_width, scan_width + 0.005, dist));
        analyzed += vec3<f32>(1.0, 1.0, 1.0) * border_line * 4.0; // Boost brightness

        color = mix(color, analyzed, in_scan * 0.9);
    } else {
        // Dim outside
        color *= 0.4;
    }

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, 1.0));
}
