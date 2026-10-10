// ═══════════════════════════════════════════════════════════════════
//  Cooperative Edge Linking
//  Category: image
//  Features: cooperative-workgroup, edge-linking, segmentation, mouse-driven,
//            audio-reactive, upgraded-rgba, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: gap bridging (link_radius enables diagonal + distance-2 links, 3→9 passes, bridge pixels drawn); chain-size confidence via workgroup atomic member count; per-chain strobe on its own hash(id) rhythm driven by mids
//  A packing: diagnostic (gradMag, chainId/256, isEdge, alpha)
// ═══════════════════════════════════════════════════════════════════
// Workgroup-Cooperative Edge Linking
// After detecting edges, uses workgroup shared memory to trace edge
// chains across the tile. Connected edges get the same edge ID.
// Audio reactivity modulates edge sensitivity and glow intensity.
// Chunks From: noise.wgsl · Created 2026-04-18
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

var<workgroup> edgeFlags: array<u32, 256>;
var<workgroup> edgeIds: array<u32, 256>;
// Idea 2: members per root id, filled after the union passes.
var<workgroup> chainCount: array<atomic<u32>, 256>;

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

const TAU: f32 = 6.28318530718;

@compute @workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(local_invocation_index) lidx: u32
) {
    let res = u.config.zw;
    // FIX: no early return before the barriers — out-of-bounds threads take
    // part in every barrier as non-edges and skip only the final stores.
    let inBounds = gid.x < u32(res.x) && gid.y < u32(res.y);
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

    // Idea 1 (gap bridging): Link Radius was unused. >= 1.5 adds the four
    // diagonal neighbours, >= 2.0 (default) adds distance-2 links across a
    // one-pixel break, and the union passes scale 3 -> 9 with the slider.
    let linkDiag = linkRadius >= 1.5;
    let linkTwo = linkRadius >= 2.0;
    let linkPasses = i32(round(mix(3.0, 9.0, clamp(u.zoom_params.y, 0.0, 1.0))));

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

    let isEdge = select(0u, 1u, (gradMag > edgeThreshold) && inBounds);

    // Store in shared memory
    edgeFlags[lidx] = isEdge;
    edgeIds[lidx] = lidx; // Initially each edge is its own component
    atomicStore(&chainCount[lidx], 0u);
    workgroupBarrier();

    let lx = lid.x;
    let ly = lid.y;
    let r = lidx + 1u;
    let l = lidx - 1u;
    let u_idx = lidx - 16u;
    let d = lidx + 16u;

    // Idea 1: a non-edge pixel sitting in a one-pixel break between two edges
    // (left+right or up+down) is a bridge pixel; it is drawn at half strength
    // in the chain colour so the join is visible, not just an id merge.
    let hasL = lx > 0u && edgeFlags[l] == 1u;
    let hasR = lx < 15u && edgeFlags[r] == 1u;
    let hasU = ly > 0u && edgeFlags[u_idx] == 1u;
    let hasD = ly < 15u && edgeFlags[d] == 1u;
    let isBridge = linkTwo && isEdge == 0u && inBounds && ((hasL && hasR) || (hasU && hasD));

    // Union-Find style linking within workgroup
    // Iteratively link connected edges (4-connectivity, plus the bridging
    // neighbours when Link Radius enables them). Fixed 9-iteration loop so
    // the barriers sit in uniform control flow; passes beyond linkPasses are no-ops.
    for (var iter = 0; iter < 9; iter = iter + 1) {
        workgroupBarrier();
        if (isEdge == 1u && iter < linkPasses) {
            var minId = edgeIds[lidx];

            // Check neighbors
            if (lx < 15u && edgeFlags[r] == 1u) { minId = min(minId, edgeIds[r]); }
            if (lx > 0u && edgeFlags[l] == 1u) { minId = min(minId, edgeIds[l]); }
            if (ly > 0u && edgeFlags[u_idx] == 1u) { minId = min(minId, edgeIds[u_idx]); }
            if (ly < 15u && edgeFlags[d] == 1u) { minId = min(minId, edgeIds[d]); }

            if (linkDiag) {
                if (lx < 15u && ly > 0u && edgeFlags[u_idx + 1u] == 1u) { minId = min(minId, edgeIds[u_idx + 1u]); }
                if (lx > 0u && ly > 0u && edgeFlags[u_idx - 1u] == 1u) { minId = min(minId, edgeIds[u_idx - 1u]); }
                if (lx < 15u && ly < 15u && edgeFlags[d + 1u] == 1u) { minId = min(minId, edgeIds[d + 1u]); }
                if (lx > 0u && ly < 15u && edgeFlags[d - 1u] == 1u) { minId = min(minId, edgeIds[d - 1u]); }
            }
            if (linkTwo) {
                if (lx < 14u && edgeFlags[lidx + 2u] == 1u) { minId = min(minId, edgeIds[lidx + 2u]); }
                if (lx > 1u && edgeFlags[lidx - 2u] == 1u) { minId = min(minId, edgeIds[lidx - 2u]); }
                if (ly > 1u && edgeFlags[lidx - 32u] == 1u) { minId = min(minId, edgeIds[lidx - 32u]); }
                if (ly < 14u && edgeFlags[lidx + 32u] == 1u) { minId = min(minId, edgeIds[lidx + 32u]); }
            }

            edgeIds[lidx] = minId;
        }
        workgroupBarrier();
    }

    // A bridge pixel borrows the id of the chain it joins.
    var myEdgeId = edgeIds[lidx];
    if (isBridge) {
        myEdgeId = select(edgeIds[u_idx], edgeIds[l], hasL && hasR);
    }

    // Idea 2 (chain-size confidence): count members per root id, then read the
    // size of this pixel's chain. Long chains glow fully, fragments are dim.
    if (isEdge == 1u) {
        atomicAdd(&chainCount[myEdgeId], 1u);
    }
    workgroupBarrier();
    let chainSize = f32(atomicLoad(&chainCount[myEdgeId]));
    let confidence = smoothstep(2.0, 16.0, chainSize);
    let confGain = mix(0.35, 1.0, confidence);

    let edgeIdHash = hash12(vec2<f32>(f32(myEdgeId % 16u), f32(myEdgeId / 16u)));

    // Idea 3 (per-chain strobe): every chain flickers on its own rhythm
    // (rate and phase from hash(id)); mids deepen the flicker from a 10%
    // shimmer at idle to a hard strobe on a loud mix.
    let strobeRate = (1.5 + edgeIdHash * 4.0) * (1.0 + mid * 2.0);
    let strobeDepth = 0.10 + mid * 0.55;
    let strobe = 1.0 - strobeDepth * (0.5 + 0.5 * sin(time * strobeRate + edgeIdHash * TAU));

    // Edge presence for the overlays: full for edges, half for bridge pixels.
    let edgeMix = select(select(0.0, 0.5, isBridge), 1.0, isEdge == 1u);
    let chainGain = confGain * strobe;

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
    let outColor0 = mix(c, edgeColor * chainGain, edgeMix);

    // Mode 1: Gradient direction coloring
    let angle1 = atan2(gy.g, gx.g) / TAU + 0.5;
    let dirColor = vec3<f32>(
        0.5 + 0.5 * cos(TAU * angle1),
        0.5 + 0.5 * cos(TAU * (angle1 + 0.33)),
        0.5 + 0.5 * cos(TAU * (angle1 + 0.67))
    );
    let outColor1 = mix(c, dirColor * mix(1.0, chainGain, edgeMix), smoothstep(0.0, edgeThreshold * 2.0, gradMag));

    // Mode 2: Glow edges on original
    // FIX: HEAD's exp(-gradMag^2 * 4) peaked on flat areas; the glow now peaks
    // where the gradient sits on the threshold (band width ~0.1 in gradMag).
    let gradOff = gradMag - edgeThreshold;
    let edgeGlow = exp(-gradOff * gradOff * 50.0) * glowAmount;
    let glowColor = vec3<f32>(1.0, 0.9, 0.6) * edgeGlow * mix(1.0, chainGain, edgeMix);
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
    // ACES only where the neon runs hot; the untouched passthrough photo
    // (outColor == c on flat areas) keeps its HEAD tonality.
    let linRGB = clamp(outColor + mouseBoost, vec3<f32>(0.0), vec3<f32>(16.0));
    let hot = smoothstep(0.7, 1.5, max(linRGB.r, max(linRGB.g, linRGB.b)));
    let finalRGB = mix(linRGB, acesToneMap(linRGB), hot);

    // Proper alpha computation — source alpha blended with edge presence,
    // scaled by chain confidence so fragments are also less opaque.
    let alpha = saturate(src.a * (0.3 + edgeMix * 0.7 * confGain + gradMag * 0.5));

    if (!inBounds) { return; }
    textureStore(writeTexture, gid.xy, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(gradMag, f32(myEdgeId) / 256.0, f32(isEdge), alpha));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
