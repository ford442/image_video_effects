// ═══════════════════════════════════════════════════════════════════
//  ASCII Flow + Structure Tensor
//  Category: advanced-hybrid
//  Features: advanced-convolution, upgraded-rgba, mouse-driven
//  Complexity: High
//  Chunks From: ascii-flow.wgsl, conv-structure-tensor-flow.wgsl
//  Created: 2026-04-18
//  By: Agent CB-10 — Image Processing & Artistry Enhancer
// ═══════════════════════════════════════════════════════════════════
//
//  Hybrid Approach:
//    1. Compute structure tensor and extract dominant eigenvector (flow direction)
//    2. Use flow coherency to determine glyph selection and orientation
//    3. High coherency = line glyphs aligned with edge flow
//    4. Low coherency = dot/cross glyphs
//    5. Line Integral Convolution (LIC) value modulates glyph brightness
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Flow-aligned glyph color with phosphor tint
//    Alpha: Structure tensor coherency — how strongly oriented the flow is.
//           High coherency = solid glyph, low coherency = ghosted glyph.
//
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: sampleLuma (from conv-structure-tensor-flow.wgsl) ═══
fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
    let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
    return dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

// ═══ CHUNK: structureTensor (from conv-structure-tensor-flow.wgsl) ═══
fn structureTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
    let gx =
        -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
        -2.0 * sampleLuma(uv, pixelSize, -1,  0) +
        -1.0 * sampleLuma(uv, pixelSize, -1,  1) +
         1.0 * sampleLuma(uv, pixelSize,  1, -1) +
         2.0 * sampleLuma(uv, pixelSize,  1,  0) +
         1.0 * sampleLuma(uv, pixelSize,  1,  1);
    let gy =
        -1.0 * sampleLuma(uv, pixelSize, -1, -1) +
        -2.0 * sampleLuma(uv, pixelSize,  0, -1) +
        -1.0 * sampleLuma(uv, pixelSize,  1, -1) +
         1.0 * sampleLuma(uv, pixelSize, -1,  1) +
         2.0 * sampleLuma(uv, pixelSize,  0,  1) +
         1.0 * sampleLuma(uv, pixelSize,  1,  1);
    let Ix2 = gx * gx;
    let Iy2 = gy * gy;
    let Ixy = gx * gy;
    return vec4<f32>(Ix2, Iy2, Ixy, 0.0);
}

// ═══ CHUNK: smoothTensor (from conv-structure-tensor-flow.wgsl) ═══
fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
    var sum = vec4<f32>(0.0);
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            sum += structureTensor(uv + offset, pixelSize);
        }
    }
    return sum / 9.0;
}

// ═══ CHUNK: lic (from conv-structure-tensor-flow.wgsl) ═══
fn lic(uv: vec2<f32>, direction: vec2<f32>, pixelSize: vec2<f32>, steps: i32, stepSize: f32) -> f32 {
    var pos = uv;
    var accum = 0.0;
    var weight = 0.0;
    for (var i = 0; i < steps; i++) {
        let lum = dot(textureSampleLevel(readTexture, u_sampler, pos, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
        let w = 1.0 - f32(i) / f32(steps);
        accum += lum * w;
        weight += w;
        pos += direction * stepSize * pixelSize;
    }
    pos = uv;
    for (var i = 0; i < steps; i++) {
        let lum = dot(textureSampleLevel(readTexture, u_sampler, pos, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
        let w = 1.0 - f32(i) / f32(steps);
        accum += lum * w;
        weight += w;
        pos -= direction * stepSize * pixelSize;
    }
    return accum / max(weight, 0.001);
}

// ═══ CHUNK: draw_glyph (from ascii-flow.wgsl, modified) ═══
fn draw_glyph(uv: vec2<f32>, index: i32, rotation: f32) -> f32 {
    // Rotate UV by flow direction
    let c = cos(rotation);
    let s = sin(rotation);
    let rotUV = vec2<f32>(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
    let p = rotUV - 0.5;
    var d = 1.0;

    // 0: Dot
    if (index == 0) {
        d = length(p) - 0.2;
    }
    // 1: Vertical Line
    else if (index == 1) {
        d = abs(p.x) - 0.1;
    }
    // 2: Horizontal Line
    else if (index == 2) {
        d = abs(p.y) - 0.1;
    }
    // 3: Plus
    else if (index == 3) {
        d = min(abs(p.x), abs(p.y)) - 0.08;
    }
    // 4: Diagonal /
    else if (index == 4) {
        d = abs(p.x + p.y) - 0.1;
    }
    // 5: Diagonal \
    else if (index == 5) {
        d = abs(p.x - p.y) - 0.1;
    }
    // 6: X
    else if (index == 6) {
        d = min(abs(p.x + p.y), abs(p.x - p.y)) - 0.08;
    }
    // 7: Box
    else {
        d = max(abs(p.x), abs(p.y)) - 0.4;
        d = abs(d) - 0.05;
    }

    return 1.0 - smoothstep(0.0, 0.05, d);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let pixelSize = 1.0 / resolution;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let gridDensity = mix(40.0, 120.0, u.zoom_params.x);
    let coherencyBoost = mix(0.5, 3.0, u.zoom_params.y);
    let licBlend = u.zoom_params.z;
    let mouseInfluence = u.zoom_params.w;

    // Grid Setup
    let grid_dims = vec2<f32>(gridDensity, gridDensity * resolution.y / resolution.x);
    let cell_uv = fract(uv * grid_dims);
    let cell_id = floor(uv * grid_dims);
    let cell_center_uv = (cell_id + 0.5) / grid_dims;

    // Compute structure tensor
    let tensor = smoothTensor(cell_center_uv, pixelSize);
    let Jxx = tensor.x;
    let Jyy = tensor.y;
    let Jxy = tensor.z;

    // Eigenvalues
    let trace = Jxx + Jyy;
    let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
    let lambda1 = (trace + diff) * 0.5;
    let lambda2 = (trace - diff) * 0.5;

    // Dominant eigenvector (flow direction)
    var eigenvec = vec2<f32>(1.0, 0.0);
    if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
        eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
    }

    // Coherency: how strongly oriented
    let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);
    let boostedCoherency = pow(coherency, 1.0 / coherencyBoost);

    // Mouse vortex disturbance
    let toMouse = cell_center_uv - mousePos;
    let mouseDist = length(toMouse);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * mouseInfluence;
    let mouseAngle = atan2(toMouse.y, toMouse.x);
    let vortex = vec2<f32>(-sin(mouseAngle), cos(mouseAngle)) * mouseFactor;
    eigenvec = normalize(mix(eigenvec, vortex, mouseFactor));

    // Flow angle for glyph rotation
    let flowAngle = atan2(eigenvec.y, eigenvec.x);

    // LIC along the flow
    let licValue = lic(cell_center_uv, eigenvec, pixelSize, 8, 1.5);

    // Sample texture for brightness
    let color = textureSampleLevel(readTexture, u_sampler, clamp(cell_center_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let gray = dot(color, vec3<f32>(0.299, 0.587, 0.114));

    // Glyph selection based on brightness + coherency
    // High coherency -> line-like glyphs (1-5), low -> dots/plus/box (0,3,7)
    var num_glyphs = 8;
    var glyph_idx = i32(gray * f32(num_glyphs));

    // If coherency is high, bias toward directional glyphs and rotate them
    var glyphRotation = 0.0;
    if (boostedCoherency > 0.6) {
        // Directional glyphs with flow alignment
        let dirGlyph = i32((flowAngle / 3.14159 + 1.0) * 2.5) % 5 + 1;
        glyph_idx = select(glyph_idx, dirGlyph, glyph_idx > 2);
        glyphRotation = flowAngle;
    }

    let shape = draw_glyph(cell_uv, glyph_idx, glyphRotation);

    // Color: phosphor green blended with flow-colored LIC
    let flowHue = flowAngle * 0.15915 + 0.5;
    let flowColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (flowHue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (flowHue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (flowHue + 0.67))
    );
    let phosphor = vec3<f32>(0.2, 1.0, 0.4);
    let mixedColor = mix(flowColor * (0.3 + 0.7 * licValue), phosphor, 0.5);
    let final_color = mixedColor * shape * (0.5 + 0.5 * gray);

    // Alpha based on coherency and shape
    let alpha = shape * mix(0.5, 1.0, boostedCoherency);

    // Store structure tensor for downstream
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(final_color, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(eigenvec, boostedCoherency, licValue));
}
