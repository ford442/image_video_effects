// ═══════════════════════════════════════════════════════════════════
//  CMYK Halftone Explosion
//  Category: advanced-hybrid
//  Features: mouse-driven, chromatic, prism, print-simulation, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-01
//  Ideas: black plate holds registration; shock-stretched halftone dots
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  CMYK halftone dots are spectrally separated near the mouse via
//  prism displacement. Click ripples launch chromatic shockwaves
//  through the halftone pattern, scattering each ink channel.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Density, y=AngleOffset, z=Spread, w=PrismStrength

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Round cell when the shock is quiet; an ellipse along the shock when a click front passes.
fn screenDot(uv: vec2<f32>, ang: f32, off: vec2<f32>, ink: f32, density: f32, aspect: f32, shockDir: vec2<f32>, stretch: f32, shockLen: f32) -> f32 {
  let localUV = rotate((uv + off) * vec2<f32>(aspect, 1.0), ang) * density;
  let grid = fract(localUV) - 0.5;
  let roundDist = length(grid);
  let axis = rotate(shockDir, ang);
  let axisN = axis / max(length(axis), 1e-4);
  let tangent = vec2<f32>(-axisN.y, axisN.x);
  let ellDist = length(vec2<f32>(dot(grid, axisN) / max(stretch, 1.0), dot(grid, tangent)));
  let dist = select(roundDist, ellDist, shockLen > 0.002);
  let radius = sqrt(max(ink, 0.0)) * 0.6;
  return 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
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

@compute @workgroup_size(16, 16, 1)
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
  // ── Idea 1: black plate holds registration. CMY throw is unchanged.
  let kUV = prismDisplace(uv, mousePos, 0.45 * dispersion, prismStrength);

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
      kOffset = kOffset + dir * kWave * 0.03 * 0.35;
    }
  }

  let intensity = 1.0 + mouseDown * 1.5;

  // Sample source with per-channel UV distortion
  let srcColorC = textureSampleLevel(readTexture, u_sampler, clamp(cUV + cOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let srcColorM = textureSampleLevel(readTexture, u_sampler, clamp(mUV + mOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let srcColorY = textureSampleLevel(readTexture, u_sampler, clamp(yUV + yOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let srcColorK = textureSampleLevel(readTexture, u_sampler, clamp(kUV + kOffset * intensity, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

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

  // ── Idea 2: dots stretch along the summed shock. Quiet frames stay round.
  let shock = cOffset + mOffset + yOffset + kOffset;
  let shockLen = length(shock);
  let shockDir = shock / max(shockLen, 1e-4);
  let stretch = 1.0 + shockLen * 22.0;

  let finalC = screenDot(uv, angC, offC, cmyk.x, density, aspect, shockDir, stretch, shockLen);
  let finalM = screenDot(uv, angM, offM, cmyk.y, density, aspect, shockDir, stretch, shockLen);
  let finalY = screenDot(uv, angY, offY, cmyk.z, density, aspect, shockDir, stretch, shockLen);
  let finalK = screenDot(uv, angK, offK, cmyk.w, density, aspect, shockDir, stretch, shockLen);

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

  let totalDisp = length(cUV - mUV) + length(mUV - yUV) + length(yUV - kUV);
  let inkCover = clamp((finalC + finalM + finalY + finalK) * 0.25, 0.0, 1.0);
  let alpha = clamp(inkCover * 0.65 + totalDisp * 2.5 + glow * 0.35, 0.0, 1.0);
  let display = acesToneMap(max(color, vec3<f32>(0.0)));
  let coord = vec2<i32>(global_id.xy);
  let outColor = vec4<f32>(display, alpha);

  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
