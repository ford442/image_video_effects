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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let tunnelStrength = u.zoom_params.x; // 0.0 to 1.0 (Zoom strength)
    let aberration = u.zoom_params.y;     // 0.0 to 1.0 (Color split)
    let pulseSpeed = u.zoom_params.z;     // 0.0 to 1.0
    let spiral = u.zoom_params.w;         // 0.0 to 1.0 (Twist)

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let center = mouse;

    // Correct for aspect ratio for distance calculation
    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
    let centerAspect = vec2<f32>(center.x * aspect, center.y);
    let offset = uvAspect - centerAspect;
    let dist = length(offset);
    let angle = atan2(offset.y, offset.x);

    // Dynamic Pulse
    let time = u.config.x;
    let pulse = sin(dist * 20.0 - time * (pulseSpeed * 10.0)) * 0.05 * tunnelStrength;

    // Twist
    let twistAngle = angle + (1.0 - smoothstep(0.0, 1.0, dist)) * (spiral * 5.0) * sin(time);

    // Zoom factor
    let zoom = 1.0 - (tunnelStrength * 0.5 * smoothstep(1.0, 0.0, dist));

    // Chromatic Aberration: Sample R, G, B at different scales/twists
    let abbrScale = aberration * 0.05 * dist; // More aberration at edges

    var color: vec4<f32>;

    let rR = dist * (zoom - abbrScale);
    let rG = dist * zoom;
    let rB = dist * (zoom + abbrScale);

    let offR = vec2<f32>(cos(twistAngle), sin(twistAngle)) * rR;
    let offG = vec2<f32>(cos(twistAngle), sin(twistAngle)) * rG;
    let offB = vec2<f32>(cos(twistAngle), sin(twistAngle)) * rB;

    // Convert back to UV space (undo aspect correction)
    let uvR = vec2<f32>(offR.x / aspect, offR.y) + center;
    let uvG = vec2<f32>(offG.x / aspect, offG.y) + center;
    let uvB = vec2<f32>(offB.x / aspect, offB.y) + center;

    let cR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let cG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let cB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    color = vec4<f32>(cR, cG, cB, 1.0);

    // Let's add a "glow" at the mouse cursor
    let glow = 1.0 - smoothstep(0.0, 0.1, dist);
    color = color + vec4<f32>(0.2, 0.4, 1.0, 0.0) * glow * tunnelStrength;

    textureStore(writeTexture, global_id.xy, color);
}
