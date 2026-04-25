// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Vortex - Polar Distortion + Color-Space Warp
//  Category: distortion
//  Description: Rotates image in polar coordinates with psychedelic
//               color-space warping driven by audio.
//  Features: mouse-driven, audio-reactive, distortion
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// RGB to YUV and back for color-space warping
fn rgb2yuv(c: vec3<f32>) -> vec3<f32> {
    let y = dot(c, vec3<f32>(0.299, 0.587, 0.114));
    let u_ = dot(c, vec3<f32>(-0.14713, -0.28886, 0.436));
    let v = dot(c, vec3<f32>(0.615, -0.51499, -0.10001));
    return vec3<f32>(y, u_, v);
}

fn yuv2rgb(c: vec3<f32>) -> vec3<f32> {
    let r = c.x + 1.13983 * c.z;
    let g = c.x - 0.39465 * c.y - 0.58060 * c.z;
    let b = c.x + 2.03211 * c.y;
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Vortex center (mouse-controlled)
    let center = u.zoom_config.yz;

    // Parameters
    let swirlStrength = u.zoom_params.x * 8.0 + bass * 2.0;
    let radiusScale = u.zoom_params.y * 3.0 + 0.5;
    let polarDistort = u.zoom_params.z * 2.0;
    let colorWarp = u.zoom_params.w;

    // Polar coordinates relative to center
    let delta = uv - center;
    let r = length(delta);
    let theta = atan2(delta.y, delta.x);

    // Spiral distortion
    let spiral = theta + swirlStrength * r * radiusScale + time * 0.3;
    let warpedR = r + polarDistort * sin(spiral * 3.0 + time) * 0.1;

    // Fold into polar sectors
    let sectors = 6.0 + floor(bass * 4.0);
    let foldedTheta = fract(spiral / 6.28318 * sectors) / sectors * 6.28318;

    // Rebuild UV
    let warpedUV = center + vec2<f32>(cos(foldedTheta), sin(foldedTheta)) * warpedR;

    // Sample with mirrored repetition for kaleidoscope effect
    let sampleUV = abs(fract(warpedUV * 2.0) - 0.5) * 2.0;
    let col = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    // Color-space warp
    var yuv = rgb2yuv(col);

    // Audio-driven hue rotation via YUV phase shift
    let hueShift = time * 0.2 + bass * 1.5 + colorWarp * 3.14159;
    let cosH = cos(hueShift);
    let sinH = sin(hueShift);
    let u_rot = yuv.y * cosH - yuv.z * sinH;
    let v_rot = yuv.y * sinH + yuv.z * cosH;
    yuv.y = u_rot;
    yuv.z = v_rot;

    // Treble boosts luminance, mids boost saturation
    yuv.x = yuv.x * (1.0 + treble * 0.5);
    yuv.y = yuv.y * (1.0 + mids * 0.3);
    yuv.z = yuv.z * (1.0 + mids * 0.3);

    var outCol = yuv2rgb(yuv);

    // Vignette
    let vig = 1.0 - smoothstep(0.3, 1.0, r);
    outCol = outCol * (0.7 + 0.3 * vig);

    // Spiral brightness streaks
    let streak = pow(sin(spiral * sectors + time * 2.0) * 0.5 + 0.5, 4.0);
    outCol = outCol + vec3<f32>(streak * bass * 0.3);

    outCol = clamp(outCol, vec3<f32>(0.0), vec3<f32>(2.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, id.xy, vec4<f32>(outCol, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
