// ═══════════════════════════════════════════════════════════════════
//  spec-cooperative-edge-linking
//  Category: image
//  Features: cooperative-workgroup, edge-linking, segmentation
//  Complexity: High
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Workgroup-Cooperative Edge Linking
//  After detecting edges, uses workgroup shared memory to trace edge
//  chains across the tile. Connected edges get the same edge ID.
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

var<workgroup> edgeFlags: array<u32, 64>;
var<workgroup> edgeIds: array<u32, 64>;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(local_invocation_index) lidx: u32
) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let texel = 1.0 / res;
    let time = u.config.x;

    let edgeThreshold = mix(0.05, 0.4, u.zoom_params.x);
    let linkRadius = mix(1.0, 3.0, u.zoom_params.y);
    let colorMode = u.zoom_params.z;
    let glowAmount = mix(0.0, 1.0, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Sobel edge detection
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let cxp = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;
    let cxm = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rgb;
    let cyp = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
    let cym = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).rgb;

    let gx = (cxp - cxm) * 0.5;
    let gy = (cyp - cym) * 0.5;
    let gradMag = length(gx) + length(gy);

    let isEdge = select(0u, 1u, gradMag > edgeThreshold);

    // Store in shared memory
    edgeFlags[lidx] = isEdge;
    edgeIds[lidx] = lidx; // Initially each edge is its own component
    workgroupBarrier();

    // Union-Find style linking within workgroup
    // Iteratively link connected edges (4-connectivity)
    for (var iter = 0; iter < 3; iter = iter + 1) {
        workgroupBarrier();
        if (isEdge == 1u) {
            let lx = lid.x;
            let ly = lid.y;
            var minId = edgeIds[lidx];

            // Check neighbors
            let r = lidx + 1u;
            let l = lidx - 1u;
            let u_idx = lidx - 8u;
            let d = lidx + 8u;

            if (lx < 7u && edgeFlags[r] == 1u) { minId = min(minId, edgeIds[r]); }
            if (lx > 0u && edgeFlags[l] == 1u) { minId = min(minId, edgeIds[l]); }
            if (ly > 0u && lidx >= 8u && edgeFlags[u_idx] == 1u) { minId = min(minId, edgeIds[u_idx]); }
            if (ly < 7u && lidx < 56u && edgeFlags[d] == 1u) { minId = min(minId, edgeIds[d]); }

            edgeIds[lidx] = minId;
        }
        workgroupBarrier();
    }

    let myEdgeId = edgeIds[lidx];
    let edgeIdHash = hash12(vec2<f32>(f32(myEdgeId % 16u), f32(myEdgeId / 16u)));

    // Color based on edge ID or gradient direction
    var outColor: vec3<f32>;
    if (colorMode < 0.33) {
        // Edge-ID rainbow
        let hue = f32(myEdgeId) / 64.0 + time * 0.05;
        let edgeColor = vec3<f32>(
            0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
            0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
        );
        outColor = mix(c, edgeColor, f32(isEdge));
    } else if (colorMode < 0.66) {
        // Gradient direction coloring
        let angle = atan2(gy.g, gx.g) / 6.28318 + 0.5;
        let dirColor = vec3<f32>(
            0.5 + 0.5 * cos(6.28318 * angle),
            0.5 + 0.5 * cos(6.28318 * (angle + 0.33)),
            0.5 + 0.5 * cos(6.28318 * (angle + 0.67))
        );
        outColor = mix(c, dirColor, smoothstep(0.0, edgeThreshold * 2.0, gradMag));
    } else {
        // Glow edges on original
        let edgeGlow = exp(-gradMag * gradMag * 4.0) * glowAmount;
        let glowColor = vec3<f32>(1.0, 0.9, 0.6) * edgeGlow;
        outColor = c + glowColor * smoothstep(0.0, edgeThreshold * 2.0, gradMag);
    }

    // Mouse interaction: highlight edges near mouse
    if (isMouseDown) {
        let mouseDist = length(uv - mousePos);
        let mouseInfluence = exp(-mouseDist * mouseDist * 1000.0);
        if (isEdge == 1u && mouseInfluence > 0.01) {
            outColor += vec3<f32>(0.3, 0.6, 1.0) * mouseInfluence;
        }
    }

    // Alpha stores edge ID / chain identifier
    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, f32(myEdgeId) / 64.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(gradMag, f32(myEdgeId) / 64.0, f32(isEdge), 1.0));
}
