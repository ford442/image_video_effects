// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn grid(uv: vec2<f32>, angle: f32, scale: f32) -> f32 {
    let s = sin(angle);
    let c = cos(angle);
    let rot = mat2x2<f32>(c, -s, s, c);
    let st = (rot * uv) * scale;
    return (sin(st.x) * sin(st.y)) * 0.5 + 0.5;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Params
    let dotScale = mix(50.0, 400.0, u.zoom_params.x); // x: Scale (Default 0.5 -> 225)
    let scanSpeed = u.zoom_params.y * 2.0;            // y: Speed
    let sep = u.zoom_params.z * 0.05;                 // z: Separation
    let brightness = u.zoom_params.w * 2.0;           // w: Brightness

    // Scanline logic
    let scanY = (time * scanSpeed) % 1.5 - 0.25;
    let dist = abs(uv.y - scanY);
    let scanIntensity = smoothstep(0.2, 0.0, dist);

    // Sample texture with separation for CMYK effect
    let texR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(sep, sep), 0.0).r;
    let texG = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let texB = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(sep, sep), 0.0).b;

    // Halftone patterns (angles: 15, 75, 0, 45 usually for CMYK, mimicking here with RGB)
    let patR = grid(uv, 0.26, dotScale); // ~15 deg
    let patG = grid(uv, 1.30, dotScale); // ~75 deg
    let patB = grid(uv, 0.0, dotScale);  // 0 deg

    // Thresholding
    let r = step(patR, texR * brightness + scanIntensity);
    let g = step(patG, texG * brightness + scanIntensity);
    let b = step(patB, texB * brightness + scanIntensity);

    // Mix with original image based on scanline
    let halftone = vec4<f32>(r, g, b, 1.0);

    // Make the scanline area purely the glitch/halftone, and the rest the original image?
    // Or apply globally? The name is "Scanner", implies the effect is localized or the whole thing is the scan result.
    // Let's make it global but the scanline adds brightness/intensity.

    let finalColor = halftone;

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
