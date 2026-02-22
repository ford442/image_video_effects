// ────────────────────────────────────────────────────────────────────────────────
//  Scan Distort
//  CRT-style scanlines that bend and warp around the mouse cursor.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    let mouse = u.zoom_config.yz;
    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    // Params
    let lines = u.zoom_params.x * 200.0 + 50.0;
    let bendStr = u.zoom_params.y * 0.2;
    let speed = u.zoom_params.z * 5.0;

    // Mouse Influence
    // Push lines away from mouse vertically
    let push = smoothstep(0.4, 0.0, dist);

    // We displace the Y coordinate used for the sine wave, not the texture lookup (yet)
    // Actually, to bend the lines, we need to displace the UV we use to calculate the line pattern.

    let lineUV = uv;
    // Calculate a vertical offset based on mouse proximity
    let vOffset = push * bendStr * sin(dist * 20.0 - time * 2.0);

    // Scanline pattern
    // sin(y * lines + time)
    let scanVal = sin((lineUV.y + vOffset) * lines - time * speed);
    let scanLine = smoothstep(0.0, 1.0, scanVal);

    // Distort the image sampling itself too
    let imgUV = uv + vec2<f32>(vOffset * 0.1, vOffset);

    let color = textureSampleLevel(videoTex, videoSampler, imgUV, 0.0).rgb;

    // Apply scanline darkening
    let finalColor = color * (0.8 + 0.2 * scanLine);

    // Add RGB split on the edges of the distortion
    let r = textureSampleLevel(videoTex, videoSampler, imgUV + vec2<f32>(vOffset * 0.05, 0.0), 0.0).r;
    let b = textureSampleLevel(videoTex, videoSampler, imgUV - vec2<f32>(vOffset * 0.05, 0.0), 0.0).b;

    let splitColor = vec3<f32>(r, finalColor.g, b) * (0.8 + 0.2 * scanLine);

    textureStore(outTex, gid.xy, vec4<f32>(splitColor, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
