// ═══════════════════════════════════════════════════════════════════
//  Quantum Tunnel Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: log-z pulse rings; wavelength-scaled twist
//  A packing: ACES display RGBA
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let texel = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001));
    let aspect = resolution.x / max(resolution.y, 0.001);

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let time = u.config.x;

    let mouseDown = u.zoom_config.w;
    let tunnelStrength = clamp(u.zoom_params.x * (1.0 + bass * 0.2) * (1.0 + mouseDown * 0.25), 0.0, 1.0);
    let aberration     = clamp(u.zoom_params.y * (1.0 + mids * 0.15), 0.0, 1.0);
    let pulseSpeed     = clamp(u.zoom_params.z * (1.0 + treble * 0.1), 0.0, 1.0);
    let spiral         = u.zoom_params.w;

    // Existing spring kept: position [133..134], velocity [135..136], time [137], flag [138]
    let mouse = u.zoom_config.yz;
    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var center = mouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
      center = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
      var springPos = center;
      var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
      if (extraBuffer[138] <= 0.5) {
        springPos = mouse;
        springVel = vec2<f32>(0.0);
      } else {
        let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
        let omega = 8.0;
        let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
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

    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
    let centerAspect = vec2<f32>(center.x * aspect, center.y);
    let offset = uvAspect - centerAspect;
    let dist = length(offset);
    let angle = atan2(offset.y, offset.x);

    var rippleTwist = 0.0;
    var rippleGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
      let rp = u.ripples[i];
      let age = time - rp.z;
      let safeAge = max(age, 0.0);
      let live = step(0.0, age) * (1.0 - step(1.8, age));
      let clickOffset = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
      let clickDist = length(clickOffset);
      let ring = 1.0 - smoothstep(0.018, 0.055, abs(clickDist - safeAge * 0.32));
      let fade = exp(-safeAge * 1.7) * live;
      let direction = select(-1.0, 1.0, fract(rp.x * 17.0 + rp.y * 31.0) > 0.5);
      rippleTwist += ring * fade * direction;
      rippleGlow = max(rippleGlow, ring * fade);
    }

    let audioPulse = 1.0 + bass * 0.5;
    // Idea 1 — log-z pulse so rings recede
    let logZ = -log(max(dist, 0.001));
    let pulse = sin(logZ * 8.0 - time * (pulseSpeed * 10.0 * audioPulse)) * 0.05 * tunnelStrength;

    let twistAngle = angle + (1.0 - smoothstep(0.0, 1.0, dist)) * (spiral * 5.0) * sin(time) + rippleTwist * 1.4 + pulse * 4.0;

    let zoom = 1.0 - (tunnelStrength * 0.5 * smoothstep(1.0, 0.0, dist)) + pulse;

    let sector = u32(floor(fract((angle + 3.14159265) / 6.2831853) * 8.0));
    let fftVoice = plasmaBuffer[(sector % 8u) + 1u].x;
    let abbrScale = aberration * 0.05 * dist * (1.0 + fftVoice * 0.35);

    let rR = dist * (zoom - abbrScale);
    let rG = dist * zoom;
    let rB = dist * (zoom + abbrScale);

    // Idea 2 — wavelength-scaled twist on the same twistAngle
    let waveTwist = aberration * 0.22;
    let twistR = twistAngle + waveTwist;
    let twistB = twistAngle - waveTwist;

    let offR = vec2<f32>(cos(twistR), sin(twistR)) * rR;
    let offG = vec2<f32>(cos(twistAngle), sin(twistAngle)) * rG;
    let offB = vec2<f32>(cos(twistB), sin(twistB)) * rB;

    let uvR = clamp(vec2<f32>(offR.x / aspect, offR.y) + center, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(vec2<f32>(offG.x / aspect, offG.y) + center, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(vec2<f32>(offB.x / aspect, offB.y) + center, vec2<f32>(0.0), vec2<f32>(1.0));

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let cR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let cG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let cB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    let luminance = dot(vec3<f32>(cR, cG, cB), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luminance + tunnelStrength * 0.3 + abs(pulse) * 2.0 + src.a * 0.2, 0.0, 1.0);
    var color = vec3<f32>(cR, cG, cB);

    let glow = 1.0 - smoothstep(0.0, 0.1, dist);
    let glowColor = vec3<f32>(0.2, 0.4, 1.0) * (1.0 + bass * 2.0);
    color = color + glowColor * (glow * tunnelStrength + rippleGlow * 0.45);

    let peak = max(max(color.r, color.g), color.b);
    color = color * min(1.0, 1.8 / max(peak, 0.001));
    color = acesToneMap(color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOut = clamp(depth - (glow * tunnelStrength + rippleGlow) * 0.06, 0.0, 1.0);
    let outCol = vec4<f32>(color, alpha);

    textureStore(writeTexture, texel, outCol);
    textureStore(dataTextureA, texel, outCol);
    textureStore(writeDepthTexture, texel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
