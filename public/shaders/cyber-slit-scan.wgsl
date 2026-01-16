// ────────────────────────────────────────────────────────────────────────────────
//  Cyber Slit Scan
//  Classic slit-scan effect where the scan line position is controlled by the mouse.
//  Includes cyber-punk style color quantization and digital artifacts.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>; // Write to history
@group(0) @binding(9) var feedbackTex: texture_2d<f32>; // Read from history

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let width = u32(dims.x);
    let height = u32(dims.y);

    if (gid.x >= width || gid.y >= height) { return; }

    let mouse = u.zoom_config.yz; // Normalized 0-1
    let time = u.config.x;

    // Slit Source X position determined by mouse X
    // Default to center if mouse not active
    var slitX = u32(mouse.x * dims.x);
    if (mouse.x < 0.0) { slitX = width / 2; }
    slitX = clamp(slitX, 0u, width - 1u);

    // Direction of scan: Right to Left
    // We shift the history texture to the left by 1 pixel
    // And write the new slit at the right edge

    var outputColor: vec4<f32>;

    // We act as if the screen is scrolling left.
    // If we are at the rightmost edge (width - 1), we sample the live video at slitX.
    // Otherwise, we sample the feedback texture at x + 1.

    // Wait, the compute shader runs for every pixel (gid.xy).
    // We need to decide what to put at gid.xy.
    // If we want the image to scroll left:
    // Pixel at (x, y) should take the value from (x + 1, y) of the PREVIOUS frame.
    // Pixel at (width-1, y) takes value from Video(slitX, y).

    // Scroll Speed Control (skip pixels to go faster?)
    let speed = 1u + u32(u.zoom_params.x * 5.0); // 1 to 6 pixels per frame

    if (gid.x >= width - speed) {
        // This is the "fresh" zone at the right edge.
        // Sample from the video at the slit position.

        let uvSource = vec2<f32>(f32(slitX) / dims.x, f32(gid.y) / dims.y);
        var color = textureSampleLevel(videoTex, videoSampler, uvSource, 0.0);

        // --- CYBER EFFECTS ---
        // 1. Color Quantization / Bit Crush
        let bits = mix(255.0, 2.0, u.zoom_params.y); // Param 2 controls crunch
        color = floor(color * bits) / bits;

        // 2. Glitch / Scanline Displacement
        // Occasionally offset the Y coordinate based on time or audio
        if (fract(time * 10.0 + f32(gid.y) * 0.01) > 0.98) {
             color *= 1.5; // Bright line
        }

        // 3. Neon Shift
        // Boost saturation/value for cyberpunk look
        var hsv = rgb2hsv(color.rgb);
        hsv.y = min(hsv.y * 1.2, 1.0); // Saturation boost
        hsv.z = min(hsv.z * 1.1, 1.0); // Brightness boost

        // Shift hue based on mouse Y
        hsv.x = fract(hsv.x + mouse.y * 0.5);

        outputColor = vec4<f32>(hsv2rgb(hsv), 1.0);

    } else {
        // Shift history
        // Read from (x + speed, y)
        // Ensure we don't read out of bounds (though textureSample handles clamping usually)
        // Since we are using textureLoad or integer coordinates, we need to be careful.
        // Using textureSample with UV is easier.

        let uvHistory = vec2<f32>(f32(gid.x + speed) / dims.x, f32(gid.y) / dims.y);

        // Sample from previous frame (feedbackTex)
        outputColor = textureSampleLevel(feedbackTex, videoSampler, uvHistory, 0.0);

        // Slight decay or color shift over time as it scrolls?
        // Let's keep it clean for a true slit-scan, maybe just a tiny bit of fade if desired.
        // outputColor *= 0.999;
    }

    textureStore(feedbackOut, gid.xy, outputColor);
    textureStore(outTex, gid.xy, outputColor);
}
