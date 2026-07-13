// ═══════════════════════════════════════════════════════════════════
//  Holographic Fracture - Iridescent cracked SDF planes
//  Category: generative
//  Features: generative, sdf, iridescence, fracture-lines, glow,
//            audio-reactive, mouse-crack, depth-aware
//  Agent 4a — Phase A shader upgrade swarm
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
  config: vec4<f32>,       // x=Time, y=unused, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=MouseX, y=MouseY, z=unused, w=MouseDown
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

    // Clamp/normalize zoom_params
    let fractureCount = mix(3.0, 12.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let iridescenceAmt = clamp(u.zoom_params.y, 0.0, 1.0);
    let crackWidth = mix(0.002, 0.02, clamp(u.zoom_params.z, 0.0, 1.0));
    let pulseSpeed = mix(0.2, 1.5, clamp(u.zoom_params.w, 0.0, 1.0));

    // Mouse crack origin
    let mouse = (u.zoom_config.xy - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDown = step(0.5, u.zoom_config.w);

    // Background substrate with subtle FBM
    let substrate = fbm2(p * 2.5 + time * 0.05, 4);

    // Fracture network: radial cracks from center + mouse point
    var minDist = 1000.0;
    var crackIntensity = 0.0;

    let centers = array<vec2<f32>, 2>(vec2<f32>(0.0), mouse);
    for (var c = 0; c < 2; c = c + 1) {
        if (c == 1 && mouseDown < 0.5) { continue; }
        let center = centers[c];
        let toP = p - center;
        let polar = vec2<f32>(length(toP), atan2(toP.y, toP.x));

        let nCracks = i32(fractureCount) + select(0, 3, c == 1);
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
            let line = 1.0 - smoothstep(0.0, w, d);
            crackIntensity = max(crackIntensity, line);
            minDist = min(minDist, d);
        }
    }

    // Holographic shard coloring based on angle and distance
    let angleToCenter = atan2(p.y, p.x);
    let distToCenter = length(p);
    let iridShift = time * 0.1 + distToCenter * 3.0 + bass * 0.2;
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

    // Vignette
    let v = 1.0 - length(uv - 0.5) * 0.4;
    col *= clamp(v, 0.0, 1.0);

    // Output as generative background (alpha = 1.0)
    let finalColor = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, 1.0));
}
