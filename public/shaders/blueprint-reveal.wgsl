// ═══════════════════════════════════════════════════════════════════
//  Blueprint Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-04
//  Ideas: dashed hidden lines on far depth; bold contour vs thin construction pen weights; cyanotype toning as the reveal fades
//  A packing: raw fields (revealMask, 0, 0, alpha) — C.r is read back exactly as the ink mask
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.3 + mids * 0.1;
}

fn sample_luma(uv: vec2<f32>) -> f32 {
    let safe_uv = clamp(uv, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    return dot(textureSampleLevel(readTexture, u_sampler, safe_uv, 0.0).rgb, vec3<f32>(0.33333334));
}

// Returns the Sobel gradient (gx, gy); its length is the edge strength and
// its perpendicular is the direction the pen travels along the edge.
fn sobel(uv: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
    let x = 1.0 / res.x;
    let y = 1.0 / res.y;
    let tl = sample_luma(uv + vec2<f32>(-x, -y));
    let t  = sample_luma(uv + vec2<f32>(0.0, -y));
    let tr = sample_luma(uv + vec2<f32>(x, -y));
    let l  = sample_luma(uv + vec2<f32>(-x, 0.0));
    let r  = sample_luma(uv + vec2<f32>(x, 0.0));
    let bl = sample_luma(uv + vec2<f32>(-x, y));
    let b  = sample_luma(uv + vec2<f32>(0.0, y));
    let br = sample_luma(uv + vec2<f32>(x, y));
    let gx = tl * -1.0 + tr + l * -2.0 + r * 2.0 + bl * -1.0 + br;
    let gy = tl * -1.0 + t * -2.0 + tr * -1.0 + bl + b * 2.0 + br;
    return vec2<f32>(gx, gy);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let time = u.config.x;
    let rawMouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Raw pointer: the old extraBuffer[133..138] spring never persisted (the
    // host re-uploads the whole extraBuffer every frame), so it was a no-op.
    let mousePos = rawMouse;
    let coord = vec2<i32>(global_id.xy);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let edgeStrength = mix(0.5, 5.0, u.zoom_params.x) * (1.0 + bass * 0.25);
    let gridOpacity = u.zoom_params.y * (1.0 + mids * 0.2);
    let radius = mix(0.05, 0.6, u.zoom_params.z) * (1.0 + bass * 0.08);
    let softness = mix(0.01, 0.3, u.zoom_params.w);

    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let revealMask = 1.0 - smoothstep(radius, radius + softness, dist);

    // Click-seeded ink blooms become durable through the existing raw mask
    // feedback. Ripple positions are already normalized canvas UVs.
    var clickInk = 0.0;
    var clickRing = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
      let rp = u.ripples[i];
      let age = time - rp.z;
      let safeAge = max(age, 0.0);
      let live = step(0.0, age) * (1.0 - step(2.0, age));
      let clickDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let bloomRadius = 0.025 + safeAge * 0.18;
      let bloom = (1.0 - smoothstep(bloomRadius, bloomRadius + softness * 0.35 + 0.01, clickDist)) * exp(-safeAge * 0.55) * live;
      let ring = (1.0 - smoothstep(0.008, 0.035, abs(clickDist - bloomRadius))) * exp(-safeAge * 1.2) * live;
      clickInk = max(clickInk, bloom);
      clickRing = max(clickRing, ring);
    }

    // Temporal ink dissolve: previous reveal state bleeds outward
    let history = textureLoad(dataTextureC, coord, 0);
    let inkDecay = 0.92 + softness * 0.05;
    let prevReveal = history.r;
    let temporalMask = max(max(revealMask, clickInk), prevReveal * inkDecay);

    let grad = sobel(uv, resolution);
    let edgeVal = clamp(length(grad) * edgeStrength, 0.0, 1.5);
    // Only plasmaBuffer[0] is uploaded; tiles pick one of the three bands.
    let tileBin = (u32(floor(uv.x * 4.0)) + u32(floor(uv.y * 4.0)) * 3u) % 3u;
    let fftInk = select(select(treble, mids, tileBin == 1u), bass, tileBin == 0u);

    // Idea 2: two pen weights. Strong edges are inked as a bold contour, weak
    // ones as a thin, paler construction line, instead of a linear gray ramp.
    let boldPen = smoothstep(0.55, 0.75, edgeVal);
    let thinPen = smoothstep(0.12, 0.28, edgeVal) * (1.0 - boldPen);
    // Idea 1: hidden lines. Edges on far depth are drawn dashed, as in a
    // technical drawing; dashes run along the edge tangent (~12 px period).
    let tangent = select(vec2<f32>(1.0, 0.0), normalize(vec2<f32>(-grad.y, grad.x)), length(grad) > 0.0001);
    let along = dot(uv * resolution, tangent) / 12.0;
    let dash = smoothstep(0.38, 0.46, fract(along)) * (1.0 - smoothstep(0.92, 0.98, fract(along)));
    let hidden = 1.0 - smoothstep(0.22, 0.38, depth);
    let lineInk = (boldPen * 1.0 + thinPen * 0.45) * mix(1.0, dash * 0.8, hidden);
    let penColor = mix(vec3<f32>(0.62, 0.80, 1.0), vec3<f32>(0.80, 0.92, 1.0), boldPen);
    var blueprint = vec3<f32>(0.04, 0.09, 0.34) + penColor * lineInk * 1.25 * (1.0 + treble * 0.20 + fftInk * 0.16);

    // Depth-based hatch density: foreground hatches are finer
    let depthHatch = mix(20.0, 60.0, depth);
    let gridSize = depthHatch * (1.0 + mids * 0.12);
    let gridLineX = smoothstep(0.9, 0.95, sin(uv.x * gridSize * aspect * 3.14159));
    let gridLineY = smoothstep(0.9, 0.95, sin(uv.y * gridSize * 3.14159));
    let grid = max(gridLineX, gridLineY) * gridOpacity * (0.25 + bass * 0.08);
    blueprint += vec3<f32>(grid);

    // Audio surge: bass creates ink ripples from mouse
    let surgePhase = dist * 20.0 - bass * 3.0;
    let surge = smoothstep(0.8, 1.0, sin(surgePhase)) * bass * 0.15;
    blueprint += vec3<f32>(0.5, 0.7, 1.0) * (surge + clickRing * (0.25 + fftInk * 0.15));

    // Idea 3: cyanotype toning. As the ink mask fades back toward blueprint,
    // the revealed photo first develops into a Prussian-blue print of itself.
    let live = max(revealMask, clickInk);
    let photoLuma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let cyanotype = mix(vec3<f32>(0.04, 0.11, 0.30), vec3<f32>(0.86, 0.92, 0.95), smoothstep(0.08, 0.92, photoLuma));
    let toneAmt = (1.0 - smoothstep(0.5, 0.92, temporalMask)) * (1.0 - live * 0.6);
    let revealed = mix(baseColor.rgb, cyanotype, toneAmt);
    let finalColor = aces(max(mix(blueprint, revealed, temporalMask), vec3<f32>(0.0)) * 1.4);
    let alpha = clamp(baseColor.a * 0.45 + (1.0 - temporalMask) * 0.32 + lineInk * 0.18 + bass * 0.05, 0.08, 1.0);
    let depthOut = clamp(depth + (1.0 - temporalMask) * 0.04, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(temporalMask, 0.0, 0.0, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
