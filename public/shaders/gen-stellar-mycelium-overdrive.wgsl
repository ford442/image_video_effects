// ----------------------------------------------------------------
// Stellar Mycelium Overdrive
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

// SDF functions
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let p_scaled = p * scale;
    return abs(dot(sin(p_scaled), cos(vec3<f32>(p_scaled.z, p_scaled.x, p_scaled.y))) - bias) / scale - thickness;
}

// Map function
fn map(pos: vec3<f32>, mouse_dist: f32) -> f32 {
    let density = u.zoom_params.x;
    var p = pos;
    // Mouse Interaction
    if (u.zoom_config.w > 0.5) {
        let pull = exp(-mouse_dist * 2.0);
        p -= normalize(p) * pull * 0.5;
    }
    // Basic structure with fBm-like distortion
    var d = sdGyroid(p, 5.0 * density, 0.05, 0.0);
    var d2 = sdGyroid(p + vec3<f32>(1.2, 0.5, 0.9), 10.0 * density, 0.02, 0.1);
    return max(d, -d2);
}

fn getAudio() -> vec3<f32> {
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    return vec3<f32>(bass, mids, treble);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let uv = (vec2<f32>(id.xy) - 0.5 * dims) / dims.y;
    if (id.x >= u32(dims.x) || id.y >= u32(dims.y)) { return; }

    let audio = getAudio();
    let pulse_speed = u.zoom_params.y;
    let glow_intensity = u.zoom_params.z;
    let color_shift = u.zoom_params.w;

    // Setup camera, ray direction
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(uv, 1.0));
    let time = u.config.x * pulse_speed * 0.5;
    ro.z += time;

    // Mouse calculation
    var mouse_dist = 10.0;
    if (u.zoom_config.w > 0.5) {
        let mouse_uv = (u.zoom_config.yz - 0.5 * dims) / dims.y;
        mouse_dist = length(uv - mouse_uv);
    }

    // Raymarching loop
    var t = 0.0;
    var bloom = 0.0;
    var d = 0.0;
    for (var i = 0; i < 64; i++) {
        let p = ro + rd * t;
        d = map(p, mouse_dist);
        if (d < 0.001) { break; }
        t += d * 0.7;
        // Accumulate bloom for glowing fog
        bloom += 0.05 * glow_intensity / (1.0 + d * d * 50.0);
        if (t > 10.0) { break; }
    }

    // Coloring and bloom
    let base_color = vec3<f32>(0.1, 0.3, 0.8); // Metallic purple/blue
    let tip_color = vec3<f32>(0.9, 0.2, 0.8);  // Neon pink/cyan

    let hue_shift = color_shift * time * 0.2 + audio.x * 0.5;
    var final_color = mix(base_color, tip_color, sin(t * 2.0 + hue_shift) * 0.5 + 0.5);

    final_color *= bloom;
    // Audio reactive pulse
    final_color += tip_color * bloom * audio.y * 0.5;

    // Output to texture
    textureStore(writeTexture, id.xy, vec4<f32>(final_color, 1.0));
}
