// ═══════════════════════════════════════════════════════════════════
//  Fractal Noise Dissolve
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: heat-shimmer refraction; scorch band; fractal pinholes
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-01 (Batch 23)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(dot(hash22(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
            dot(hash22(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u2.x),
        mix(dot(hash22(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
            dot(hash22(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * noise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

// Compress only the brightest channel, then scale the full RGB vector by the
// same ratio so hot burn hues survive instead of clipping toward white.
fn softKnee(c: vec3<f32>, knee: f32) -> vec3<f32> {
  let peak = max(c.r, max(c.g, c.b));
  let mapped = peak / (1.0 + max(peak - knee, 0.0) * 0.5);
  return c * (mapped / max(peak, 1e-5));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFade = mix(0.7, 1.0, depth);

    let noiseScale = u.zoom_params.x * 20.0 + 5.0;
    let radius = u.zoom_params.y * 0.5 * bass_env(bass, mids);
    let edgeWidth = max(u.zoom_params.z * 0.2, 0.01);
    let burnColor = u.zoom_params.w * (1.0 + mids * 0.35);

    // Erosion centre follows the raw pointer (HEAD's extraBuffer spring was
    // dead: the buffer is re-uploaded each frame and workgroups raced it).
    let erosionCenter = mouse;

    // Domain warped FBM
    let warp = vec2<f32>(
        fbm(uv * noiseScale * 0.5 + vec2<f32>(time * 0.1, 0.0), 3),
        fbm(uv * noiseScale * 0.5 + vec2<f32>(0.0, time * 0.1), 3)
    );
    var n = fbm((uv + warp * 0.1) * noiseScale * (1.0 + bass * 0.25) + vec2<f32>(time, time * 0.7), 4);
    n += fbm((uv + warp * 0.15) * noiseScale * 2.0 - vec2<f32>(time * (1.0 + treble * 0.2), time), 4) * 0.5;
    n = n * 0.5 + 0.5;

    let dist = distance(uv * vec2<f32>(aspect, 1.0), erosionCenter * vec2<f32>(aspect, 1.0));
    let contour = dist + (n * 0.2 - 0.1);

    // Click timestamps seed independent expanding dissolve rings. These alter
    // only the display mask; dataTextureA remains the existing display-color
    // feedback role and no simulation state is repacked.
    var clickErosion = 0.0;
    var clickEdge = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
      let rp = u.ripples[ri];
      let age = time - rp.z;
      if (age < 0.0 || age > 2.2) { continue; }
      let clickDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let ringRadius = age * 0.30;
      let fade = exp(-age * 1.15);
      let ringDelta = abs(clickDist - ringRadius);
      clickErosion = max(clickErosion,
        (1.0 - smoothstep(0.0, edgeWidth * 1.8 + 0.018, ringDelta)) * fade);
      clickEdge = max(clickEdge,
        (1.0 - smoothstep(edgeWidth * 0.8, edgeWidth * 3.0 + 0.03, ringDelta)) * fade);
    }

    var mask = smoothstep(radius, radius + edgeWidth, contour);
    mask = mask * (1.0 - clamp(clickErosion, 0.0, 1.0));
    let burnAmt = clamp(burnColor * 1.4, 0.0, 1.0);

    // Idea 3: fractal pinholes — a fine-octave FBM punches small detached
    // holes just ahead of the front and leaves a few unburnt islands just
    // behind it, so the erosion breaks up across scales.
    // fbm(.,3) of this gradient noise spans only ~±0.17 (std ~0.058), so it is
    // stretched x2 around 0.5 or the 0.64..0.76 cuts below are never reached.
    let nf = fbm((uv + warp * 0.3) * noiseScale * 4.0 + vec2<f32>(-time * 0.4, time * 0.3), 3) * 2.0 + 0.5;
    let ahead = smoothstep(radius - 0.01, radius + edgeWidth, contour)
      * (1.0 - smoothstep(radius + edgeWidth, radius + edgeWidth * 3.0 + 0.06, contour));
    let pinThr = 0.72 - 0.08 * ahead;
    let pin = smoothstep(pinThr, pinThr + 0.03, nf) * ahead;
    let pinEdge = clamp(pin * (1.0 - pin) * 4.0, 0.0, 1.0);
    let island = smoothstep(0.74, 0.76, nf) * smoothstep(radius - 0.1, radius - 0.02, contour)
      * (1.0 - smoothstep(radius - 0.01, radius + edgeWidth, contour));
    mask = max(mask * (1.0 - pin), island * 0.9);

    // Idea 1: heat-shimmer refraction — rising heat just outside the front
    // bends the photo along the gradient of a scrolling noise.
    let heatZone = smoothstep(radius - 0.005, radius + edgeWidth, contour)
      * (1.0 - smoothstep(radius + edgeWidth, radius + edgeWidth * 4.0 + 0.06, contour));
    let sp = uv * vec2<f32>(aspect, 1.0) * noiseScale * 1.5 + vec2<f32>(0.0, time * 1.6);
    let he = 0.35;
    let heatGrad = vec2<f32>(
      noise(sp + vec2<f32>(he, 0.0)) - noise(sp - vec2<f32>(he, 0.0)),
      noise(sp + vec2<f32>(0.0, he)) - noise(sp - vec2<f32>(0.0, he))
    );
    let heatUV = clamp(uv + heatGrad * heatZone * burnAmt * (0.012 + bass * 0.006), vec2<f32>(0.0), vec2<f32>(1.0));

    var baseColor = textureSampleLevel(readTexture, u_sampler, heatUV, 0.0);

    // Idea 2: scorch band — before the flame arrives the photo browns,
    // desaturates and darkens toward char (islands stay fully charred).
    let scorch = (1.0 - smoothstep(radius + edgeWidth, radius + edgeWidth * 3.0 + 0.05, contour)) * burnAmt;
    let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let sepia = luma * vec3<f32>(0.62, 0.40, 0.22);
    baseColor = vec4<f32>(mix(baseColor.rgb, sepia, scorch * 0.6) * (1.0 - scorch * 0.45), baseColor.a);

    let edge = max(max(1.0 - smoothstep(radius, radius + edgeWidth * 2.0, contour), clickEdge), pinEdge);
    let burnRaw = vec3<f32>(1.0, 0.45 + treble * 0.2, 0.18 + mids * 0.2)
      * edge * burnColor * 4.0 * (1.0 - mask);
    let burn = softKnee(burnRaw, 1.25);

    // Edge glow from audio
    let edgeGlow = vec3<f32>(0.5 + bass * 0.3, 0.3, 0.8) * edge * bass * 0.5;
    var finalColor = baseColor.rgb * mask + burn + edgeGlow;
    finalColor = acesToneMap(max(finalColor * depthFade, vec3<f32>(0.0)));
    let alpha = clamp(baseColor.a * mask + edge * 0.42 + bass * 0.05, 0.04, 1.0);
    let depthOut = clamp(depth + edge * 0.06 - scorch * 0.02, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
