// ═══════════════════════════════════════════════════════════
// Shader: spec-cooperative-edge-linking
// Category: Image
// Features: cooperative-workgroup, edge-linking, segmentation, audio-reactive, upgraded-rgba
// Complexity: High
// Chunks From: noise.wgsl
// Created: 2026-04-18
// Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════
// Workgroup-Cooperative Edge Linking
// After detecting edges, uses workgroup shared memory to trace edge
// chains across the tile. Connected edges get the same edge ID.
// Audio reactivity modulates edge sensitivity and glow intensity.
// ═══════════════════════════════════════════════════════════

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

var<workgroup> edgeFlags: array<u32, 256>;
var<workgroup> edgeIds: array<u32, 256>;

// ═══ CHUNK: hash3 (from noise.wgsl) ═══
fn hash3(p: vec2<f32>) -> vec3<f32> {
  let q = vec3<f32>(dot(p, vec2<f32>(127.1, 311.7)),
                    dot(p, vec2<f32>(269.5, 183.3)),
                    dot(p, vec2<f32>(419.2, 371.9)));
  return fract(sin(q) * 43758.5453);
}
// ════════════════════════════════════════

fn hash12(p: vec2<f32>) -> f32 {
    return hash3(p).x;
}

const TAU: f32 = 6.28318530718;

@compute @workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(local_invocation_index) lidx: u32
) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let texel = 1.0 / res;
    let time = u.config.x;

    // Audio — read from plasmaBuffer[0].xyz as standard (bass, mids, treble)
    let audio  = plasmaBuffer[0].xyz;
    let bass   = audio.x;
    let mid    = audio.y;
    let treble = audio.z;

    // Params — audio-reactive modulation
    let edgeThreshold = mix(0.05, 0.4, u.zoom_params.x) * (1.0 - bass * 0.15);
    let linkRadius = mix(1.0, 3.0, u.zoom_params.y);
    let colorMode = u.zoom_params.z;
    let glowAmount = mix(0.0, 1.0, u.zoom_params.w) * (1.0 + treble * 0.2);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Sobel edge detection
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let c = src.rgb;
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
            let u_idx = lidx - 16u;
            let d = lidx + 16u;

            if (lx < 15u && edgeFlags[r] == 1u) { minId = min(minId, edgeIds[r]); }
            if (lx > 0u && edgeFlags[l] == 1u) { minId = min(minId, edgeIds[l]); }
            if (ly > 0u && lidx >= 16u && edgeFlags[u_idx] == 1u) { minId = min(minId, edgeIds[u_idx]); }
            if (ly < 15u && lidx < 240u && edgeFlags[d] == 1u) { minId = min(minId, edgeIds[d]); }

            edgeIds[lidx] = minId;
        }
        workgroupBarrier();
    }

    let myEdgeId = edgeIds[lidx];
    let edgeIdHash = hash12(vec2<f32>(f32(myEdgeId % 16u), f32(myEdgeId / 16u)));

    // Branchless color mode selection using select()
    let isMode0 = colorMode < 0.33;
    let isMode1 = colorMode >= 0.33 && colorMode < 0.66;

    // Mode 0: Edge-ID rainbow
    let hue0 = f32(myEdgeId) / 256.0 + time * 0.05;
    let edgeColor = vec3<f32>(
        0.5 + 0.5 * cos(TAU * (hue0 + 0.0)),
        0.5 + 0.5 * cos(TAU * (hue0 + 0.33)),
        0.5 + 0.5 * cos(TAU * (hue0 + 0.67))
    );
    let outColor0 = mix(c, edgeColor, f32(isEdge));

    // Mode 1: Gradient direction coloring
    let angle1 = atan2(gy.g, gx.g) / TAU + 0.5;
    let dirColor = vec3<f32>(
        0.5 + 0.5 * cos(TAU * angle1),
        0.5 + 0.5 * cos(TAU * (angle1 + 0.33)),
        0.5 + 0.5 * cos(TAU * (angle1 + 0.67))
    );
    let outColor1 = mix(c, dirColor, smoothstep(0.0, edgeThreshold * 2.0, gradMag));

    // Mode 2: Glow edges on original
    let edgeGlow = exp(-gradMag * gradMag * 4.0) * glowAmount;
    let glowColor = vec3<f32>(1.0, 0.9, 0.6) * edgeGlow;
    let outColor2 = c + glowColor * smoothstep(0.0, edgeThreshold * 2.0, gradMag);

    let outColor = select(
        select(outColor2, outColor1, isMode1),
        outColor0,
        isMode0
    );

    // Mouse interaction — branchless via select()
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = exp(-mouseDist * mouseDist * 1000.0);
    let mouseActive = isMouseDown && (isEdge == 1u) && (mouseInfluence > 0.01);
    let mouseBoost = select(vec3<f32>(0.0), vec3<f32>(0.3, 0.6, 1.0) * mouseInfluence, mouseActive);
    let finalRGB = outColor + mouseBoost;

    // Proper alpha computation — source alpha blended with edge presence
    let alpha = saturate(src.a * (0.3 + f32(isEdge) * 0.7 + gradMag * 0.5));

    textureStore(writeTexture, gid.xy, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(gradMag, f32(myEdgeId) / 256.0, f32(isEdge), alpha));
}
