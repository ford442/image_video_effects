// ═══════════════════════════════════════════════════════════════════
//  chroma-threads-gabor
//  Category: advanced-hybrid
//  Features: chroma-threads, gabor-texture-analysis, mouse-driven
//  Complexity: High
//  Chunks From: chroma-threads, conv-gabor-texture-analyzer
//  Created: 2026-04-18
//  By: Agent CB-12 — Chroma & Spectral Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Vibrating horizontal threads whose displacement is colored by
//  multi-orientation Gabor filter responses. Each thread samples
//  a psychedelic palette based on local texture orientation.
// ═══════════════════════════════════════════════════════════════════

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

fn gaborResponse(uv: vec2<f32>, theta: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> f32 {
    var response = 0.0;
    let radius = i32(ceil(sigma * 3.0));
    let maxRadius = min(radius, 4);
    let cosTheta = cos(theta);
    let sinTheta = sin(theta);
    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let x = f32(dx);
            let y = f32(dy);
            let xTheta = x * cosTheta + y * sinTheta;
            let yTheta = -x * sinTheta + y * cosTheta;
            let gaussian = exp(-(xTheta*xTheta + yTheta*yTheta) / (2.0 * sigma * sigma + 0.001));
            let sinusoidal = cos(2.0 * 3.14159265 * freq * xTheta);
            let kernel = gaussian * sinusoidal;
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
            response += luma * kernel;
        }
    }
    return response;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Thread params
    let density = mix(50.0, 300.0, u.zoom_params.x);
    let amp = u.zoom_params.y * 0.2;
    let split = u.zoom_params.z * 0.05;

    // Gabor params
    let freq = mix(0.05, 0.3, u.zoom_params.y);
    let sigma = mix(1.5, 4.0, u.zoom_params.z);
    let responseScale = mix(0.5, 3.0, u.zoom_params.w);

    let threadID = floor(uv.y * density);
    let threadUVY = (threadID + 0.5) / density;
    let distY = abs(threadUVY - mousePos.y);
    let mouseRadius = 0.2;
    let influence = smoothstep(mouseRadius, 0.0, distY);
    let distX = uv.x - mousePos.x;
    let vibration = sin(distX * 20.0 - time * 10.0) * exp(-abs(distX) * 5.0);
    let activeAmp = amp * (1.0 + mouseDown * 2.0);
    let offset = vibration * influence * activeAmp;

    let offsetR = offset * (1.0 + split * 10.0);
    let offsetG = offset;
    let offsetB = offset * (1.0 - split * 10.0);

    let threadPattern = abs(fract(uv.y * density) - 0.5) * 2.0;
    let mask = smoothstep(0.9, 0.6, threadPattern);

    let uvR = vec2<f32>(uv.x - offsetR, uv.y);
    let uvG = vec2<f32>(uv.x - offsetG, uv.y);
    let uvB = vec2<f32>(uv.x - offsetB, uv.y);

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Gabor coloring on thread samples
    let r0 = gaborResponse(uv, 0.0, freq, sigma, pixelSize) * responseScale;
    let r45 = gaborResponse(uv, 0.785398, freq, sigma, pixelSize) * responseScale;
    let r90 = gaborResponse(uv, 1.570796, freq, sigma, pixelSize) * responseScale;

    let pal0 = palette(r0 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    let pal45 = palette(r45 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0));
    let pal90 = palette(r90 * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33));

    let totalResponse = abs(r0) + abs(r45) + abs(r90) + 0.001;
    var gaborColor = pal0 * abs(r0) + pal45 * abs(r45) + pal90 * abs(r90);
    gaborColor = gaborColor / totalResponse;

    var threadColor = vec3<f32>(r, g, b) * mask;
    threadColor = mix(threadColor, gaborColor * mask, 0.5);

    let highlight = exp(-length(uv - mousePos) * 10.0) * 0.2;

    textureStore(writeTexture, gid.xy, vec4<f32>(threadColor + highlight, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
