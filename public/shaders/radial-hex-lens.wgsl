struct Uniforms {
    time: f32,
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    scale: f32,
    radius: f32,
    distortion: f32,
};

@group(0) @binding(0) var<uniform> uni: Uniforms;
@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

fn get_hex_center(uv: vec2<f32>, scale: f32) -> vec2<f32> {
    let r = vec2<f32>(1.0, 1.7320508); // 1.0, sqrt(3.0)
    let h = r * 0.5;

    // Divide space into a grid
    let spacing = vec2<f32>(scale, scale * r.y);

    let a = (fract(uv / spacing) - 0.5) * spacing;
    let b = (fract((uv - spacing * 0.5) / spacing) - 0.5) * spacing;

    let center_a = uv - a;
    let center_b = uv - b;

    if (dot(a, a) < dot(b, b)) {
        return center_a;
    } else {
        return center_b;
    }
}

@fragment
fn main(@builtin(position) FragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    let uv = FragCoord.xy / uni.resolution;
    var uv_corrected = uv;
    uv_corrected.x = uv_corrected.x * (uni.resolution.x / uni.resolution.y); // Fix aspect for math

    let mouse_corrected = vec2<f32>(
        uni.mouse.x * (uni.resolution.x / uni.resolution.y),
        uni.mouse.y
    );

    // Lens Distortion
    let offset = uv_corrected - mouse_corrected;
    let dist = length(offset);

    // Nonlinear zoom: bulge out near mouse
    // Map dist to new_dist
    let effect_radius = uni.radius * 1.5; // Scale up a bit to be useful
    let strength = uni.distortion;

    // Simple bulge: displacement direction is -offset (pull in) or +offset (push out)
    // Fisheye usually pulls UVs inward to zoom center.
    // New UV = Center + Offset * (1.0 - Strength * Falloff)

    let falloff = smoothstep(effect_radius, 0.0, dist);
    let zoom_factor = 1.0 - strength * falloff * 0.5; // Max 0.5x zoom (2x mag)

    let distorted_pos = mouse_corrected + offset * zoom_factor;

    // Back to 0-1 UV space for sampling?
    // Wait, hex grid needs aspect corrected space to be regular hexes.

    // Hex Pixelate
    // Map 0.0-1.0 slider to useful scale (e.g. 0.01 to 0.1)
    let hex_size = mix(0.01, 0.1, uni.scale);

    // Determine hex center in aspect-corrected space
    let center = get_hex_center(distorted_pos, hex_size);

    // Convert back to UV space
    var sample_uv = center;
    sample_uv.x = sample_uv.x / (uni.resolution.x / uni.resolution.y);

    // Edge darkening for hexes (optional, adds style)
    let dist_to_center = length(distorted_pos - center);
    let hex_mask = smoothstep(hex_size * 0.5, hex_size * 0.45, dist_to_center);

    // Sample texture
    // Mirror repeat to handle edges
    let color = textureSample(myTexture, mySampler, sample_uv);

    return color * hex_mask;
}
