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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Steps, y=Offset, z=ColorShift, w=Mix
  ripples: array<vec4<f32>, 50>,
};

fn hue_shift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cos_angle = cos(shift);
    return vec3<f32>(color * cos_angle + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cos_angle));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let steps_param = u.zoom_params.x * 20.0 + 5.0; // 5 to 25 steps
    let offset_param = u.zoom_params.y * 0.8; // Offset 0 to 0.8
    let color_freq = u.zoom_params.z * 10.0 + 2.0;
    let mix_amt = u.zoom_params.w;

    let mouse = u.zoom_config.yz * vec2<f32>(aspect, 1.0);
    var p = uv * vec2<f32>(aspect, 1.0) - mouse;

    // Rotate slightly over time for effect
    let time = u.config.x * 0.2;
    let s = sin(time);
    let c = cos(time);
    p = vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);

    var height = 0.0;
    var size = 1.0;
    var current_offset = vec2<f32>(0.0);

    // Iterative box SDF-like approach
    for (var i = 0.0; i < steps_param; i = i + 1.0) {
        // Distance to current box edge
        // Box is centered at current_offset with 'size'
        let d = max(abs(p.x - current_offset.x), abs(p.y - current_offset.y));

        if (d < size) {
            // We are inside this box layer
            height = i;

            // Prepare for next inner layer
            // We shrink the size and move the center
            let shrink = 0.1; // Amount to shrink per step
            size = size - shrink;

            // Determine direction to offset based on quadrant of p relative to center
            // This creates the hopper effect (spiraling inward)
            // Simplification: Shift towards one corner based on iteration parity
            let mod_i = i % 4.0;
            var dir = vec2<f32>(0.0);
            if (mod_i < 1.0) { dir = vec2<f32>(1.0, 1.0); }
            else if (mod_i < 2.0) { dir = vec2<f32>(-1.0, 1.0); }
            else if (mod_i < 3.0) { dir = vec2<f32>(-1.0, -1.0); }
            else { dir = vec2<f32>(1.0, -1.0); }

            current_offset = current_offset + dir * offset_param * shrink;

        } else {
            // Outside the outermost box that contains p?
            // Actually, we start large. If p is outside the current box, it belongs to the previous layer (or background).
            // But since we start with size 1.0 (or larger), and p is usually small, this logic is inverted.
            // Better: loop determines strictly the "deepest" box p is inside.
            // Since we shrink, the condition `d < size` becomes FALSE eventually.
            // The last time it was TRUE is our depth.
            // Wait, if `d < size` is true, we go deeper.
            // So we continue.
        }

        if (size <= 0.0) { break; }
    }

    // Calculate color based on height
    // Iridescence
    let phase = height * 0.5 + u.config.x;
    let irid = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.0, 4.0) + phase * color_freq);

    // Geometry edge highlight
    // Fractional part of height or similar?
    // We didn't compute precise distance, just discrete steps.
    // Let's add shading based on normal of the "pyramid" faces.
    // Hard to get normal without precise SDF.
    // Use steps as distinct bands.

    // Sample texture
    let img_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Displace UV based on crystal structure?
    // Let's use the height to refract the image
    let refraction_scale = 0.01;
    let uv_refracted = uv + vec2<f32>(sin(height), cos(height)) * refraction_scale;
    let refracted_color = textureSampleLevel(readTexture, u_sampler, uv_refracted, 0.0).rgb;

    // Mix iridescence with refracted image
    let crystal_look = mix(refracted_color, irid, 0.6); // Mostly iridescence

    // Mask: Only apply near mouse? Or everywhere?
    // Let's fade out at edges of screen or based on max size
    // For now, full screen.

    let final_color = mix(img_color, crystal_look, mix_amt);

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
}
