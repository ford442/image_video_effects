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

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);
    let time = u.config.x;

    // Params
    let scanSpeed = u.zoom_params.x;     // 1.0 to 10.0
    let glitchAmount = u.zoom_params.y;  // 0.0 to 1.0
    let hueShift = u.zoom_params.z;      // 0.0 to 1.0
    let focusStrength = u.zoom_params.w; // 0.0 to 1.0 (Stabilizer)

    // Mouse Stabilization
    let aspect = f32(dims.x) / f32(dims.y);
    let mousePos = u.zoom_config.yz;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Calculate local glitch intensity: Reduced near mouse
    let stabilization = smoothstep(0.0, 0.4, dist) * focusStrength;
    // If focusStrength is 0, stabilization is 0 (full glitch).
    // If focusStrength is 1, stabilization is 0 at mouse, 1 far away.
    // We want LOW glitch near mouse.
    // So effectiveGlitch should be glitchAmount * stabilization + (small base if not focused)

    let effectiveGlitch = glitchAmount * mix(1.0, stabilization, focusStrength);

    // Scanlines
    let scanline = sin(uv.y * 800.0 + time * scanSpeed * 5.0) * 0.1;
    let slowScan = sin(uv.y * 10.0 - time * scanSpeed) * 0.2;

    // Glitch Offset
    var offset = vec2<f32>(0.0);
    if (effectiveGlitch > 0.01) {
        let block = floor(uv.y * 20.0);
        let noise = rand(vec2<f32>(block, floor(time * 10.0)));
        if (noise < effectiveGlitch * 0.3) {
            offset.x = (rand(vec2<f32>(time)) - 0.5) * effectiveGlitch * 0.2;
        }
    }

    // Chromatic Aberration
    let aberr = effectiveGlitch * 0.05;

    let r = textureSampleLevel(readTexture, u_sampler, uv + offset + vec2<f32>(aberr, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + offset - vec2<f32>(aberr, 0.0), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Apply scanlines
    color += scanline + slowScan;

    // Hologram Tint (Cyan/Blue usually, but adjustable via HueShift)
    // Simple tint: Boost G/B, reduce R, then rotate
    // Let's just multiply by a tint color
    // hueShift 0 -> Cyan, 0.5 -> Magenta, 1.0 -> Yellow?
    // Let's keep it simple: Just RGB manipulation

    let tint = vec3<f32>(0.5 + 0.5 * sin(hueShift * 6.28), 0.8, 0.5 + 0.5 * cos(hueShift * 6.28));
    color = color * tint * 1.5; // Boost brightness for holo look

    // Flicker
    let flicker = 0.9 + 0.1 * sin(time * 20.0);
    color *= flicker;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
