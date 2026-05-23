// ═══════════════════════════════════════════════════════════════════
//  Anaglyph 3D
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Description: Red-cyan stereoscopic anaglyph from a single camera feed.
//    The red channel is sampled at a leftward offset and the cyan channels
//    at a rightward offset, simulating parallax depth. Separation scales
//    with depth proximity to the mouse cursor. Bass pulses the split width;
//    mids tint the ghost fringing; mouse positions the focal centre.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=separation, y=depth_curve, z=ghost_strength, w=grain

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=separation, y=depth_curve, z=ghost_strength, w=grain
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / res;
    let time  = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Base stereo separation (UV fraction) — bass expands it
    let sepBase  = 0.004 + u.zoom_params.x * 0.024;
    let sep      = sepBase * (1.0 + bass * 0.6);

    // Depth curve: distance from mouse focal point changes per-pixel separation
    let mouse    = u.zoom_config.yz;
    let aspect   = res.x / res.y;
    let toMouse  = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist     = clamp(length(toMouse), 0.0, 1.0);
    let curve    = 0.5 + u.zoom_params.y * 2.5;  // depth falloff
    let localSep = sep * (0.3 + pow(dist, curve) * 1.4);

    // Ghost fringing strength (secondary echo at wider separation)
    let ghostStr = u.zoom_params.z * 0.35 * (1.0 + mids * 0.5);

    // Sample red channel left-shifted, cyan (GB) channels right-shifted
    let uvL  = clamp(uv - vec2<f32>(localSep, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvR  = clamp(uv + vec2<f32>(localSep, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvL2 = clamp(uv - vec2<f32>(localSep * 1.6, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvR2 = clamp(uv + vec2<f32>(localSep * 1.6, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let sL  = textureSampleLevel(readTexture, u_sampler, uvL, 0.0);
    let sR  = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
    let sL2 = textureSampleLevel(readTexture, u_sampler, uvL2, 0.0);
    let sR2 = textureSampleLevel(readTexture, u_sampler, uvR2, 0.0);

    // Anaglyph combine: red eye = left, cyan eye = right
    var r = sL.r + ghostStr * sL2.r;
    var g = sR.g + ghostStr * sR2.g;
    var b = sR.b + ghostStr * sR2.b;

    // Mids add a warm tint to the left ghost and cool to right
    r = clamp(r * (1.0 + mids * 0.15), 0.0, 1.0);
    g = clamp(g, 0.0, 1.0);
    b = clamp(b * (1.0 + treble * 0.1), 0.0, 1.0);

    // Film grain
    let grainAmt = u.zoom_params.w * 0.06;
    let grain    = (hash21(uv * 7139.3 + vec2<f32>(fract(time), fract(time * 1.7))) - 0.5) * grainAmt;
    let rgb      = clamp(vec3<f32>(r, g, b) + grain, vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha: stronger at separation edges (the 3D "depth" regions)
    let src   = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma  = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(src.a * 0.6 + luma * 0.5 + bass * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
