// ═══════════════════════════════════════════════════════════════════
//  CMYK Halftone Explosion
//  Category: advanced-hybrid
//  Features: mouse-driven, chromatic, prism, print-simulation
//  Complexity: High
//  Chunks From: cmyk-halftone-interactive.wgsl, mouse-chromatic-explosion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-9
// ═══════════════════════════════════════════════════════════════════
//  CMYK halftone dots are spectrally separated near the mouse via
//  prism displacement. Click ripples launch chromatic shockwaves
//  through the halftone pattern, scattering each ink channel.
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=AngleOffset, z=Spread, w=PrismStrength
  ripples: array<vec4<f32>, 50>,
};

fn rgb2cmyk(rgb: vec3<f32>) -> vec4<f32> {
  let k = 1.0 - max(rgb.r, max(rgb.g, rgb.b));
  if (k >= 1.0) {
    return vec4<f32>(0.0, 0.0, 0.0, 1.0);
  }
  let c = (1.0 - rgb.r - k) / (1.0 - k);
  let m = (1.0 - rgb.g - k) / (1.0 - k);
  let y = (1.0 - rgb.b - k) / (1.0 - k);
  return vec4<f32>(c, m, y, k);
}

fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
  let s = sin(a);
  let c = cos(a);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// ═══ CHUNK: prismDisplace (from mouse-chromatic-explosion.wgsl) ═══
fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
  let toMouse = uv - mousePos;
  let dist = length(toMouse);
  let prismAngle = atan2(toMouse.y, toMouse.x);
  let deflection = wavelengthOffset * strength / max(dist, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  return uv + perpendicular * deflection;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Parameters
  let density = 50.0 + u.zoom_params.x * 150.0;
  let baseAngle = u.zoom_params.y * 3.14159;
  let spread = u.zoom_params.z * 0.05;
  let prismStrength = mix(0.02, 0.12, u.zoom_params.w);
  let dispersion = 2.0;

  // Mouse interaction angles
  let interactAngle = (mousePos.x - 0.5) * 3.14159;
  let interactSpread = mousePos.y * 0.1;
  let finalSpread = spread + interactSpread;

  // ── Prism displacement per channel (from mouse-chromatic-explosion) ──
  // Each CMYK channel gets a different prism offset
  let cUV = prismDisplace(uv, mousePos, -1.5 * dispersion, prismStrength);
  let mUV = prismDisplace(uv, mousePos, -0.5 * dispersion, prismStrength);
  let yUV = prismDisplace(uv, mousePos, 0.5 * dispersion, prismStrength);
  let kUV = prismDisplace(uv, mousePos, 1.5 * dispersion, prismStrength);

  // Ripple chromatic shockwaves
  let rippleCount = min(u32(u.config.y), 50u);
  var cOffset = vec2<f32>(0.0);
  var mOffset = vec2<f32>(0.0);
  var yOffset = vec2<f32>(0.0);
  var kOffset = vec2<f32>(0.0);

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);

      // Different phases per channel for spectral scattering
      let cWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.8) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let mWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.3) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let yWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.3) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let kWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.8) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);

      cOffset = cOffset + dir * cWave * 0.03;
      mOffset = mOffset + dir * mWave * 0.03;
      yOffset = yOffset + dir * yWave * 0.03;
      kOffset = kOffset + dir * kWave * 0.03;
    }
  }

  let intensity = 1.0 + mouseDown * 1.5;

  // Sample source with per-channel UV distortion
  let srcColorC = textureSampleLevel(readTexture, u_sampler, cUV + cOffset * intensity, 0.0).rgb;
  let srcColorM = textureSampleLevel(readTexture, u_sampler, mUV + mOffset * intensity, 0.0).rgb;
  let srcColorY = textureSampleLevel(readTexture, u_sampler, yUV + yOffset * intensity, 0.0).rgb;
  let srcColorK = textureSampleLevel(readTexture, u_sampler, kUV + kOffset * intensity, 0.0).rgb;

  // Average the displaced samples for base color
  let baseColor = (srcColorC + srcColorM + srcColorY + srcColorK) * 0.25;
  let cmyk = rgb2cmyk(baseColor);

  // Standard halftone angles
  let angC = radians(15.0) + baseAngle + interactAngle;
  let angM = radians(75.0) + baseAngle + interactAngle;
  let angY = radians(0.0)  + baseAngle + interactAngle;
  let angK = radians(45.0) + baseAngle + interactAngle;

  // Offsets for spread (simulate misregistration) + prism displacement
  let offC = vec2<f32>(-1.0, 0.0) * finalSpread + (cUV - uv);
  let offM = vec2<f32>(1.0, 0.0) * finalSpread + (mUV - uv);
  let offY = vec2<f32>(0.0, -1.0) * finalSpread + (yUV - uv);
  let offK = vec2<f32>(0.0, 1.0) * finalSpread + (kUV - uv);

  var finalC = 0.0;
  var finalM = 0.0;
  var finalY = 0.0;
  var finalK = 0.0;

  // Cyan
  {
    let localUV = rotate((uv + offC) * vec2<f32>(aspect, 1.0), angC) * density;
    let grid = fract(localUV) - 0.5;
    let dist = length(grid);
    let radius = sqrt(cmyk.x) * 0.6;
    finalC = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
  }

  // Magenta
  {
    let localUV = rotate((uv + offM) * vec2<f32>(aspect, 1.0), angM) * density;
    let grid = fract(localUV) - 0.5;
    let dist = length(grid);
    let radius = sqrt(cmyk.y) * 0.6;
    finalM = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
  }

  // Yellow
  {
    let localUV = rotate((uv + offY) * vec2<f32>(aspect, 1.0), angY) * density;
    let grid = fract(localUV) - 0.5;
    let dist = length(grid);
    let radius = sqrt(cmyk.z) * 0.6;
    finalY = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
  }

  // Black
  {
    let localUV = rotate((uv + offK) * vec2<f32>(aspect, 1.0), angK) * density;
    let grid = fract(localUV) - 0.5;
    let dist = length(grid);
    let radius = sqrt(cmyk.w) * 0.6;
    finalK = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
  }

  // Composite Subtractive
  var color = vec3<f32>(1.0);
  let cColor = vec3<f32>(0.0, 1.0, 1.0);
  let mColor = vec3<f32>(1.0, 0.0, 1.0);
  let yColor = vec3<f32>(1.0, 1.0, 0.0);
  let kColor = vec3<f32>(0.0, 0.0, 0.0);

  let inkDarkness = 0.7;
  let mixC = mix(vec3<f32>(1.0), cColor, finalC * inkDarkness);
  let mixM = mix(vec3<f32>(1.0), mColor, finalM * inkDarkness);
  let mixY = mix(vec3<f32>(1.0), yColor, finalY * inkDarkness);
  let mixK = mix(vec3<f32>(1.0), kColor, finalK * inkDarkness);

  color = color * mixC * mixM * mixY * mixK;

  // Spectral glow near mouse
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  color = color + vec3<f32>(0.5, 0.3, 0.8) * glow;

  // Alpha = total chromatic displacement magnitude
  let totalDisp = length(cUV - mUV) + length(mUV - yUV) + length(yUV - kUV);
  let alpha = clamp(totalDisp * 5.0 + 0.8, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
