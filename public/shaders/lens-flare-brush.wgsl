// Lens Flare Brush — interactive brush igniting anamorphic streaks and multi-element flares from image highlights.
// A/C stores ACES display RGBA for continuous brush trail persistence; B is unused; depth passes through source depth.

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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let threshold = 0.35 + u.zoom_params.x * 0.55;
  let intensity = (0.25 + u.zoom_params.y * 2.2) * (1.0 + bass * 0.45);
  let stretch = 0.15 + u.zoom_params.z * 1.5;
  let colorShift = 0.05 + u.zoom_params.w * 0.85;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mouse = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // Click ripple interaction
  var rippleOffset = vec2<f32>(0.0);
  var ripplePulse = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.34 + bass * 0.1);
      let wave = sin((rd - front) * 62.0) * exp(-abs(rd - front) * 27.0) * exp(-age * 1.15);
      rippleOffset += rDelta / max(rd, 0.0001) * wave * 0.02;
      ripplePulse += abs(wave) * 0.2;
    }
  }

  // Brush localized influence around cursor
  let mouseDist = length((uv - mouse) * aspectVec);
  let brushRadius = (0.12 + u.zoom_params.z * 0.08) * select(1.0, 1.5, held);
  let brushFalloff = exp(-mouseDist * mouseDist / (brushRadius * brushRadius));

  // Sample underlying source color at mouse cursor
  let mouseSample = textureSampleLevel(readTexture, u_sampler, mouse, 0.0).rgb;
  let mouseLuma = dot(mouseSample, vec3<f32>(0.2126, 0.7152, 0.0722));
  let lumaGate = smoothstep(threshold, threshold + 0.2, mouseLuma);

  // Core flare at mouse cursor
  let coreGlow = exp(-mouseDist * mouseDist * 60.0) * intensity * (0.4 + lumaGate * 0.8);
  let coreColor = vec3<f32>(1.0, 0.94, 0.82) * coreGlow;

  // Anamorphic horizontal streak with chromatic shift
  let streakDelta = (uv - mouse + rippleOffset) * aspectVec;
  let streakY = exp(-streakDelta.y * streakDelta.y * 350.0);
  let streakX = exp(-abs(streakDelta.x) / max(stretch * (0.2 + bass * 0.1), 0.01));
  let streakBase = streakY * streakX * intensity * (0.3 + lumaGate * 0.7);

  // Rainbow chromatic shift on anamorphic streak
  let streakPhase = streakDelta.x * 20.0 * colorShift + time * 0.5;
  let streakRainbow = vec3<f32>(
    0.5 + 0.5 * cos(streakPhase),
    0.5 + 0.5 * cos(streakPhase + 2.094),
    0.5 + 0.5 * cos(streakPhase + 4.188)
  );
  let streakColor = (vec3<f32>(0.7, 0.85, 1.0) * 0.6 + streakRainbow * 0.4) * streakBase;

  // Orbital ghost flares around brush
  var ghostAccum = vec3<f32>(0.0);
  let numGhosts = 5;
  for (var g = 0; g < numGhosts; g = g + 1) {
    let fg = f32(g);
    let ghostOffset = vec2<f32>(
      sin(fg * 1.4 + time * 0.3) * (0.12 + fg * 0.04) * stretch,
      cos(fg * 1.1 + time * 0.25) * (0.08 + fg * 0.03)
    );
    let ghostPos = mouse + ghostOffset / aspectVec + rippleOffset;
    let gDist = length((uv - ghostPos) * aspectVec);
    let gRadius = 0.03 + fg * 0.01;
    let gGlow = exp(-gDist * gDist / (gRadius * gRadius));

    let gHue = fg * 1.25 + colorShift * 3.14 + mids;
    let gColor = vec3<f32>(
      0.5 + 0.5 * sin(gHue),
      0.5 + 0.5 * sin(gHue + 2.094),
      0.5 + 0.5 * sin(gHue + 4.188)
    );
    ghostAccum += gColor * gGlow * intensity * 0.22 * (0.3 + lumaGate * 0.7);
  }

  // Diffraction starburst blades at cursor
  let toBrush = (uv - mouse) * aspectVec;
  let brushAngle = atan2(toBrush.y, toBrush.x);
  let spike = pow(max(0.0, sin(brushAngle * 6.0 + time)), 12.0) * exp(-mouseDist * 14.0) * (0.4 + treble * 0.3);
  let spikeColor = vec3<f32>(1.0, 0.9, 0.75) * spike * intensity;

  let flareTotal = (coreColor + streakColor + ghostAccum + spikeColor + vec3<f32>(ripplePulse)) * brushFalloff;

  // Exact previous frame history load for brush strokes
  let history = historyAt(uv - rippleOffset * 0.5, resolution);

  var hdr = sourceColor.rgb + flareTotal;
  hdr += history.rgb * 0.065;

  let flareLuma = dot(flareTotal, vec3<f32>(0.2126, 0.7152, 0.0722));
  let finalAlpha = clamp(sourceColor.a * 0.5 + flareLuma * 0.5 + ripplePulse * 0.1, 0.0, 1.0);

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), finalAlpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
