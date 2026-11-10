// ═══════════════════════════════════════════════════════════════════
//  Color Channel Weave
//  Category: image
//  Features: mouse-driven, click-reactive, audio-reactive, depth-aware, upgraded-rgba, semantic-alpha
//  Complexity: Medium
//  Upgraded: 2026-11-10
//  Ideas: two-ply yarn twist; exact-C under-thread ghost; Jacquard yarn-dye cells; slub yarn thickness/dye lots
//  A packing: display RGBA (leftover B kept)
// ═══════════════════════════════════════════════════════════════════
//  Samples R, G, and B channels from offset positions, creating the
//  visual illusion of woven fabric threads. Horizontal threads carry
//  red and blue; vertical threads carry green. Audio shifts the
//  thread spacing and weave angle. Mouse tilts the warp direction.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=ThreadSpacing, y=WeaveAngle, z=ShadowDepth, w=ChromaOffset

const PI: f32 = 3.14159265358979;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;

    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mid = audio.y;
    let treble = audio.z;

    // RESCUE: HEAD kept a spring in extraBuffer[133..138], which the host zeroes every
    // frame, so it always fell back to the raw pointer. Read the pointer directly.
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

    // Params
    let threadFreq  = mix(20.0, 120.0, u.zoom_params.x) * (1.0 + bass * 0.4);
    let weaveAngle  = mix(-0.4, 0.4,   u.zoom_params.y) + (mouse.x - 0.5) * 0.3;
    let shadowDepth = mix(0.0, 0.5,    u.zoom_params.z);
    let chromaOff   = mix(0.0, 0.008,  u.zoom_params.w) * (1.0 + treble);

    // Rotate UV for warp direction
    let cosA = cos(weaveAngle);
    let sinA = sin(weaveAngle);
    let ruv  = vec2<f32>(
        uv.x * cosA - uv.y * sinA,
        uv.x * sinA + uv.y * cosA
    );

    var pluck = 0.0;
    let aspect = dims.x / dims.y;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.2) {
            let radius = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            pluck += sin(radius * 55.0 - age * 16.0) * exp(-radius * 7.0 - age * 1.4);
        }
    }
    pluck = clamp(pluck, -1.0, 1.0);

    let warpPhase  = sin(ruv.x * threadFreq * PI + pluck * 0.8) * 0.5 + 0.5;
    let weftPhase  = sin(ruv.y * threadFreq * PI - pluck * 0.8) * 0.5 + 0.5;

    // Determine which thread is on top at each pixel
    // classic over-under weave: thread alternates every half-period
    let warpCell   = floor(ruv.x * threadFreq);
    let weftCell   = floor(ruv.y * threadFreq);
    let warpOnTop  = fract((warpCell + weftCell) * 0.5) < 0.5;

    // Thread brightness from sine profile (rounded cross-section)
    // Idea 1: two-ply twist — each yarn is two offset fibers.
    let ply = 0.55;
    let warpBrightA = smoothstep(0.0, 0.3, warpPhase) * (1.0 - smoothstep(0.7, 1.0, warpPhase));
    let weftBrightA = smoothstep(0.0, 0.3, weftPhase) * (1.0 - smoothstep(0.7, 1.0, weftPhase));
    let warpPhase2 = sin(ruv.x * threadFreq * PI + ply + pluck * 0.8) * 0.5 + 0.5;
    let weftPhase2 = sin(ruv.y * threadFreq * PI - ply - pluck * 0.8) * 0.5 + 0.5;
    let warpBrightB = smoothstep(0.0, 0.3, warpPhase2) * (1.0 - smoothstep(0.7, 1.0, warpPhase2)) * 0.82;
    let weftBrightB = smoothstep(0.0, 0.3, weftPhase2) * (1.0 - smoothstep(0.7, 1.0, weftPhase2)) * 0.82;
    // Idea 4: slub yarn — every warp/weft yarn has its own spun thickness and dye lot.
    let warpSlub = fract(sin(warpCell * 12.9898 + 4.1) * 43758.5453);
    let weftSlub = fract(sin(weftCell * 78.233 + 1.7) * 43758.5453);
    let warpSlubPhase = abs(warpPhase - 0.5) * 2.0;
    let weftSlubPhase = abs(weftPhase - 0.5) * 2.0;
    let warpThick = 1.0 - smoothstep(0.55 + warpSlub * 0.4, 1.0, warpSlubPhase) * 0.75;
    let weftThick = 1.0 - smoothstep(0.55 + weftSlub * 0.4, 1.0, weftSlubPhase) * 0.75;
    let warpBright = max(warpBrightA, warpBrightB) * warpThick * (0.85 + warpSlub * 0.4);
    let weftBright = max(weftBrightA, weftBrightB) * weftThick * (0.85 + weftSlub * 0.4);
    let topBright  = select(weftBright, warpBright, warpOnTop);
    let botBright  = select(warpBright, weftBright, warpOnTop);
    let cellCode = u32(abs(warpCell * 19.0 + weftCell * 37.0));
    // RESCUE: plasmaBuffer[1..8] are never uploaded (only [0] is); the FFT bins live in extraBuffer[5..132].
    let fftVoice = clamp(extraBuffer[5u + (cellCode % 128u)], 0.0, 1.0);

    // Under-thread shadow
    let shadow     = 1.0 - shadowDepth * (1.0 - botBright);

    // UV offsets per channel: warp→R, neutral→G, weft→B
    let warpDir = vec2<f32>(cosA, sinA);
    let weftDir = vec2<f32>(-sinA, cosA);
    let rUV = clamp(uv + warpDir * chromaOff,  vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv,                         vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + weftDir * chromaOff,  vec2<f32>(0.0), vec2<f32>(1.0));

    let srcR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let srcG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let srcB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let srcA = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    // Build thread colour: warp threads tinted warm, weft tinted cool
    let warpTint = vec3<f32>(1.05, 0.97, 0.93);
    let weftTint = vec3<f32>(0.93, 0.97, 1.05);
    // Idea 3: Jacquard yarn-dye — the crossing cell's yarn carries the source colour
    // sampled at the cell centre (rotated back to screen uv), not a per-pixel print.
    let cellRuv = (vec2<f32>(warpCell, weftCell) + 0.5) / threadFreq;
    let cellUV  = clamp(vec2<f32>(cellRuv.x * cosA + cellRuv.y * sinA,
                                  -cellRuv.x * sinA + cellRuv.y * cosA), vec2<f32>(0.0), vec2<f32>(1.0));
    let dyeCol  = textureSampleLevel(readTexture, u_sampler, cellUV, 0.0).rgb;
    let srcPix  = vec3<f32>(srcR, srcG, srcB);
    let fringe  = srcPix - textureSampleLevel(readTexture, u_sampler, gUV, 0.0).rgb; // keep the channel-offset fringes
    let srcCol  = max(mix(srcPix, dyeCol + fringe, 0.8), vec3<f32>(0.0));
    let tinted   = mix(srcCol * weftTint, srcCol * warpTint, f32(select(0, 1, warpOnTop)));

    // Apply thread brightness and shadow
    var col = tinted * topBright * shadow;

    // Audio reactivity: mid brightens highlights
    col += srcCol * (1.0 - topBright) * 0.15 * mid;

    // Yarn specular micro-highlight
    let specMask = topBright * topBright;
    col += vec3<f32>(0.8, 0.85, 0.9) * specMask * 0.12 * (1.0 + treble * 0.5 + fftVoice * 0.45);

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.5));

    // Idea 2: exact-C under-thread ghost — previous weft shows through gaps.
    let histDim = textureDimensions(dataTextureC);
    let histCoord = clamp(coord, vec2<i32>(0), vec2<i32>(histDim) - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, histCoord, 0);
    let gap = 1.0 - topBright;
    col = mix(col, prev.rgb * botBright, gap * 0.28);

    // Semantic alpha
    let alpha = clamp(srcA * (0.55 + topBright * 0.45), 0.0, 1.0);

    let mapped = acesToneMap(clamp(col, vec3<f32>(0.0), vec3<f32>(1.2)));
    let outColor = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, coord, outColor);
    let sourceDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let weaveDepth = clamp(sourceDepth + topBright * shadowDepth * 0.18 + abs(pluck) * topBright * 0.05, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(weaveDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(warpBright, weftBright, bass, mid));
}
