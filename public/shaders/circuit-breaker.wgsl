// ═══════════════════════════════════════════════════════════════════
//  Circuit Breaker
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17, 2026-11-15
//  Ideas: annular via pads & 45-degree routed edge traces; Schmitt-trigger breaker latch (§12.2B)
//  A packing: ACES display RGB + Schmitt-trigger trip bit in A.a
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv    = vec2<f32>(global_id.xy) / resolution;
    let time  = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let gridScale     = mix(20.0, 100.0, u.zoom_params.x);
    let intensity     = u.zoom_params.y;
    let jitterStrength = u.zoom_params.z;
    let edgeThreshold = u.zoom_params.w;

    // Mouse interaction
    let mouse        = u.zoom_config.yz;
    let aspectRatio  = resolution.x / max(resolution.y, 0.001);
    let uv_corrected = vec2<f32>(uv.x * aspectRatio, uv.y);
    let mouse_corrected = vec2<f32>(mouse.x * aspectRatio, mouse.y);
    let dist         = distance(uv_corrected, mouse_corrected);

    let hasMouse = step(0.001, mouse.x + mouse.y);
    // Bass boosts influence radius and strength
    let baseInfluence = smoothstep(0.4, 0.0, dist) * hasMouse * (1.0 + intensity * 2.0);
    let influence     = baseInfluence * (1.0 + bass * 0.5);

    // Grid generation
    let gridUV  = uv * gridScale;
    let gridID  = floor(gridUV);
    let gridLine = smoothstep(0.95, 1.0, fract(gridUV.x)) + smoothstep(0.95, 1.0, fract(gridUV.y));
    let isGrid  = clamp(gridLine, 0.0, 1.0);

    // Circuit nodes
    let node = step(0.9, hash21(gridID));

    // Branchless jitter: apply displacement proportional to influence, clamped to [0,1]
    let jitterActive = step(0.001, influence);
    let jitter = (vec2<f32>(hash21(uv + time), hash21(uv + time + 10.0)) - 0.5)
                 * jitterStrength * influence * 0.1 * jitterActive;
    let sampleUV = clamp(uv + jitter, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample texture
    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Edge detection
    let offset = 1.0 / resolution;
    let left  = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(offset.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up    = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down  = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.0, offset.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lumaWeights = vec3<f32>(0.299, 0.587, 0.114);
    let lumaL = dot(left.rgb,  lumaWeights);
    let lumaR = dot(right.rgb, lumaWeights);
    let lumaU = dot(up.rgb,    lumaWeights);
    let lumaD = dot(down.rgb,  lumaWeights);

    let edgeX = lumaL - lumaR;
    let edgeY = lumaU - lumaD;
    let edge  = sqrt(edgeX * edgeX + edgeY * edgeY);

    let isEdge = step(edgeThreshold, edge);

    // ── Idea 1: annular solder-via pads & 45-degree routed PCB edge traces ──
    let cellLocal = fract(gridUV) - 0.5;
    let padDist = length(cellLocal);
    let viaRing = smoothstep(0.35, 0.26, padDist) * smoothstep(0.08, 0.15, padDist) * node;
    let drillHole = smoothstep(0.12, 0.06, padDist) * node;

    let octAngle = round(atan2(edgeX, -edgeY) / 0.78539816) * 0.78539816;
    let traceDir = vec2<f32>(cos(octAngle), sin(octAngle));
    let traceCross = abs(dot(cellLocal, vec2<f32>(-traceDir.y, traceDir.x)));
    let routedTrace = isEdge * mix(0.45, 1.0, smoothstep(0.24, 0.08, traceCross));
    let busPacket = (0.5 + 0.5 * sin(dot(gridUV, traceDir) * 3.4 - time * (6.5 + mids * 5.0) + hash21(gridID) * 6.28318)) * routedTrace;

    // ── Idea 2: Schmitt-trigger breaker latch per PCB cell (§12.2B) ─────────
    let resI = vec2<i32>(resolution);
    let cellCenterUV = clamp((gridID + 0.5) / gridScale, vec2<f32>(0.0), vec2<f32>(0.9999));
    let cellCoord = clamp(vec2<i32>(cellCenterUV * resolution), vec2<i32>(0), resI - vec2<i32>(1));
    let prevCell = textureLoad(dataTextureC, cellCoord, 0);
    let prevPixel = textureLoad(dataTextureC, coord, 0);
    let lockPrev = step(0.5, prevCell.a);
    let cellRating = 0.72 + 0.28 * hash21(gridID + vec2<f32>(3.7, 9.1));
    let overloadDrive = influence / cellRating;
    let tripHi = 0.88 - intensity * 0.34;
    let tripLo = max(tripHi - 0.30, 0.08);
    var tripped = lockPrev;
    tripped = select(tripped, 1.0, overloadDrive > tripHi);
    tripped = select(tripped, 0.0, overloadDrive < tripLo);
    let tripOnset = max(tripped - lockPrev, 0.0);

    // Circuit glow colors — bass tints toward overload; tripped cells open-circuit to charred copper
    let circuitColor = vec3<f32>(0.0, 0.8, 0.2);
    let overloadColor = vec3<f32>(0.5, 0.8, 1.0);
    let charredCopper = vec3<f32>(0.22, 0.09, 0.04);
    let liveGlow = mix(circuitColor, overloadColor, clamp(influence + bass * 0.3 + busPacket * 0.35, 0.0, 1.0));
    let glow = mix(liveGlow, charredCopper, tripped * 0.82) * (1.0 + busPacket * 0.45 * (1.0 - tripped));

    // Branchless edge/grid/via blend
    let applyGlow = clamp(routedTrace + isGrid + viaRing, 0.0, 1.0);
    let glowBlend = 0.5 + influence * 0.5;
    var colorAfterGlow = mix(color.rgb, mix(color.rgb, glow, glowBlend), applyGlow);
    colorAfterGlow *= 1.0 - drillHole * 0.85;

    // Branchless node flash on copper via ring + arc burst when breaker trips
    let flashActive = step(0.5, influence) * viaRing;
    let flash = sin(time * (20.0 + treble * 10.0) + hash21(gridID) * 6.28318) * 0.5 + 0.5;
    let tripArc = (viaRing + isGrid * 0.35) * (tripOnset * 2.4 + tripped * flash * 0.55);
    var hdrRGB = mix(colorAfterGlow, vec3<f32>(1.0, 0.98, 0.92), clamp(flash * influence * flashActive, 0.0, 1.0));
    hdrRGB += vec3<f32>(0.55, 0.88, 1.35) * tripArc;
    hdrRGB = mix(hdrRGB, max(hdrRGB, prevPixel.rgb * 0.84), tripped * 0.28);

    // Scanline + ACES display mapping
    let scanline = sin(uv.y * resolution.y * 0.5) * 0.08;
    let finalRGB = aces(max(hdrRGB - scanline, vec3<f32>(0.0)));

    // Meaningful alpha: edge strength + grid/via presence + influence + breaker state
    let alpha = clamp(color.a * 0.2 + edge * 2.0 + (isGrid + viaRing) * 0.3 + influence * 0.35 + tripped * 0.2 + bass * 0.15, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));

    // Depth pass-through & Schmitt latch stored in A.a
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, tripped));
}
