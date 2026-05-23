// ═══════════════════════════════════════════════════════════════════
//  Zoom Burst
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Description: Radial zoom blur emanating from the mouse cursor, simulating
//    a long-exposure zoom-lens pull. Each pixel samples along the ray from
//    the focal point through its screen position, accumulating N samples at
//    increasing zoom magnifications. Bass pulses the burst radius for a
//    beat-synchronized explosion; mids rotate the burst slightly for a
//    spin-zoom hybrid; treble adds chromatic fringing along burst rays.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=burst_length, y=num_samples, z=spin_angle, w=chroma

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
  zoom_params: vec4<f32>,  // x=burst_len, y=samples, z=spin, w=chroma
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / res;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Focal centre: mouse position
    let focal  = u.zoom_config.yz;

    // Ray from focal point through current pixel
    let ray    = uv - focal;
    let rayLen = length(ray);

    // Burst parameters
    let burstBase = 0.02 + u.zoom_params.x * 0.16;
    let burst     = burstBase * (1.0 + bass * 0.7);  // bass pulses the radius
    let nSamp     = max(4.0, floor(4.0 + u.zoom_params.y * 28.0));
    let spinAngle = u.zoom_params.z * 0.08 + mids * 0.03;  // slight rotation per sample
    let chromaStr = u.zoom_params.w * 0.012 + treble * 0.006;

    // Avoid singularity at focal point
    let minRay = 0.001;
    let rayDir = select(vec2<f32>(1.0, 0.0), ray / rayLen, rayLen > minRay);

    var accR = 0.0;
    var accG = 0.0;
    var accB = 0.0;
    var wSum = 0.0;

    let invN = 1.0 / nSamp;

    for (var i = 0.0; i < nSamp; i += 1.0) {
        let t     = i * invN;  // 0 = current pixel, 1 = max zoom-out
        let scale = 1.0 - burst * t;  // zoom out toward focal point

        // Optional spin: rotate ray slightly for each sample
        let angle = spinAngle * t;
        let ca    = cos(angle);
        let sa    = sin(angle);
        let rotDir = vec2<f32>(rayDir.x * ca - rayDir.y * sa,
                               rayDir.x * sa + rayDir.y * ca);

        // Zoomed sample UV: move toward focal at this step
        let sUV = focal + rotDir * rayLen * scale;

        // Chromatic fringing: R samples farther out, B closer in
        let cOff   = chromaStr * t;
        let uvR    = focal + rotDir * rayLen * (scale + cOff);
        let uvG    = sUV;
        let uvB    = focal + rotDir * rayLen * (scale - cOff);

        let sR = textureSampleLevel(readTexture, u_sampler,
                     clamp(uvR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let sG = textureSampleLevel(readTexture, u_sampler,
                     clamp(uvG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
        let sB = textureSampleLevel(readTexture, u_sampler,
                     clamp(uvB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

        // Weight: taper toward far samples (closer samples have higher weight)
        let w  = 1.0 - t * 0.5;
        accR  += sR * w;
        accG  += sG * w;
        accB  += sB * w;
        wSum  += w;
    }

    let invW   = 1.0 / max(wSum, 0.001);
    let finalRGB = clamp(vec3<f32>(accR, accG, accB) * invW, vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha: stronger at pixels far from focal (more burst), fades at centre
    let src   = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let radFrac = clamp(rayLen / max(burst * 3.0, 0.01), 0.0, 1.0);
    let alpha = clamp(src.a * 0.5 + radFrac * 0.5 + bass * 0.12, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
