// ═══════════════════════════════════════════════════════════════════
//  Multi-Fractal Compositor + Gravitational Lens
//  Category: generative
//  Features: advanced-hybrid, mandelbrot, julia, mouse-driven, gravitational-lens, interactive
//  Complexity: Very High
//  Chunks From: multi-fractal-compositor, gravitational-lensing
//  Created: 2026-04-18
//  By: Agent CB-4 - Mouse Physics Injector
// ═══════════════════════════════════════════════════════════════════
//  Multi-layer fractal compositor with mouse-controlled gravitational
//  lensing. Mouse mass bends UV coordinates; ripples create temporary
//  mass concentrations. Einstein ring glow around mouse.
//  Alpha stores lens distortion strength.
// ═══════════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

fn ping_pong(a: f32) -> f32 {
  return (1.0 - abs(((fract((a * 0.5)) * 2.0) - 1.0)));
}

fn ping_pong_v2_(v: vec2<f32>) -> vec2<f32> {
  let _e2 = ping_pong(v.x);
  let _e4 = ping_pong(v.y);
  return vec2<f32>(_e2, _e4);
}

fn hash21_(p: vec2<f32>) -> f32 {
  var p3_ = fract((vec3<f32>(p.x, p.y, p.x) * 0.1031));
  let _e9 = p3_;
  let _e10 = p3_;
  let _e11 = p3_;
  p3_ = (_e9 + vec3(dot(_e10, (_e11 + vec3(33.33)))));
  let _e19 = p3_.x;
  let _e21 = p3_.y;
  let _e24 = p3_.z;
  return fract(((_e19 + _e21) * _e24));
}

fn noise(p_1: vec2<f32>) -> f32 {
  var i_1 = floor(p_1);
  let f = fract(p_1);
  let u2_ = ((f * f) * (vec2(3.0) - (2.0 * f)));
  let _e11 = i_1;
  let _e16 = hash21_((_e11 + vec2<f32>(0.0, 0.0)));
  let _e17 = i_1;
  let _e22 = hash21_((_e17 + vec2<f32>(1.0, 0.0)));
  let _e25 = i_1;
  let _e30 = hash21_((_e25 + vec2<f32>(0.0, 1.0)));
  let _e31 = i_1;
  let _e36 = hash21_((_e31 + vec2<f32>(1.0, 1.0)));
  return mix(mix(_e16, _e22, u2_.x), mix(_e30, _e36, u2_.x), u2_.y);
}

fn hsv2rgb(h: f32, s: f32, v_1: f32) -> vec3<f32> {
  var rgb = vec3(0.0);
  let c = (v_1 * s);
  let h6_ = (h * 6.0);
  let x = (c * (1.0 - abs(((fract(h6_) * 2.0) - 1.0))));
  if (h6_ < 1.0) {
    rgb = vec3<f32>(c, x, 0.0);
  } else {
    if (h6_ < 2.0) {
      rgb = vec3<f32>(x, c, 0.0);
    } else {
      if (h6_ < 3.0) {
        rgb = vec3<f32>(0.0, c, x);
      } else {
        if (h6_ < 4.0) {
          rgb = vec3<f32>(0.0, x, c);
        } else {
          if (h6_ < 5.0) {
            rgb = vec3<f32>(x, 0.0, c);
          } else {
            rgb = vec3<f32>(c, 0.0, x);
          }
        }
      }
    }
  }
  let _e40 = rgb;
  return (_e40 + vec3((v_1 - c)));
}

fn reconstruct_normal(uv_1: vec2<f32>, depth: f32) -> vec3<f32> {
  let _e5 = u.config.z;
  let _e9 = u.config.w;
  let resolution_1 = vec2<f32>(_e5, _e9);
  let _e14 = resolution_1.x;
  let _e18 = resolution_1.y;
  let offset = vec2<f32>((1.0 / _e14), (1.0 / _e18));
  let _e28 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 + vec2<f32>(offset.x, 0.0)), 0.0);
  let _e37 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 - vec2<f32>(offset.x, 0.0)), 0.0);
  let dx = (_e28.x - _e37.x);
  let _e47 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 + vec2<f32>(0.0, offset.y)), 0.0);
  let _e56 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 - vec2<f32>(0.0, offset.y)), 0.0);
  let dy = (_e47.x - _e56.x);
  let n = vec3<f32>(-(dx), -(dy), 1.0);
  return normalize(n);
}

fn schlickFresnel(cosTheta: f32, F0_: f32) -> f32 {
  return (F0_ + ((1.0 - F0_) * pow((1.0 - cosTheta), 5.0)));
}

fn calculateVolumetricAlpha(layerDepth: f32, fogDensity: f32, viewDotNormal: f32, accumulatedWeight: f32) -> f32 {
  let _e7 = schlickFresnel(max(0.0, viewDotNormal), 0.03);
  let fogAmount = exp(((-(layerDepth) * fogDensity) * 3.0));
  let depthAlpha = mix(0.95, 0.4, fogAmount);
  let weightAlpha = mix(0.5, 0.9, smoothstep(0.0, 1.0, accumulatedWeight));
  let alpha = ((depthAlpha * weightAlpha) * (1.0 - (_e7 * 0.2)));
  return clamp(alpha, 0.0, 1.0);
}

// ═══ CHUNK: gravitationalBend (from gravitational-lensing.wgsl) ═══
fn gravitationalBend(uv: vec2<f32>, massPos: vec2<f32>, mass: f32) -> vec2<f32> {
  let toMass = massPos - uv;
  let dist = length(toMass);
  let deflection = mass * toMass / (dist * dist + 0.001);
  return uv + deflection * 0.01;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = vec2<f32>(u.config.z, u.config.w);
  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  let zoom_time = u.zoom_config.x;
  let zoom_center = u.zoom_config.yz;
  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;

  var accumulatedColor = vec3(0.0);
  var accumulatedDepth = 0.0;
  var totalWeight = 0.0;

  // Gravitational lens parameters
  let lensMass = mix(0.5, 5.0, u.zoom_params.x);
  let ringGlowStrength = mix(0.0, 1.0, u.zoom_params.y);
  let rippleMass = mix(0.5, 3.0, u.zoom_params.z);
  let chromaBoost = mix(0.0, 0.05, u.zoom_params.w);

  // Compute total gravitational bend including ripples as temporary masses
  var bentUV = gravitationalBend(uv, mousePos, lensMass);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0) {
      let decay = exp(-elapsed * 0.8);
      let rippleBend = gravitationalBend(uv, ripple.xy, rippleMass * decay);
      bentUV = bentUV + (rippleBend - uv) * decay;
    }
  }

  var clickIntensity = 0.0;
  if (arrayLength((&extraBuffer)) > 10u) {
    clickIntensity = extraBuffer[10];
  }

  for (var i: i32 = 0; i < 5; i = i + 1) {
    let layerDepth_1 = (f32(i) / f32((5 - 1)));
    let layerSpeed = mix(u.zoom_params.x, u.zoom_params.y, layerDepth_1);
    let layerZoom = (1.0 + (fract((zoom_time * layerSpeed)) * 4.0));

    // Apply gravitational lens to the layer coordinates
    let lensedToCenter = (bentUV - zoom_center);
    let angle = atan2(lensedToCenter.y, lensedToCenter.x);
    let dist = length(lensedToCenter);

    let vortexStrength = ((clickIntensity * 0.3) / (dist + 0.1));
    let spinAngle = ((vortexStrength * layerDepth_1) * (1.0 - layerDepth_1));
    let rotatedUV = (vec2<f32>(
      ((cos(spinAngle) * lensedToCenter.x) - (sin(spinAngle) * lensedToCenter.y)),
      ((sin(spinAngle) * lensedToCenter.x) + (cos(spinAngle) * lensedToCenter.y))
    ) + zoom_center);

    let flowUV = (rotatedUV + ((vec2<f32>(
      noise(((rotatedUV * 6.0) + vec2<f32>((time * 0.15), 0.0))),
      noise(((rotatedUV * 6.0) + vec2<f32>(0.0, (time * 0.15))))
    ) * 0.015) * layerDepth_1));

    let transformed = (((flowUV - zoom_center) / vec2(layerZoom)) + zoom_center);
    let _e142 = ping_pong_v2_(transformed);
    let sampleColor = textureSampleLevel(readTexture, u_sampler, _e142, 0.0).xyz;
    let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, _e142, 0.0).x;

    let density = exp((-(layerDepth_1) * 1.5));
    let weight = (density * (1.0 + (sampleDepth * 0.5)));
    accumulatedColor = accumulatedColor + (sampleColor * weight);
    accumulatedDepth = accumulatedDepth + (sampleDepth * weight);
    totalWeight = totalWeight + weight;
  }

  let baseColor = (accumulatedColor / vec3(max(totalWeight, 0.0001)));
  let baseDepth = (accumulatedDepth / max(totalWeight, 0.0001));

  var chroma = 0.02;
  if (arrayLength((&extraBuffer)) > 0u) {
    chroma = extraBuffer[0];
  }

  // Enhanced chromatic aberration from lens distortion
  let effectiveChroma = chroma + chromaBoost * lensMass;

  let r = textureSampleLevel(readTexture, u_sampler, (uv + vec2<f32>((effectiveChroma * baseDepth), 0.0)), 0.0).x;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).y;
  let b = textureSampleLevel(readTexture, u_sampler, (uv - vec2<f32>((effectiveChroma * baseDepth), 0.0)), 0.0).z;
  var chromaticColor = vec3<f32>(r, g, b);

  let ps = vec2<f32>((1.0 / resolution.x), (1.0 / resolution.y));
  let depthX = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv + vec2<f32>(ps.x, 0.0)), 0.0).x;
  let depthY = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv + vec2<f32>(0.0, ps.y)), 0.0).x;
  let depthGrad = length(vec2<f32>((depthX - baseDepth), (depthY - baseDepth)));
  let edgeGlow = ((exp((-(depthGrad) * 30.0)) * baseDepth) * 2.0);
  var finalColor = (chromaticColor + vec3<f32>(edgeGlow, (edgeGlow * 0.8), (edgeGlow * 0.6)));

  // Einstein ring glow around mouse
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(toMouse);
  let einsteinRadius = sqrt(lensMass * 0.02);
  let ringGlow = smoothstep(0.5, 0.0, abs(mouseDist - einsteinRadius)) * ringGlowStrength;
  finalColor = finalColor + vec3<f32>(0.9, 0.8, 0.6) * ringGlow;

  // Core glow
  let coreGlow = exp(-mouseDist * mouseDist * 400.0) * lensMass * 0.3;
  finalColor = finalColor + vec3<f32>(0.6, 0.9, 1.0) * coreGlow;

  let fogDensity_1 = u.zoom_params.w;
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal_1 = dot(viewDir, reconstruct_normal(uv, baseDepth));
  let normalizedWeight = (totalWeight / f32(5));
  let alpha = calculateVolumetricAlpha(0.5, fogDensity_1, viewDotNormal_1, normalizedWeight);
  let fog = exp(((-(baseDepth) * fogDensity_1) * 3.0));
  let fogColor = vec3<f32>(0.02, 0.05, 0.1);
  let outColor = mix(finalColor, fogColor, (1.0 - fog));

  // Alpha enhanced by lens strength
  let outAlpha = clamp(alpha + ringGlow * 0.2, 0.0, 1.0);

  textureStore(writeTexture, vec2<u32>(gid.xy), vec4<f32>(outColor, outAlpha));
  textureStore(writeDepthTexture, vec2<u32>(gid.xy), vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
