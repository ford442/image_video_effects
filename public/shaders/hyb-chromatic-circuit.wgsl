// ═══════════════════════════════════════════════════════════════════
//  hyb-chromatic-circuit
//  Category: hybrid
//  Features: hex-grid, trace-edges, chromatic-aberration, pulse-glow,
//            alpha-passthrough, depth-passthrough, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-10, 2026-11-20
//  Ideas: neighbor-gated traces; traveling packet along segment h; via pads with annular ring and drill (PCB via, pad grows with node degree); copper-ridge bevel under solder mask (SDF cross-section normal, §12.2E)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn nearestHexCenter(uv: vec2<f32>, scale: f32) -> vec2<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let uvScaled = uv * scale;
    let uvA = uvScaled / r;
    let idA = floor(uvA + 0.5);
    let uvB = (uvScaled - h) / r;
    let idB = floor(uvB + 0.5);
    let centerA = idA * r;
    let centerB = idB * r + h;
    let distA = distance(uvScaled, centerA);
    let distB = distance(uvScaled, centerB);
    return select(centerB, centerA, distA < distB);
}

fn sdSegment2(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return vec2<f32>(length(pa - ba * h), h);
}

fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / max(radius * radius, 1e-6)) * intensity;
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
    return v * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

fn neighborGate(center: vec2<f32>, offset: vec2<f32>, r: vec2<f32>) -> f32 {
    let nid = floor((center + offset) / r);
    return step(0.35, hash12(nid + vec2<f32>(37.0, 17.0)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let coord = vec2<i32>(gid.xy);
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
        return;
    }

    let uv = (vec2<f32>(coord) + 0.5) / dims;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
    let gridScale = mix(4.0, 32.0, zp.x);
    let traceWidth = mix(0.02, 0.12, zp.y);
    let chromaSpread = mix(0.0, 0.05, zp.z);
    let effectMix = mix(0.0, 1.0, zp.w);

    let hexUV = uv * gridScale;
    let center = nearestHexCenter(uv, gridScale);
    let local = hexUV - center;

    let r = vec2<f32>(1.0, 1.7320508);
    let q = abs(local);
    let hexDist = max(q.x * 0.5 + q.y * 0.866025, q.x);
    let edgeDist = 0.5 - hexDist;
    let hexEdge = 1.0 - smoothstep(0.0, 0.08, edgeDist);

    let cellId = floor(center / r);
    let rnd = hash12(cellId + vec2<f32>(37.0, 17.0));
    let selfGate = step(0.35, rnd);

    let n0 = vec2<f32>(1.0, 0.0);
    let n1 = vec2<f32>(0.5, 0.866025);
    let n2 = vec2<f32>(-0.5, 0.866025);
    let n3 = vec2<f32>(-1.0, 0.0);
    let n4 = vec2<f32>(-0.5, -0.866025);
    let n5 = vec2<f32>(0.5, -0.866025);

    let s0 = sdSegment2(hexUV, center, center + n0);
    let s1 = sdSegment2(hexUV, center, center + n1);
    let s2 = sdSegment2(hexUV, center, center + n2);
    let s3 = sdSegment2(hexUV, center, center + n3);
    let s4 = sdSegment2(hexUV, center, center + n4);
    let s5 = sdSegment2(hexUV, center, center + n5);

    let g0 = selfGate * neighborGate(center, n0, r);
    let g1 = selfGate * neighborGate(center, n1, r);
    let g2 = selfGate * neighborGate(center, n2, r);
    let g3 = selfGate * neighborGate(center, n3, r);
    let g4 = selfGate * neighborGate(center, n4, r);
    let g5 = selfGate * neighborGate(center, n5, r);

    var traceMask = 0.0;
    var pulseGlow = 0.0;
    var packet = 0.0;
    var bevel = 0.0;
    let pulsePhase = time * 1.5 + cellId.x * 0.7 + cellId.y * 0.5;
    let pulse = 0.5 + 0.5 * sin(pulsePhase);
    let packetHead = fract(time * (0.55 + treble * 0.35) + rnd);

    let segs = array<vec3<f32>, 6>(
        vec3<f32>(s0.x, s0.y, g0),
        vec3<f32>(s1.x, s1.y, g1),
        vec3<f32>(s2.x, s2.y, g2),
        vec3<f32>(s3.x, s3.y, g3),
        vec3<f32>(s4.x, s4.y, g4),
        vec3<f32>(s5.x, s5.y, g5)
    );
    let dirs = array<vec2<f32>, 6>(n0, n1, n2, n3, n4, n5);
    // Fixed key light for the solder-mask relief (uv has y down, so this is upper-left).
    let lightDir = vec2<f32>(-0.7071068, -0.7071068);
    for (var i = 0; i < 6; i = i + 1) {
        let dist = segs[i].x;
        let h = segs[i].y;
        let gate = segs[i].z;
        let m = (1.0 - smoothstep(0.0, traceWidth, dist)) * gate;
        // ── Idea 2: copper-ridge bevel. The pixel's offset from this segment's centreline
        // (local - n*h) is the cross-section direction of the trace; the ridge height is the
        // trace profile itself, whose slope 4t(1-t) peaks at half-width. Lit side > 0.
        let off = (local - dirs[i] * h) / max(dist, 1e-4);
        let tw = clamp(dist / max(traceWidth, 1e-4), 0.0, 1.0);
        let ridge = dot(off, lightDir) * 4.0 * tw * (1.0 - tw);
        bevel = select(bevel, ridge, m > traceMask);
        traceMask = max(traceMask, m);
        pulseGlow = max(pulseGlow, glow(dist, traceWidth * 2.5, 1.2) * pulse * gate);
        packet = max(packet, exp(-abs(h - packetHead) * 14.0) * (1.0 - smoothstep(0.0, traceWidth * 1.4, dist)) * gate);
    }

    let texel = 1.0 / dims;
    let cR = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let cU = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let luma = dot(src.rgb, vec3<f32>(0.333));
    let lumaR = dot(cR, vec3<f32>(0.333));
    let lumaU = dot(cU, vec3<f32>(0.333));
    let dLx = luma - lumaR;
    let dLy = luma - lumaU;
    let imgEdge = sqrt(dLx * dLx + dLy * dLy); // rescue: pow(negative, 2.0) is undefined, squares are not
    let edgeBoost = smoothstep(0.05, 0.25, imgEdge);

    let grad = normalize(hexUV - center + vec2<f32>(1e-4));
    let rUV = clamp(uv + grad * chromaSpread, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - grad * chromaSpread, vec2<f32>(0.0), vec2<f32>(1.0));
    let chroma = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        src.g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    );

    let hue = fract(rnd * 0.2 + time * 0.08 + pulse * 0.15);
    let circuitCol = hsv2rgb(hue, 0.85, 1.0);
    // ── Idea 2 (apply): the lit shoulder of the ridge brightens, the shaded one dims,
    // and a short specular (bevel^4, squares only) rides the lit edge like mask sheen.
    let ridgeLit = 1.0 + 0.6 * bevel;
    let spec2 = max(bevel, 0.0) * max(bevel, 0.0);
    let sheen = vec3<f32>(1.0, 0.96, 0.88) * spec2 * spec2 * traceMask * 0.5;
    let traceCol = circuitCol * (traceMask * ridgeLit + pulseGlow * 0.6 + packet * (1.1 + bass * 0.4)) * (1.0 + edgeBoost * 1.5) + sheen;
    let hexFill = circuitCol * hexEdge * 0.12 * edgeBoost;

    // ── Idea 1: via pad with annular ring and drill at every live node. A node is live when
    // at least one gated trace leaves it (selfGate*neighborGate already counted in g0..g5);
    // the pad grows with how many traces land on it, the drill punches through the layer.
    let degree = g0 + g1 + g2 + g3 + g4 + g5;
    let nodeLive = step(0.5, degree);
    let nodeR = length(local);
    let aa = gridScale * 1.5 / max(dims.y, 1.0);
    let padR = traceWidth * (1.9 + 0.1 * degree);
    let drillR = padR * 0.42;
    let padDisc = 1.0 - smoothstep(padR - aa, padR + aa, nodeR);
    let drillDisc = 1.0 - smoothstep(drillR - aa, drillR + aa, nodeR);
    let annulus = max(padDisc - drillDisc, 0.0) * nodeLive;
    let hole = drillDisc * nodeLive;
    let padRim = smoothstep(padR - 3.0 * aa, padR - aa, nodeR) * annulus;
    let launch = exp(-packetHead * 7.0) * (1.0 + bass * 0.4); // flare while a packet leaves this pad
    let padCol = circuitCol * annulus * (0.85 + 0.5 * pulse + launch) + vec3<f32>(1.0, 0.96, 0.88) * padRim * 0.18;

    var layerRGB = clamp(chroma + traceCol + hexFill + padCol, vec3<f32>(0.0), vec3<f32>(4.0));
    layerRGB = mix(layerRGB, src.rgb * 0.25, hole); // drill: the photo shows through, darkened
    let outRGB = mix(src.rgb, layerRGB, effectMix);
    let alpha = clamp(src.a + traceMask * 0.25 + packet * 0.2 + annulus * 0.25, 0.0, 1.0);
    let outColor = vec4<f32>(acesToneMap(outRGB), alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);
    // Depth: HEAD packet bump kept; raised copper (trace + pad) and the drilled hole are truthful relief.
    let relief = traceMask * 0.01 + annulus * 0.02 - hole * 0.02;
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth + packet * 0.03 + relief, 0.0, 1.0), 0.0, 0.0, 0.0));
}
