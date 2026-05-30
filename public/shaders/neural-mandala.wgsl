// ═══════════════════════════════════════════════════════════════════
//  Neural Mandala
//  Category: generative
//  Features: generative, audio-reactive, geometric-recursion, pulsing-nodes, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
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

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let ringCount = 4 + i32(u.zoom_params.x * 8.0);
    let complexity = u.zoom_params.y;
    let pulseSpeed = u.zoom_params.z * 3.0;
    let connectionDensity = u.zoom_params.w;

    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let dist = length(p);
    let angle = atan2(p.y, p.x);

    var color = vec3<f32>(0.02, 0.01, 0.04);
    var glow = 0.0;

    for (var ri = 0; ri < ringCount; ri = ri + 1) {
        let r = f32(ri);
        let radius = 0.05 + r * 0.06;
        let ringPulse = sin(time * pulseSpeed + r * 1.3) * 0.5 + 0.5;
        let ringWidth = 0.003 * (1.0 + ringPulse * bass);

        let ringMask = smoothstep(radius + ringWidth, radius, dist) * smoothstep(radius - ringWidth, radius, dist);

        // Nodes on ring
        let nodeCount = 4 + i32(r * complexity * 8.0);
        for (var ni = 0; ni < nodeCount; ni = ni + 1) {
            let nodeAngle = f32(ni) / f32(nodeCount) * 6.28318530718 + time * 0.1 * (0.5 + r * 0.1);
            let nodePos = vec2<f32>(cos(nodeAngle), sin(nodeAngle)) * radius;
            let nodeDist = length(p - nodePos);
            let nodeSize = 0.008 * (1.0 + bass * 0.5) * (1.0 + ringPulse);
            let nodeGlow = smoothstep(nodeSize * 2.0, 0.0, nodeDist);

            // Connections to next ring
            if (ri < ringCount - 1) {
                let nextRadius = radius + 0.06;
                let nextNodeCount = nodeCount + 2;
                let nextAngle = f32(ni) / f32(nextNodeCount) * 6.28318530718 + time * 0.08 * (0.5 + (r + 1.0) * 0.1);
                let nextPos = vec2<f32>(cos(nextAngle), sin(nextAngle)) * nextRadius;
                let lineDir = nextPos - nodePos;
                let lineLen = length(lineDir);
                let lineDirNorm = lineDir / max(lineLen, 0.0001);
                let toPixel = p - nodePos;
                let proj = clamp(dot(toPixel, lineDirNorm), 0.0, lineLen);
                let closest = nodePos + lineDirNorm * proj;
                let lineDist = length(p - closest);
                let lineGlow = smoothstep(0.003 * (1.0 + connectionDensity), 0.0, lineDist);
                color = color + vec3<f32>(0.3, 0.6, 1.0) * lineGlow * connectionDensity * mids;
                glow = glow + lineGlow * connectionDensity;
            }

            let hue = fract(r * 0.08 + time * 0.02 + bass * 0.05);
            let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
            let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
            let nodeColor = clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));

            color = color + nodeColor * nodeGlow * (0.8 + treble * 0.4);
            glow = glow + nodeGlow;
        }

        color = color + vec3<f32>(0.2, 0.5, 0.9) * ringMask * (0.3 + mids * 0.3);
        glow = glow + ringMask * 0.3;
    }

    let alpha = clamp(glow * 0.6 + 0.15 + bass * 0.05, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(glow * 0.3, 0.0, 0.0, 0.0));
}
