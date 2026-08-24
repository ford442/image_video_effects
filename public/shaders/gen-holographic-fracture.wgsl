// ═══════════════════════════════════════════════════════════════════
//  Holographic Fracture - Iridescent cracked SDF planes
//  Category: generative
//  Features: generative, sdf, iridescence, fracture-lines, glow,
//            audio-reactive, mouse-crack, click-ripples, depth-aware
//  Agent 4a — Phase A shader upgrade swarm
//  Engine uniform convention (verified src/renderer/UniformBuffer.ts):
//    zoom_config.yz = mouse position (0..1), zoom_config.w = mouse-down
//    zoom_config.x  = TIME (do NOT use as mouse x)
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=FractureCount, y=Iridescence, z=CrackWidth, w=PulseSpeed
  ripples: array<vec4<f32>, 50>,
};

// ── Chunk: hash22 (from gen_grid.wgsl / chunk-library) ────────────
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ── Chunk: valueNoise (from gen_grid.wgsl) ────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uS = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash22(i + vec2<f32>(0.0, 0.0)).x;
    let b = hash22(i + vec2<f32>(1.0, 0.0)).x;
    let c = hash22(i + vec2<f32>(0.0, 1.0)).x;
    let d = hash22(i + vec2<f32>(1.0, 1.0)).x;
    return mix(mix(a, b, uS.x), mix(c, d, uS.x), uS.y);
}

// ── Chunk: fbm2 (from chunk-library) ──────────────────────────────
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ── Chunk: rot2 (from chunk-library) ──────────────────────────────
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ── Chunk: glow (from anamorphic-flare.wgsl) ──────────────────────
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius + 1e-6)) * intensity;
}

// Signed distance to a line segment
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

// Iridescent thin-film color
fn iridescence(theta: f32, shift: f32) -> vec3<f32> {
    let t = theta * 4.0 + shift;
    return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189));
}

// Filmic ACES tonemap (Krzysztof Narkowicz fit)
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Hue-preserving clamp: rescale by max channel instead of clipping
fn huePreserveClamp(c: vec3<f32>) -> vec3<f32> {
    let m = max(c.r, max(c.g, c.b));
    if (m > 1.0) {
        return c / m;
    }
    return c;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(gid.xy);
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / max(res.y, 1.0);
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;

    // Audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders → shader-specific constants
    // x: FractureCount  → radial crack count (3..12) + shard cell scale
    // y: Iridescence    → thin-film amplitude + per-crack phase-shift range
    // z: CrackWidth     → crack core line width + glow falloff radii
    // w: PulseSpeed     → crack pulse rate, wobble rate, ripple front speed
    let fractureCount = mix(3.0, 12.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let iridescenceAmt = clamp(u.zoom_params.y, 0.0, 1.0);
    let crackWidth = mix(0.002, 0.02, clamp(u.zoom_params.z, 0.0, 1.0));
    let pulseSpeed = mix(0.2, 1.5, clamp(u.zoom_params.w, 0.0, 1.0));

    // Mouse crack origin (FIX: read .yz, not .xy — x is time)
    let rawMouse = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDown = step(0.5, u.zoom_config.w);

    // Spring-damper the mouse crack origin so it eases rather than snaps.
    // Persistent state: [133..134] position, [135..136] velocity, [137] init.
    // All accesses are guarded and only invocation (0,0) writes the state.
    var easedMouse = rawMouse;
    var mouseVelocity = vec2<f32>(0.0);
    let hasSpringState = arrayLength(&extraBuffer) > 137u;
    if (hasSpringState && extraBuffer[137] > 0.5) {
        easedMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        mouseVelocity = (mouseVelocity + (rawMouse - easedMouse) * 0.16) * 0.72;
        easedMouse += mouseVelocity;
    }
    if (hasSpringState && gid.x == 0u && gid.y == 0u) {
        extraBuffer[133] = easedMouse.x;
        extraBuffer[134] = easedMouse.y;
        extraBuffer[135] = mouseVelocity.x;
        extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0;
    }
    let mouse = easedMouse;

    // Background substrate with subtle FBM
    let substrate = fbm2(p * 2.5 + time * 0.05, 4);

    // Fracture network: radial cracks from center + mouse point
    var minDist = 1000.0;
    var crackIntensity = 0.0;
    var domPhase = 0.0; // audio-bin phase of the dominant crack at this pixel

    let centers = array<vec2<f32>, 2>(vec2<f32>(0.0), mouse);
    for (var c = 0; c < 2; c = c + 1) {
        let center = centers[c];
        let toP = p - center;
        let polar = vec2<f32>(length(toP), atan2(toP.y, toP.x));

        let nCracks = i32(fractureCount) + select(0, 3, c == 1 && mouseDown > 0.5);
        let pointerGain = select(0.35, 1.0, c == 0 || mouseDown > 0.5);
        for (var i = 0; i < 16; i = i + 1) {
            if (i >= nCracks) { break; }
            let fi = f32(i);
            let baseAngle = fi / fractureCount * 6.28318;
            let angle = baseAngle + polar.y;
            let wave = sin(angle * 3.0 + polar.x * 12.0 + time * pulseSpeed) * 0.03;
            let r = polar.x + wave + substrate * 0.05;

            let a = center + vec2<f32>(cos(baseAngle), sin(baseAngle)) * 0.02;
            let b = center + vec2<f32>(cos(baseAngle + wave), sin(baseAngle + wave)) * (1.2 + bass * 0.3);
            let d = sdSegment(p, a, b);
            let w = crackWidth * (1.0 + mids * 0.5);
            let line = (1.0 - smoothstep(0.0, w, d)) * pointerGain;
            if (line > crackIntensity) {
                crackIntensity = line;
                // Per-crack iridescence phase from audio FFT bins 1..8,
                // so each crack index shimmers to its own band.
                domPhase = plasmaBuffer[1u + (u32(i) % 8u)].x;
            }
            minDist = min(minDist, d);
        }
    }

    // Click crack fronts: transient radial fractures expanding from each
    // ripple point, fading with ripple age (guard: max 50 engine ripples)
    let nRipples = min(u32(u.config.y), 50u);
    var frontGlow = 0.0;
    var frontDist = 1000.0;
    for (var ri = 0u; ri < nRipples; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age < 0.0 || age > 4.0) { continue; }
        let rc = (rp.xy - 0.5) * vec2<f32>(aspect, 1.0);
        let fade = exp(-age * 1.4);
        let radius = age * (0.2 + pulseSpeed * 0.3);
        let dr = length(p - rc);
        // expanding ring front where the fracture is actively propagating
        let ring = abs(dr - radius);
        frontGlow += glow(ring, crackWidth * 5.0, fade * 0.9);
        frontDist = min(frontDist, ring);
        // short radial spokes left behind the advancing front
        let spokeAng = atan2(p.y - rc.y, p.x - rc.x);
        let spoke = abs(sin(spokeAng * 4.0)) * dr;
        let inside = 1.0 - smoothstep(radius - 0.02, radius, dr);
        frontGlow += glow(spoke, crackWidth * 3.0, fade * 0.5) * inside;
        frontDist = min(frontDist, spoke + (1.0 - inside));
    }

    // Holographic shard coloring based on angle and distance
    let angleToCenter = atan2(p.y, p.x);
    let distToCenter = length(p);
    let iridShift = time * 0.1 + distToCenter * 3.0 + bass * 0.2
                  + domPhase * 6.28318 * iridescenceAmt;
    let shardColor = iridescence(angleToCenter + substrate, iridShift);

    // Shard boundaries via Voronoi-like cell edges
    let cellScale = fractureCount * 0.6;
    let cellId = floor(p * cellScale);
    let cellFract = fract(p * cellScale) - 0.5;
    let rnd = hash22(cellId);
    let cellCenter = (rnd - 0.5) * 0.8;
    let edgeDist = abs(length(cellFract - cellCenter) - 0.35);
    let edgeGlow = glow(edgeDist, crackWidth * 3.0, 0.5) * (0.3 + treble * 0.5);

    // Pulse along cracks
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed * 3.0 + distToCenter * 10.0);
    let crackGlow = glow(minDist, crackWidth * 4.0, 1.0 + pulse * 0.7) * (0.4 + bass * 0.6);

    // Compose
    var col = vec3<f32>(0.02, 0.03, 0.05);
    col += shardColor * substrate * 0.25;
    col += shardColor * iridescenceAmt * 0.2;
    col += vec3<f32>(0.7, 0.9, 1.0) * crackGlow;
    col += shardColor * edgeGlow * iridescenceAmt;
    col += vec3<f32>(1.0, 0.9, 0.7) * crackIntensity * (0.6 + treble);
    col += mix(vec3<f32>(1.0, 0.75, 0.45), shardColor, 0.5) * frontGlow;

    // Vignette
    let v = 1.0 - length(uv - 0.5) * 0.4;
    col *= clamp(v, 0.0, 1.0);

    // Honest depth: crack proximity raises the surface, substrate adds
    // gentle relief, ripple fronts ridge outward. 0 = far, 1 = near.
    let crackDepth = 1.0 - smoothstep(0.0, 0.3, minDist);
    let frontDepth = 1.0 - smoothstep(0.0, 0.15, frontDist);
    let depth = clamp(substrate * 0.3 + crackDepth * 0.5 + frontDepth * 0.2 + edgeGlow * 0.1,
                      0.0, 1.0);

    // Hue-preserving soft clamp, then filmic ACES. A/C owns this exact
    // display RGBA so persistence never re-tonemaps a previous display frame.
    col = huePreserveClamp(col);
    let currentDisplay = acesToneMap(col * 1.05);
    let prevDisplay = textureLoad(dataTextureC, coord, 0);
    let persistence = clamp(0.12 + bass * 0.04, 0.10, 0.22);
    let finalColor = mix(prevDisplay.rgb * 0.955, currentDisplay, persistence);
    let fractureCoverage = clamp(
        0.08 + crackIntensity * 0.52 + crackGlow * 0.20 + edgeGlow * 0.12 + frontGlow * 0.32,
        0.05, 0.98
    );
    let alpha = max(fractureCoverage, prevDisplay.a * 0.94);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
}
