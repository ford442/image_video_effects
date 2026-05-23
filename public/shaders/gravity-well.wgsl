// ═══════════════════════════════════════════════════════════════════
//  Gravity Well
//  Category: distortion
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven, photon-sphere, relativistic-doppler
//  Complexity: Very High
//  Scientific: Schwarzschild-like radial lensing with photon-sphere rings, gravitational redshift, and Doppler-bright accretion flow.
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn sampleColor(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn sampleDepth(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 15000.0);
  let tt = t / 100.0;
  var r = 1.0;
  var g = 1.0;
  var b = 1.0;

  if (t <= 6600.0) {
    r = 1.0;
    g = 0.39008157 * log(tt) - 0.63184144;
    if (t < 2000.0) {
      b = 0.0;
    } else {
      b = 0.54320679 * log(max(tt - 10.0, 0.01)) - 1.19625408;
    }
  } else {
    r = 1.29293618 * pow(tt - 60.0, -0.1332047592);
    g = 1.12989086 * pow(tt - 60.0, -0.0755148492);
    b = 1.0;
  }

  return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
  let uv = vec2<f32>(global_id.xy) / resolution;
  let center = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;

  let rs = max(0.008, mix(0.015, 0.10, u.zoom_params.x));
  let diskOuter = rs * mix(3.5, 8.5, u.zoom_params.y);
  let flareGain = mix(0.5, 2.5, u.zoom_params.z);
  let higherOrder = mix(0.2, 1.2, u.zoom_params.w);

  let aspect = resolution.x / max(resolution.y, 1.0);
  let pos = vec2<f32>((uv.x - center.x) * aspect, uv.y - center.y);
  let r = length(pos);
  let radialDir = pos / max(r, 1e-4);
  let impact = max(r, rs * 1.02);
  let deflection = clamp(4.0 * rs / impact + higherOrder * 6.0 * rs * rs / (impact * impact), 0.0, 3.0);
  let sourceRadius = r + deflection * rs * 0.55;
  let sampleUV = center + vec2<f32>(radialDir.x * sourceRadius / aspect, radialDir.y * sourceRadius);

  let background = sampleColor(sampleUV);
  let backgroundDepth = sampleDepth(sampleUV);

  let gravRedshift = 1.0 / sqrt(max(1.0 - rs / max(r, rs * 1.02), 0.05)) - 1.0;
  let redTint = clamp(vec3<f32>(1.0 + gravRedshift * 0.35, 0.95, 1.0 - gravRedshift * 0.45), vec3<f32>(0.0), vec3<f32>(2.0));

  let photonSphere = 1.5 * rs;
  let bCrit = rs * 2.59807621135;
  let photonRing = exp(-pow((r - photonSphere) / max(rs * 0.12, 0.001), 2.0));
  let einsteinRing = exp(-pow((r - bCrit) / max(rs * 0.18, 0.001), 2.0));
  let secondaryImage = exp(-pow((r - bCrit * 1.35) / max(rs * 0.24, 0.001), 2.0)) * smoothstep(0.8, 2.5, deflection);

  let tiltAngle = 0.55;
  let ct = cos(tiltAngle);
  let st = sin(tiltAngle);
  let diskX = ct * pos.x - st * pos.y;
  let diskY = st * pos.x + ct * pos.y;
  let diskPlane = vec2<f32>(diskX, diskY * 0.25);
  let diskRadius = length(diskPlane);
  let diskMask = smoothstep(rs * 1.45, rs * 1.85, diskRadius) * (1.0 - smoothstep(diskOuter * 0.75, diskOuter, diskRadius)) * exp(-abs(diskY) / max(rs * 0.18, 0.001));

  let beta = sqrt(clamp(0.5 * rs / max(diskRadius, rs * 1.5), 0.0, 0.92));
  let gamma = 1.0 / sqrt(max(1.0 - beta * beta, 0.05));
  var tangent = vec2<f32>(1.0, 0.0);
  if (diskRadius > 1e-4) {
    tangent = vec2<f32>(-diskPlane.y, diskPlane.x) / diskRadius;
  }
  let approachingDir = normalize(vec2<f32>(-0.9, -0.35));
  let cosPhi = dot(tangent, approachingDir);
  let doppler = clamp(1.0 / (gamma * max(1.0 - beta * cosPhi, 0.1)), 0.4, 2.8);
  let gravFactor = sqrt(max(1.0 - rs / max(diskRadius, rs * 1.05), 0.03));
  let radialNorm = clamp((diskRadius - rs * 1.6) / max(diskOuter - rs * 1.6, 0.001), 0.0, 1.0);
  let localTemp = mix(11000.0, 1800.0, radialNorm);
  let observedTemp = localTemp * doppler * gravFactor;
  let flare = 1.0 + flareGain * bass * smoothstep(0.0, 1.0, max(cosPhi, 0.0));
  let diskEmission = blackbodyRGB(observedTemp) * diskMask * pow(doppler, 3.0) * gravFactor * flare * 1.4;

  let ringColor = blackbodyRGB(10500.0) * (einsteinRing * 1.8 + photonRing * 1.2 * (1.0 + bass * 0.4));
  let secondaryColor = blackbodyRGB(6500.0) * secondaryImage * 0.45;
  let shadow = 1.0 - smoothstep(rs * 0.95, rs * 1.10, r);

  let finalColor = background.rgb * redTint * (1.0 - shadow) + ringColor + secondaryColor + diskEmission;
  let finalAlpha = clamp(max(background.a, diskMask * 0.55 + einsteinRing * 0.35 + shadow), 0.0, 1.0);
  let outDepth = clamp(backgroundDepth * (1.0 - shadow) + shadow, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(dataTextureA, coord, vec4<f32>(deflection / 3.0, einsteinRing + photonRing, diskMask, shadow));
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
