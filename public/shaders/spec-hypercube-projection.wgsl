// ═══════════════════════════════════════════════════════════════════
//  spec-hypercube-projection
//  Category: geometric
//  Features: 4D, hypercube, tesseract, projection
//  Complexity: High
//  Chunks From: chunk-library (hash22)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Animated 4D Hypercube (Tesseract) Projection
//  Renders a 4D tesseract projected into 2D using double rotation
//  (one in XW plane, one in YZ). Input image texture-mapped onto faces.
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

fn rotate4D_XW(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(c*p.x + s*p.w, p.y, p.z, -s*p.x + c*p.w);
}

fn rotate4D_YZ(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(p.x, c*p.y + s*p.z, -s*p.y + c*p.z, p.w);
}

fn rotate4D_XY(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(c*p.x - s*p.y, s*p.x + c*p.y, p.z, p.w);
}

fn project4DTo2D(p: vec4<f32>) -> vec2<f32> {
    let perspective = 1.5 / (2.5 - p.w);
    return p.xy * perspective;
}

fn lineSDF(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let rotSpeedXW = mix(0.1, 1.0, u.zoom_params.x);
    let rotSpeedYZ = mix(0.05, 0.8, u.zoom_params.y);
    let edgeGlow = mix(0.002, 0.015, u.zoom_params.z);
    let faceOpacity = mix(0.0, 0.6, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Mouse adds extra rotation when pressed
    var extraRot = 0.0;
    if (isMouseDown) {
        extraRot = (mousePos.x - 0.5) * 2.0;
    }

    // 4D Tesseract vertices (±1, ±1, ±1, ±1)
    var verts4D = array<vec4<f32>, 16>();
    var idx = 0;
    for (var x = -1; x <= 1; x = x + 2) {
        for (var y = -1; y <= 1; y = y + 2) {
            for (var z = -1; z <= 1; z = z + 2) {
                for (var w = -1; w <= 1; w = w + 2) {
                    verts4D[idx] = vec4<f32>(f32(x), f32(y), f32(z), f32(w)) * 0.35;
                    idx = idx + 1;
                }
            }
        }
    }

    // Rotate all vertices
    var verts2D = array<vec2<f32>, 16>();
    var depths = array<f32, 16>();
    let angXW = time * rotSpeedXW + extraRot;
    let angYZ = time * rotSpeedYZ * 0.7;
    let angXY = time * 0.15;

    for (var i = 0; i < 16; i = i + 1) {
        var v = verts4D[i];
        v = rotate4D_XW(v, angXW);
        v = rotate4D_YZ(v, angYZ);
        v = rotate4D_XY(v, angXY);
        verts2D[i] = project4DTo2D(v);
        depths[i] = v.w;
    }

    // Center on screen
    let screenUV = (uv - 0.5) * 2.0;

    // Edge list for tesseract (32 edges)
    // Each vertex connects to 4 others (differ by one coordinate)
    var minEdgeDist = 1000.0;
    var edgeDepth = 0.0;
    var edgeCount = 0.0;

    for (var i = 0; i < 16; i = i + 1) {
        for (var j = i + 1; j < 16; j = j + 1) {
            // Check if vertices differ by exactly one coordinate
            let diff = abs(verts4D[i] - verts4D[j]);
            var diffs = 0;
            if (diff.x > 0.1) { diffs = diffs + 1; }
            if (diff.y > 0.1) { diffs = diffs + 1; }
            if (diff.z > 0.1) { diffs = diffs + 1; }
            if (diff.w > 0.1) { diffs = diffs + 1; }

            if (diffs == 1) {
                let d = lineSDF(screenUV, verts2D[i], verts2D[j]);
                if (d < minEdgeDist) {
                    minEdgeDist = d;
                    edgeDepth = (depths[i] + depths[j]) * 0.5;
                }
                edgeCount = edgeCount + 1.0;
            }
        }
    }

    // Sample input image for texture mapping
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Edge glow
    let glow = exp(-minEdgeDist * minEdgeDist / (edgeGlow * edgeGlow));
    let depthFade = 1.0 - smoothstep(-0.5, 0.5, edgeDepth);

    // Color edges by depth
    let edgeHue = edgeDepth * 0.3 + time * 0.05;
    let edgeColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * (edgeHue + 0.0)),
        0.5 + 0.5 * cos(6.28318 * (edgeHue + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (edgeHue + 0.67))
    );

    // Face filling (simplified: radial fill from projected center)
    let center2D = project4DTo2D(vec4<f32>(0.0));
    let distFromCenter = length(screenUV - center2D);
    let faceFill = smoothstep(0.7, 0.3, distFromCenter) * faceOpacity * (1.0 - glow * 0.5);

    var outColor = baseColor * (1.0 - faceFill) + baseColor * edgeColor * faceFill;
    outColor = outColor + edgeColor * glow * depthFade * 2.0;

    // Tone map
    outColor = outColor / (1.0 + outColor * 0.3);

    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, glow * depthFade));
    textureStore(dataTextureA, gid.xy, vec4<f32>(edgeColor, edgeDepth));
}
