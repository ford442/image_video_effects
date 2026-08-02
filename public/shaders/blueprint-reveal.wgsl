// ═══════════════════════════════════════════════════════════════════
//  Blueprint Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-ink, depth-hatch, upgraded-rgba
//  Complexity: High
//  Chunks From: blueprint-reveal, bass_env, temporal-feedback
//  Created: 2026-05-30
//  Upgraded: 2026-05-31
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

fn sobel(uv: vec2<f32>, res: vec2<f32>) -> f32 {
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
    return sqrt(gx * gx + gy * gy);
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

    // The reveal brush glides with a critically damped spring. Its state lives
    // only in the persistent-safe extraBuffer range [133..138].
    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mousePos = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
      mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
      var springPos = mousePos;
      var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
      if (extraBuffer[138] <= 0.5) {
        springPos = rawMouse;
        springVel = vec2<f32>(0.0);
      } else {
        let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
        let omega = 7.5;
        let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
        springVel += accel * dt;
        springPos += springVel * dt;
      }
      extraBuffer[133] = springPos.x;
      extraBuffer[134] = springPos.y;
      extraBuffer[135] = springVel.x;
      extraBuffer[136] = springVel.y;
      extraBuffer[137] = time;
      extraBuffer[138] = 1.0;
    }

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
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let inkDecay = 0.92 + softness * 0.05;
    let prevReveal = history.r;
    let temporalMask = max(max(revealMask, clickInk), prevReveal * inkDecay);

    let edgeVal = clamp(sobel(uv, resolution) * edgeStrength, 0.0, 1.5);
    let tileBin = (u32(floor(uv.x * 4.0)) + u32(floor(uv.y * 4.0)) * 3u) % 8u + 1u;
    let fftInk = plasmaBuffer[tileBin].x;
    var blueprint = vec3<f32>(0.04, 0.09, 0.34) + vec3<f32>(0.75, 0.88, 1.0) * edgeVal * (1.0 + treble * 0.20 + fftInk * 0.16);

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

    let finalColor = mix(blueprint, baseColor.rgb, temporalMask);
    let alpha = clamp(baseColor.a * 0.45 + (1.0 - temporalMask) * 0.32 + edgeVal * 0.18 + bass * 0.05, 0.08, 1.0);
    let depthOut = clamp(depth + (1.0 - temporalMask) * 0.04, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(temporalMask, 0.0, 0.0, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
