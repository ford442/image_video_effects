// ═══════════════════════════════════════════════════════════════════
//  hyb-chromatic-circuit
//  Category: hybrid
//  Features: hex-grid, trace-edges, chromatic-aberration, pulse-glow,
//            alpha-passthrough, depth-passthrough
//  Chunks: nearestHexCenter + sdSegment + glow + hsv2rgb
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

// ── Chunk: hash12 (from gen_grid.wgsl) ──
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Chunk: nearestHexCenter (from hex-mosaic.wgsl / quantum-prism.wgsl) ──
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

// ── Chunk: sdSegment (from gen-holographic-fracture.wgsl) ──
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

// ── Chunk: glow (from anamorphic-flare.wgsl) ──
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius)) * intensity;
}

// ── Chunk: hsv2rgb (from chronos-brush.wgsl) ──
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
    return v * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    let dimsI = vec2<i32>(dims);

    if (any(coord >= dimsI)) {
        return;
    }

    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Normalize zoom_params
    let time = u.config.x;
    let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
    let gridScale = mix(4.0, 32.0, zp.x);
    let traceWidth = mix(0.02, 0.12, zp.y);
    let chromaSpread = mix(0.0, 0.05, zp.z);
    let effectMix = mix(0.0, 1.0, zp.w);

    // Hex-grid trace network built from nearest cell centers
    let hexUV = uv * gridScale;
    let center = nearestHexCenter(uv, gridScale);
    let local = hexUV - center;

    // Hex edge distance for cell outline
    let r = vec2<f32>(1.0, 1.7320508);
    let q = abs(local);
    let hexDist = max(q.x * 0.5 + q.y * 0.866025, q.x);
    let edgeDist = 0.5 - hexDist;
    let hexEdge = 1.0 - smoothstep(0.0, 0.08, edgeDist);

    // Trace segments to neighboring cell centers, animated by a hash gate
    let cellId = floor(center / r);
    let rnd = hash12(cellId + vec2<f32>(37.0, 17.0));
    let gate = step(0.35, rnd);

    // Six hex-neighbor offsets in scaled space
    let n0 = center + vec2<f32>(1.0, 0.0);
    let n1 = center + vec2<f32>(0.5, 0.866025);
    let n2 = center + vec2<f32>(-0.5, 0.866025);
    let n3 = center + vec2<f32>(-1.0, 0.0);
    let n4 = center + vec2<f32>(-0.5, -0.866025);
    let n5 = center + vec2<f32>(0.5, -0.866025);

    let d0 = sdSegment(hexUV, center, n0);
    let d1 = sdSegment(hexUV, center, n1);
    let d2 = sdSegment(hexUV, center, n2);
    let d3 = sdSegment(hexUV, center, n3);
    let d4 = sdSegment(hexUV, center, n4);
    let d5 = sdSegment(hexUV, center, n5);
    let traceDist = min(min(min(d0, d1), min(d2, d3)), min(d4, d5));

    // Animated pulse travels along traces
    let pulsePhase = time * 1.5 + cellId.x * 0.7 + cellId.y * 0.5;
    let pulse = 0.5 + 0.5 * sin(pulsePhase);
    let traceMask = (1.0 - smoothstep(0.0, traceWidth, traceDist)) * gate;
    let pulseGlow = glow(traceDist, traceWidth * 2.5, 1.2) * pulse * gate;

    // Image edges modulate trace intensity
    let texel = 1.0 / vec2<f32>(dims);
    let cR = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let cU = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let luma = dot(src.rgb, vec3<f32>(0.333));
    let lumaR = dot(cR, vec3<f32>(0.333));
    let lumaU = dot(cU, vec3<f32>(0.333));
    let imgEdge = sqrt(pow(luma - lumaR, 2.0) + pow(luma - lumaU, 2.0));
    let edgeBoost = smoothstep(0.05, 0.25, imgEdge);

    // Chromatic aberration smears the input along the local hex gradient
    let grad = normalize(hexUV - center + vec2<f32>(1e-4));
    let rUV = clamp(uv + grad * chromaSpread, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - grad * chromaSpread, vec2<f32>(0.0), vec2<f32>(1.0));
    let chroma = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        src.g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    );

    // Opal-circuit coloring: hue shifts by cell ID and pulse
    let hue = fract(rnd * 0.2 + time * 0.08 + pulse * 0.15);
    let circuitCol = hsv2rgb(hue, 0.85, 1.0);
    let traceCol = circuitCol * (traceMask + pulseGlow * 0.6) * (1.0 + edgeBoost * 1.5);
    let hexFill = circuitCol * hexEdge * 0.12 * edgeBoost;

    let layerRGB = clamp(chroma + traceCol + hexFill, vec3<f32>(0.0), vec3<f32>(1.0));
    let outRGB = mix(src.rgb, layerRGB, effectMix);

    textureStore(writeTexture, coord, vec4<f32>(clamp(outRGB, vec3<f32>(0.0), vec3<f32>(1.0)), src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
