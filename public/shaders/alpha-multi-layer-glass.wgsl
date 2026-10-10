// ═══════════════════════════════════════════════════════════════════
//  Alpha Multi-Layer Glass — Refractive Glass Stack
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, multi-layer-glass, fresnel,
//            chromatic-aberration, frosted-glass, beer-lambert, semantic-transmittance, ACES
//  Ideas:    1. per-pane surfaces — each pane has its own normal seed and sits at its own
//               depth, so panes slide against each other (parallax around the cursor)
//            2. frosting — roughness is a rotated 4-tap scatter blur, not hash grain
//            3. Beer-Lambert pane edges — long paths through steep glass turn green
//  Complexity: High
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let sm = f * f * (3.0 - 2.0 * f);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, sm.x), mix(c, d, sm.x), sm.y);
}

fn fbm2(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var freq = 1.0;
  for (var i = 0; i < 3; i = i + 1) {
    v += a * valueNoise(p * freq);
    a *= 0.5;
    freq *= 2.0;
  }
  return v;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Sliders: exact parameter contracts
  let iorParam = u.zoom_params.x;     // 0..1, def 0.5 -> IOR 1.1 to 1.7
  let thickParam = u.zoom_params.y;   // 0..1, def 0.3 -> thickness
  let chromParam = u.zoom_params.z;   // 0..1, def 0.3 -> chromatic dispersion
  let roughParam = u.zoom_params.w;   // 0..1, def 0.4 -> surface roughness

  let iorBase = mix(1.15, 1.75, iorParam);
  let thickness = mix(0.003, 0.025, thickParam);
  let chromaticStrength = chromParam * (0.008 + mids * 0.006);
  let roughness = roughParam * (0.012 + treble * 0.008);

  // Raw pointer: the old extraBuffer[133..138] spring raced (pixel (0,0) wrote
  // while every other pixel read) and the buffer is re-uploaded each frame.
  let mouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Touch deflection & pointer influence
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let mouseInfluence = smoothstep(0.35, 0.0, mouseDist) * (0.5 + held * 0.5);
  let mouseNormal = normalize(uv - mouse + vec2<f32>(0.0001));

  // Click ripple shocks on glass surface
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleNormal = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let wave = sin((rDist - age * 0.6) * 40.0) * exp(-rDist * 4.5) * exp(-age * 1.6);
    let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
    rippleNormal += dir * wave * 0.4;
  }

  // Acoustic plate vibration rides on the front pane and fades into the stack.
  let plateWave = sin(uv.x * 20.0 + time * 2.0) * sin(uv.y * 20.0 - time * 1.5) * bass * 0.4;

  // Frost taps are rotated per pixel, so the scatter reads as ground glass.
  let frostAngle = hash12(vec2<f32>(gid.xy)) * 6.2831853;
  let frostRot = mat2x2<f32>(cos(frostAngle), sin(frostAngle), -sin(frostAngle), cos(frostAngle));

  // Multi-layer glass refraction stack (3 distinct physical panes)
  var totalTransmittance = 1.0;
  var accumulatedColor = vec3<f32>(0.0);
  var weightSum = 0.0;
  var specularTotal = 0.0;

  for (var layer = 0; layer < 3; layer = layer + 1) {
    let layerF = f32(layer);
    let ior = iorBase + layerF * 0.08;

    // Idea 1: per-pane surfaces. Each pane has its own noise seed and drift, and
    // deeper panes are seen through a parallax shift away from the cursor, as if
    // the pointer were the eye. Panes now slide against each other instead of
    // sharing a single normal.
    let parallaxUV = uv + (uv - mouse) * layerF * 0.035;
    let seed = vec2<f32>(19.7, 7.3) * layerF;
    let noiseUV = parallaxUV * (3.5 + layerF * 0.6) + seed
                + vec2<f32>(time * 0.015, time * 0.01) * (1.0 - layerF * 0.3);
    let normalX = (fbm2(noiseUV) - 0.5) * 2.0 + plateWave / (1.0 + layerF);
    let normalY = (fbm2(noiseUV + vec2<f32>(43.12, 17.89)) - 0.5) * 2.0;
    let surfaceNormal = normalize(vec2<f32>(normalX, normalY));
    let combinedNormal = normalize(mix(surfaceNormal, mouseNormal, mouseInfluence * 0.6));
    let paneNormal = normalize(combinedNormal + rippleNormal * 0.5);

    // Schlick Fresnel
    let r0 = (1.0 - ior) / (1.0 + ior);
    let R0 = r0 * r0;
    let cosI = clamp(abs(paneNormal.y * 0.8 + 0.2), 0.0, 1.0);
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cosI, 5.0);
    let layerTransmittance = clamp(1.0 - fresnel * 0.65, 0.05, 1.0);

    // Refraction offset per pane with physical dispersion
    let paneOffset = paneNormal * thickness * (layerF + 1.0);
    let refractR = uv + paneOffset * (1.0 + chromaticStrength * 1.5);
    let refractG = uv + paneOffset;
    let refractB = uv + paneOffset * (1.0 - chromaticStrength * 1.5);

    // Idea 2: frosting. Roughness scatters each channel over a rotated 4-tap
    // footprint that widens with pane depth, which is how ground glass blurs.
    let frostR = roughness * (layerF + 1.0) * 0.7;
    var sampled = vec3<f32>(0.0);
    for (var k = 0; k < 4; k = k + 1) {
      let kf = f32(k);
      let tap = frostRot * vec2<f32>(cos(kf * 1.5708 + 0.785), sin(kf * 1.5708 + 0.785)) * frostR
              * vec2<f32>(1.0 / aspect, 1.0);
      sampled.r += textureSampleLevel(readTexture, u_sampler, clamp(refractR + tap, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
      sampled.g += textureSampleLevel(readTexture, u_sampler, clamp(refractG + tap, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
      sampled.b += textureSampleLevel(readTexture, u_sampler, clamp(refractB + tap, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    }
    sampled *= 0.25;

    // Physical absorption tint per pane (Beer-Lambert law)
    let tint = vec3<f32>(
      1.0 - layerF * 0.08,
      1.0 - layerF * 0.03,
      0.95 + layerF * 0.02
    );

    // Idea 3: Beer-Lambert pane edges. Where the pane surface is steep, the
    // path through the glass is long and iron-green absorption builds up, like
    // the edge of a window pane.
    // Only the extra path beyond face-on absorbs, so flat glass stays clear.
    let pathLen = thickParam * (0.4 + layerF * 0.3) * (1.0 / max(cosI, 0.2) - 1.0);
    let edgeTint = exp(-vec3<f32>(0.55, 0.12, 0.40) * pathLen);

    let layerColor = sampled * tint * edgeTint;
    let w = totalTransmittance * layerTransmittance;
    accumulatedColor += layerColor * w;
    weightSum += w;
    totalTransmittance *= layerTransmittance;

    // Specular glint on pane surface
    let lightDir = normalize(vec2<f32>(0.7, -0.7));
    let spec = pow(max(dot(paneNormal, lightDir), 0.0), mix(25.0, 8.0, roughParam)) * fresnel;
    specularTotal += spec * (0.35 + treble * 0.25);
  }

  // Panes are averaged by their transmitted weight (HEAD summed ~2.7x and blew
  // out), then dimmed by what the stack actually passes.
  accumulatedColor = accumulatedColor / max(weightSum, 1e-4) * (0.6 + 0.4 * totalTransmittance);
  accumulatedColor += vec3<f32>(1.0, 0.98, 0.95) * specularTotal;

  // ACES tonemap, then internal multi-bounce reflection from the exact
  // dataTextureC load, mixed in display space (C holds ACES output).
  let prevInternal = textureLoad(dataTextureC, pixel, 0).rgb;
  let finalRGB = mix(aces(accumulatedColor), prevInternal, 0.08 + thickParam * 0.05);

  // Semantic transmittance alpha
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalAlpha = clamp(totalTransmittance * 0.75 + (1.0 - totalTransmittance) * 0.95 + mouseInfluence * 0.1, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
