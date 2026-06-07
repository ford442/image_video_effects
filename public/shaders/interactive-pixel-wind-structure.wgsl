// ═══════════════════════════════════════════════════════════════════
//  interactive-pixel-wind-structure
//  Category: advanced-hybrid
//  Features: mouse-driven, feedback, structure-tensor, flow
//  Complexity: High
//  Chunks From: interactive-pixel-wind.wgsl, conv-structure-tensor-flow.wgsl
//  Created: 2026-04-18
//  By: Agent CB-25
// ═══════════════════════════════════════════════════════════════════
//  Wind direction is driven by the dominant texture orientation
//  extracted from the structure tensor. Line Integral Convolution
//  guides the wind flow while mouse creates vortices. Includes
//  chromatic aberration and feedback trails.
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

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
    let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
    return dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
    var sum = vec4<f32>(0.0);
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let p = uv + offset;
            let gx = -1.0 * sampleLuma(p, pixelSize, -1, -1) + -2.0 * sampleLuma(p, pixelSize, -1, 0) + -1.0 * sampleLuma(p, pixelSize, -1, 1)
                   +  1.0 * sampleLuma(p, pixelSize,  1, -1) +  2.0 * sampleLuma(p, pixelSize,  1, 0) +  1.0 * sampleLuma(p, pixelSize,  1, 1);
            let gy = -1.0 * sampleLuma(p, pixelSize, -1, -1) + -2.0 * sampleLuma(p, pixelSize, 0, -1) + -1.0 * sampleLuma(p, pixelSize, 1, -1)
                   +  1.0 * sampleLuma(p, pixelSize, -1,  1) +  2.0 * sampleLuma(p, pixelSize, 0,  1) +  1.0 * sampleLuma(p, pixelSize, 1,  1);
            sum += vec4<f32>(gx * gx, gy * gy, gx * gy, 0.0);
        }
    }
    return sum / 9.0;
}

fn random(st: vec2<f32>) -> f32 {
    return fract(sin(dot(st.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453123);
}

fn noise(st: vec2<f32>) -> f32 {
    let i = floor(st);
    let f = fract(st);
    let a = random(i);
    var b = random(i + vec2<f32>(1.0, 0.0));
    let c = random(i + vec2<f32>(0.0, 1.0));
    var d = random(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let strength = u.zoom_params.x * 0.1;
    let turbulence = u.zoom_params.y;
    let trails = u.zoom_params.z;
    let shift = u.zoom_params.w;

    // Compute structure tensor for flow direction
    let tensor = smoothTensor(uv, pixelSize);
    let Jxx = tensor.x;
    let Jyy = tensor.y;
    let Jxy = tensor.z;
    let trace = Jxx + Jyy;
    let det = Jxx * Jyy - Jxy * Jxy;
    let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
    let lambda1 = (trace + diff) * 0.5;
    var eigenvec = vec2<f32>(1.0, 0.0);
    if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
        eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
    }

    // Mouse vortex disturbance
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0);
    let mouseAngle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
    let vortex = vec2<f32>(-sin(mouseAngle), cos(mouseAngle)) * mouseFactor;
    eigenvec = normalize(mix(eigenvec, vortex, mouseFactor));

    // Ripple turbulence
    var rippleTurb = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rElapsed = time - ripple.z;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - ripple.xy);
            let wave = exp(-pow((rDist - rElapsed * 0.3) * 8.0, 2.0));
            let turbAngle = atan2(uv.y - ripple.xy.y, uv.x - ripple.xy.x) + rElapsed * 3.0;
            rippleTurb += vec2<f32>(cos(turbAngle), sin(turbAngle)) * wave * (1.0 - rElapsed / 3.0);
        }
    }
    eigenvec = normalize(eigenvec + rippleTurb * 2.0);

    // Wind vector follows texture flow
    let n = noise(uv * 10.0 + vec2<f32>(time));
    let turbOffset = (vec2<f32>(n) - 0.5) * turbulence * 0.05;
    let offset = eigenvec * strength + turbOffset;

    // Sample with wind offset
    var color = textureSampleLevel(readTexture, u_sampler, uv - offset, 0.0);

    // Chromatic aberration based on wind
    let redOffset = offset * (1.0 + shift * 5.0);
    let blueOffset = offset * (1.0 - shift * 5.0);
    let r = textureSampleLevel(readTexture, u_sampler, uv - redOffset, 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, uv - blueOffset, 0.0).b;
    color = vec4<f32>(r, color.g, b, color.a);

    // Feedback trail
    let historyUV = uv - offset * 0.5;
    let history = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0);
    let finalColor = mix(color, history, trails);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
