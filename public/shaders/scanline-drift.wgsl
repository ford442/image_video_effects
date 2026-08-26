// ═══════════════════════════════════════════════════════════════════
//  Scanline Drift — Batch 62
//  Spring tracking band [133..138], held jitter boost, capped click tears,
//  regional FFT flicker, exact C drift memory, ACES + semantic alpha.
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
  zoom_params: vec4<f32>,  // x=DriftSpeed, y=LineHeight, z=Jitter, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let held = u.zoom_config.w > 0.5;
    var mouse = u.zoom_config.yz;

    let driftSpeed = u.zoom_params.x * 2.0 * (1.0 + bass * 0.2);
    let lineHeight = mix(0.001, 0.1, u.zoom_params.y);
    let jitter = u.zoom_params.z * 0.1 * (1.0 + mids * 0.3) * select(1.0, 1.35, held);
    let colorShiftBase = u.zoom_params.w * 0.05;

    var bandPos = mouse.y;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[138] > 0.5) {
      bandPos = extraBuffer[133];
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
      var springVel = extraBuffer[134];
      if (extraBuffer[138] <= 0.5) {
        bandPos = mouse.y;
        springVel = 0.0;
      } else {
        let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
        let omega = 8.0;
        let accel = (mouse.y - bandPos) * (omega * omega) - springVel * (2.0 * omega);
        springVel += accel * dt;
        bandPos += springVel * dt;
      }
      extraBuffer[133] = bandPos;
      extraBuffer[134] = springVel;
      extraBuffer[137] = time;
      extraBuffer[138] = 1.0;
    }

    // Determine which horizontal strip we are in
    let stripId = floor(uv.y / lineHeight);
    let stripRand = hash11(stripId);

    // Mouse proximity increases jitter (band eased by the spring)
    let distY = abs(uv.y - bandPos);
    let mouseEffect = smoothstep(0.2, 0.0, distY);

    // Calculate horizontal offset
    var offset = sin(time * driftSpeed + stripRand * 6.28) * jitter;
    offset += (hash11(stripId + time) - 0.5) * mouseEffect * jitter * 2.0;

    // mouse.x axis: horizontal proximity to each strip's displaced edge
    // subtly boosts that strip's drift — mouse-driven in both axes.
    let edgeProx = smoothstep(0.15, 0.0, abs(mouse.x - fract(uv.x + offset)));
    offset += (stripRand - 0.5) * edgeProx * jitter * 1.2;

    // Audio flicker: treble adds a faint per-strip shimmer on the drift so
    // the tracking breathes with the soundtrack (hash-timed at 12 Hz).
    let stripBin = (u32(abs(stripId)) % 8u) + 1u;
    let flicker = 1.0 + treble * 0.3 * (hash11(stripId * 3.7 + floor(time * 12.0)) - 0.5) * (1.0 + plasmaBuffer[stripBin].x * 0.2);
    offset *= flicker;

    // ── Click tracking tears ─────────────────────────────────────────
    // Each live ripple slams a hard horizontal tear onto the strips near
    // its click row: a one-shot offset spike decaying over ~0.8s, plus a
    // brief colorShift doubling while the tear is alive.
    var tear = 0.0;
    var tearChroma = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age <= 0.0 || age > 0.8) { continue; }
        let rowMask = smoothstep(0.08, 0.0, abs(uv.y - rp.y));
        let decay = 1.0 - age / 0.8;
        let slam = rowMask * decay * decay;
        // Tear direction hashed per strip per click — hard VHS slam.
        tear += slam * (hash11(stripId + rp.z * 7.31) - 0.5) * 2.0;
        tearChroma += slam;
    }
    offset += tear * 0.12;
    let colorShift = colorShiftBase * (1.0 + tearChroma);

    // Color separation
    let rOffset = offset + colorShift;
    let gOffset = offset;
    let bOffset = offset - colorShift;

    let rUV = vec2<f32>(fract(uv.x + rOffset), uv.y);
    let gUV = vec2<f32>(fract(uv.x + gOffset), uv.y);
    let bUV = vec2<f32>(fract(uv.x + bOffset), uv.y);

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Scanline darkness at strip boundaries
    let stripUVy = fract(uv.y / lineHeight);
    let lineDark = smoothstep(0.0, 0.1, stripUVy) * smoothstep(1.0, 0.9, stripUVy);

    var color = vec3<f32>(r, g, b);
    color *= mix(0.8, 1.0, lineDark);
    color = acesToneMap(color * (0.96 + bass * 0.04));

    let prevDrift = textureLoad(dataTextureC, coord, 0).rgb;
    color = mix(color, prevDrift, tearChroma * 0.08);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let driftMag = abs(rOffset - bOffset);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let effectIntensity = clamp(driftMag * 10.0 + mouseEffect * 0.3 + tearChroma * 0.3 + luma * 0.2, 0.0, 1.0);
    let finalAlpha = clamp(mix(baseColor.a, 1.0, effectIntensity * 0.7) + bass * 0.05, 0.0, 1.0);

    let depth = textureLoad(readDepthTexture, coord, 0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
