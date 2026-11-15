// ═══════════════════════════════════════════════════════════════════
//  Chroma Threads Gabor
//  Category: advanced-hybrid
//  Features: chroma-threads, gabor-texture-analysis, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: grain-following nudge; filament core
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn gaborResponse(uv: vec2<f32>, theta: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> f32 {
    var response = 0.0;
    let radius = i32(ceil(sigma * 3.0));
    let maxRadius = min(radius, 4);
    let cosTheta = cos(theta);
    let sinTheta = sin(theta);
    for (var dy = -maxRadius; dy <= maxRadius; dy = dy + 1) {
        for (var dx = -maxRadius; dx <= maxRadius; dx = dx + 1) {
            let x = f32(dx);
            let y = f32(dy);
            let xTheta = x * cosTheta + y * sinTheta;
            let yTheta = -x * sinTheta + y * cosTheta;
            let gaussian = exp(-(xTheta * xTheta + yTheta * yTheta) / (2.0 * sigma * sigma + 0.001));
            let sinusoidal = cos(2.0 * 3.14159265 * freq * xTheta);
            let kernel = gaussian * sinusoidal;
            let offset = vec2<f32>(x, y) * pixelSize;
            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let luma = dot(textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
            response = response + luma * kernel;
        }
    }
    return response;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let pixelSize = 1.0 / max(res, vec2<f32>(1.0));
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let density = mix(50.0, 300.0, u.zoom_params.x);
    let amp = u.zoom_params.y * 0.2;
    let split = u.zoom_params.z * 0.05;

    let freq = mix(0.05, 0.3, u.zoom_params.y);
    let sigma = mix(1.5, 4.0, u.zoom_params.z);
    let responseScale = mix(0.5, 3.0, u.zoom_params.w);

    let r0 = gaborResponse(uv, 0.0, freq, sigma, pixelSize) * responseScale;
    let r45 = gaborResponse(uv, 0.785398, freq, sigma, pixelSize) * responseScale;
    let r90 = gaborResponse(uv, 1.570796, freq, sigma, pixelSize) * responseScale;

    // ── Idea 1: grain-following nudge — the Gabor orientation the colour already uses
    let w0 = abs(r0);
    let w45 = abs(r45);
    let w90 = abs(r90);
    let orient = (w45 * 0.785398 + w90 * 1.570796) / max(w0 + w45 + w90, 0.001);
    let grain = vec2<f32>(cos(orient), sin(orient)) * (0.006 + amp * 0.18);

    let threadID = floor(uv.y * density);
    let threadUVY = (threadID + 0.5) / max(density, 1.0);
    let distY = abs(threadUVY - mousePos.y);
    let mouseRadius = 0.2;
    let influence = smoothstep(mouseRadius, 0.0, distY);
    let distX = uv.x - mousePos.x;
    let vibration = sin(distX * 20.0 + orient * 5.0 - time * 10.0) * exp(-abs(distX) * 5.0);
    let activeAmp = amp * (1.0 + mouseDown * 2.0);
    let offset = vibration * influence * activeAmp;

    let offsetR = offset * (1.0 + split * 10.0);
    let offsetG = offset;
    let offsetB = offset * (1.0 - split * 10.0);

    let threadPattern = abs(fract(uv.y * density) - 0.5) * 2.0;
    let mask = smoothstep(0.9, 0.6, threadPattern);

    let uvR = clamp(vec2<f32>(uv.x - offsetR, uv.y) + grain, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(vec2<f32>(uv.x - offsetG, uv.y) + grain, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(vec2<f32>(uv.x - offsetB, uv.y) + grain, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let gSample = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));

    let totalResponse = w0 + w45 + w90 + 0.001;
    var gaborColor = pal0 * w0 + pal45 * w45 + pal90 * w90;
    gaborColor = gaborColor / totalResponse;

    var threadColor = vec3<f32>(r, gSample.g, b) * mask;
    threadColor = mix(threadColor, gaborColor * mask, 0.5);

    // ── Idea 2: filament core — the thread centerline is brighter than its edge
    let core = smoothstep(0.42, 0.05, threadPattern);
    threadColor = threadColor * (1.0 + core * mask * 0.85);

    let highlight = exp(-length(uv - mousePos) * 10.0) * 0.2;
    let display = aces(max(threadColor + highlight, vec3<f32>(0.0)));
    let alpha = clamp(0.42 + mask * 0.4 + core * mask * 0.18 + highlight, 0.0, 1.0);
    let outColor = vec4<f32>(display, alpha);

    textureStore(writeTexture, gid.xy, outColor);
    textureStore(dataTextureA, gid.xy, outColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(clamp(depth * 0.85 + core * mask * 0.15, 0.0, 1.0), 0.0, 0.0, 0.0));
}
