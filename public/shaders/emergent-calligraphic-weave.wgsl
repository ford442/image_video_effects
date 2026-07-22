// ═══════════════════════════════════════════════════════════════════
//  Emergent Calligraphic Weave v3
//  Category: generative
//  Features: stroke-based, brush-dynamics, ink-viscosity, paper-absorption,
//            bezier-strokes, sumi-e, dry-brush, dry-brush-sparkle,
//            curl-field, chromatic-edge, upgraded-rgba, aces-tone-map
//  Complexity: Very High
//  Created: 2026-05-31
//  Upgraded: 2026-07-22 (Visualist: curl-noise stroke field, real brush
//            constants on all 4 sliders, treble dry-brush edge sparkle)
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=FieldComplexity, y=StrokePersistence, z=Coherence, w=Chaos
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Smooth value noise built on hash12 (lattice-interpolated)
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (3.0 - 2.0 * f);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, uu.x), mix(c, d, uu.x), uu.y);
}

// Divergence-free curl field: perpendicular gradient of a scalar potential.
// Strokes advected along this flow read as brushed calligraphy, not static hash.
fn curlField(p: vec2<f32>, freq: f32, time: f32) -> vec2<f32> {
    let e = 0.35 / max(freq, 0.001);
    let sp = p * freq + vec2<f32>(time * 0.13, -time * 0.09);
    let pR = vnoise(sp + vec2<f32>(e, 0.0));
    let pL = vnoise(sp - vec2<f32>(e, 0.0));
    let pU = vnoise(sp + vec2<f32>(0.0, e));
    let pD = vnoise(sp - vec2<f32>(0.0, e));
    let dx = (pR - pL) / (2.0 * e);
    let dy = (pU - pD) / (2.0 * e);
    return vec2<f32>(dy, -dx);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.5;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // ── Slider-wired brush constants (saved-preset contract) ─────────
    let pComplexity   = clamp(u.zoom_params.x, 0.0, 1.0); // Field Complexity
    let pPersistence  = clamp(u.zoom_params.y, 0.0, 1.0); // Stroke Persistence
    let pCoherence    = clamp(u.zoom_params.z, 0.0, 1.0); // Pattern Coherence
    let pChaos        = clamp(u.zoom_params.w, 0.0, 1.0); // Field Chaos

    // p1: orientation-field frequency + stroke width (complex field = finer strokes)
    let fieldFreq   = mix(1.2, 5.5, pComplexity);
    let strokeWidth = mix(0.022, 0.006, pComplexity);
    // p2: ink viscosity (temporal decay) + dry-brush threshold (wetter ink = less dry-brush)
    let viscosity   = mix(0.78, 0.97, pPersistence) + mids * 0.02;
    let dryThresh   = mix(0.30, 0.52, pPersistence);
    // p3: coherence feedback gain — larger connected stroke structures
    let coherenceGain = mix(0.005, 0.14, pCoherence);
    // p4: turbulence amplitude injected into the orientation field
    let chaosAmp = mix(0.05, 1.4, pChaos);

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Brush dynamics parameters
    let pressure = mouseDown * (0.6 + hash12(mouse * 10.0 + time) * 0.4);
    let brushSpeed = 0.5 + bass * 2.0;
    let inkConcentration = 0.4 + mids * 0.6;

    let strokeLength = strokeWidth * (0.6 + brushSpeed * 1.4);
    let chaos = chaosAmp + treble * 0.4;

    // Orientation field with mouse influence
    let toMouse = normalize(uv - mouse + vec2<f32>(0.0001));
    let mouseAngle = atan2(toMouse.y, toMouse.x);
    let mouseInfluence = smoothstep(0.3, 0.02, length(uv - mouse)) * pressure * 2.0;

    let n1 = hash12(uv * 1.7 + time * 0.1) - 0.5;
    let n2 = hash12(uv * 4.3 - time * 0.17) - 0.5;
    let baseAngle = (n1 * 1.2 + n2 * 0.6) * (1.0 + chaos * 0.6);

    // Curl-noise advection: bend the base stroke direction along the
    // divergence-free flow so strokes sweep like a moving brush.
    let curl = curlField(uv, fieldFreq, time);
    let curlMag = length(curl);
    let curlWeight = clamp(curlMag * mix(0.25, 0.9, pComplexity), 0.0, 0.85);
    let baseDir = vec2<f32>(cos(baseAngle), sin(baseAngle));
    let flowedDir = normalize(mix(baseDir, curl / max(curlMag, 0.0001), curlWeight));
    let flowedAngle = atan2(flowedDir.y, flowedDir.x);
    let angle = mix(flowedAngle, mouseAngle, mouseInfluence);

    // Bézier stroke sampling modulated by velocity
    let dir = vec2<f32>(cos(angle), sin(angle));
    let perp = vec2<f32>(-dir.y, dir.x);
    let curvature = sin(angle * 3.0 + time * 2.0) * 0.015 * brushSpeed;
    let sampleUV = clamp(uv - dir * strokeLength + perp * curvature, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampled = textureSampleLevel(dataTextureC, u_sampler, sampleUV, 0.0);

    // Paper grain and absorption scale from depth
    let paperScale = mix(30.0, 100.0, depth);
    let grain = hash12(uv * paperScale);
    let paperAbsorb = 0.5 + depth * 0.5;
    let dryBrush = smoothstep(dryThresh, dryThresh + 0.2, grain);

    // Paper fiber visibility
    let fiber = sin(uv.x * paperScale * 2.3 + uv.y * paperScale * 1.7) * 0.5 + 0.5;
    let fiberMask = smoothstep(0.4, 0.6, fiber) * dryBrush * 0.2;

    // Stroke edge detection (needed by both ink flow and dry-brush sparkle)
    let neighbor = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + dir * 0.004, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let edge = abs(prev.r - neighbor.r);
    let edgeMask = smoothstep(0.02, 0.08, edge);

    // Ink viscosity flow and capillary bleed
    let decay = viscosity - bass * 0.02;
    let bleed = (sampled.r - prev.r) * 0.08 * paperAbsorb;
    var newStroke = sampled.r * decay + 0.035 * inkConcentration + bleed;
    newStroke = newStroke * (0.7 + dryBrush * 0.6);

    // Brush temperature from bass (faster = drier / hotter)
    let brushTemp = 0.5 + bass * 0.5;
    let evaporation = smoothstep(0.3, 0.8, brushTemp);
    newStroke = newStroke * (1.0 - evaporation * 0.08);

    // Treble-driven splatter
    let splatter = step(1.0 - treble * 0.25, hash12(uv * 60.0 + time * 5.0)) * treble * 0.4;
    newStroke = newStroke + splatter;

    // Dry-brush edge sparkle: treble-excited ink grain that sizzles only
    // on stroke edges where the brush has run dry.
    let sparkleGrain = hash12(uv * paperScale * 4.0 + vec2<f32>(time * 9.0, -time * 7.0));
    let sparkle = step(1.0 - treble * 0.45, sparkleGrain) * treble * edgeMask * dryBrush;
    newStroke = newStroke + sparkle * 0.15;

    // Coherence feedback from orientation alignment (slider-driven gain)
    let coherence = 1.0 - abs(sampled.g - angle) * 0.7;
    newStroke += coherence * coherenceGain * (0.5 + mids * 0.4);

    let density = clamp(newStroke, 0.0, 1.2);
    let ink = pow(density, 0.9);

    // Sumi-e ink wash palette
    let inkR = mix(vec3<f32>(0.06, 0.04, 0.03), vec3<f32>(0.9, 0.7, 0.5), ink);
    let inkB = mix(vec3<f32>(0.06, 0.04, 0.03), vec3<f32>(0.5, 0.7, 0.9), ink);
    let col = mix(inkR, inkB, smoothstep(0.3, 0.7, treble));

    // Chromatic edge darkening (yellowing at ink boundaries)
    let yellowing = vec3<f32>(0.9, 0.85, 0.5) * edgeMask * 0.35;

    let hueShift = sin(angle * 2.0) * 0.06;
    var finalCol = col * (1.0 + hueShift) + yellowing;

    // Dry-brush sparkle as warm paper-grain glint on stroke edges
    finalCol = finalCol + vec3<f32>(0.85, 0.8, 0.65) * sparkle * 0.6;

    // Add paper fiber texture to final color
    finalCol = finalCol + vec3<f32>(0.05, 0.04, 0.03) * fiberMask;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    finalCol = vec3<f32>(finalCol.r + caStr, finalCol.g, finalCol.b - caStr * 0.5);

    // ACES tone map
    finalCol = acesToneMap(finalCol * 1.1);

    let alpha = clamp(ink * paperAbsorb * depth + splatter * 0.5 + sparkle * 0.3, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(finalCol, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(newStroke, angle, inkConcentration, density));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(density * 0.5, 0.0, 0.0, 0.0));
}
