// ═══════════════════════════════════════════════════════════════════
//  Liquid Touch
//  Category: interactive-mouse
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: High
//  Scientific: Young-Laplace capillary flow with curvature-driven surface tension, dispersive capillary waves, Marangoni convection, and touch-induced droplet coalescence
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

const PI: f32 = 3.14159265359;

fn clampUV(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let len2 = dot(v, v);
  if (len2 < 1e-8) {
    return vec2<f32>(0.0, 0.0);
  }
  return v * inverseSqrt(len2);
}

fn sampleState(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(dataTextureC, non_filtering_sampler, clampUV(uv), 0.0);
}

fn surfaceNormal(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
  let leftPhi = sampleState(uv - vec2<f32>(texel.x, 0.0)).r;
  let rightPhi = sampleState(uv + vec2<f32>(texel.x, 0.0)).r;
  let upPhi = sampleState(uv - vec2<f32>(0.0, texel.y)).r;
  let downPhi = sampleState(uv + vec2<f32>(0.0, texel.y)).r;
  let grad = vec2<f32>((rightPhi - leftPhi) / (2.0 * texel.x), (downPhi - upPhi) / (2.0 * texel.y));
  return safeNormalize(grad);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let texel = 1.0 / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let gamma = mix(0.02, 1.2, clamp(u.zoom_params.x, 0.0, 1.0));
  let radius = 0.015 + 0.09 * clamp(u.zoom_params.y, 0.0, 1.0);
  let optical = 0.5 + 3.0 * clamp(u.zoom_params.z, 0.0, 1.0);
  let marangoni = clamp(u.zoom_params.w, 0.0, 1.0);
  let rho = 1.0;

  let center = sampleState(uv);
  let left = sampleState(uv - vec2<f32>(texel.x, 0.0));
  let right = sampleState(uv + vec2<f32>(texel.x, 0.0));
  let up = sampleState(uv - vec2<f32>(0.0, texel.y));
  let down = sampleState(uv + vec2<f32>(0.0, texel.y));

  var phi = center.r;
  var velocity = center.g;
  var temperature = center.b * 0.985;

  let gradPhi = vec2<f32>((right.r - left.r) / (2.0 * texel.x), (down.r - up.r) / (2.0 * texel.y));
  let interfaceDelta = length(gradPhi);
  let laplacian = (left.r + right.r + up.r + down.r - 4.0 * center.r) / max(texel.x * texel.y, 1e-6);

  let normalCenter = safeNormalize(gradPhi);
  let normalLeft = surfaceNormal(uv - vec2<f32>(texel.x, 0.0), texel);
  let normalRight = surfaceNormal(uv + vec2<f32>(texel.x, 0.0), texel);
  let normalUp = surfaceNormal(uv - vec2<f32>(0.0, texel.y), texel);
  let normalDown = surfaceNormal(uv + vec2<f32>(0.0, texel.y), texel);
  let curvature = ((normalRight.x - normalLeft.x) / (2.0 * texel.x)) + ((normalDown.y - normalUp.y) / (2.0 * texel.y));

  let gradTemperature = vec2<f32>((right.b - left.b) / (2.0 * texel.x), (down.b - up.b) / (2.0 * texel.y));
  let surfaceTensionForce = gamma * curvature * interfaceDelta;
  let marangoniForce = -dot(gradTemperature, normalCenter) * (0.01 + 0.05 * marangoni);

  let localK = clamp(interfaceDelta * 0.08 + abs(curvature) * 0.6, 0.001, 18.0);
  let capillaryOmega = sqrt(max((gamma / rho) * localK * localK * localK, 0.0001));
  let capillaryWave = sin(capillaryOmega * time * 1.5 + curvature * 0.15) * (0.004 + 0.012 * treble) * smoothstep(0.04, 0.4, interfaceDelta);
  let gravityWave = laplacian * 0.000004 + bass * sin(time * 1.8 + dot(uv, vec2<f32>(7.0, 4.0))) * 0.008;

  let mouse = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
  let toMouse = (uv - mouse) * aspectVec;
  let mouseDist = length(toMouse);
  let touchEnvelope = exp(-(mouseDist * mouseDist) / max(radius * radius, 1e-5)) * mouseDown;
  phi -= touchEnvelope * (0.06 + 0.18 * gamma);
  velocity -= touchEnvelope * 0.025;
  temperature += touchEnvelope * (0.02 + 0.14 * marangoni);

  var dropletDrive = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 5.0) {
      continue;
    }
    let delta = (uv - ripple.xy) * aspectVec;
    let r = length(delta);
    let envelope = exp(-r * 10.0 - age * 0.9);
    let naturalOscillation = sin(age * (4.5 + 10.0 * sqrt(gamma)) - r * 55.0);
    dropletDrive += envelope * naturalOscillation;
  }

  let mergeSignal = smoothstep(0.10, 0.55, abs(dropletDrive) + interfaceDelta * 0.025);
  let coalescence = sin(time * (8.0 + 10.0 * sqrt(gamma)) + center.a * 6.28318) * mergeSignal * 0.018;

  velocity *= max(0.86, 0.992 - 0.02 * gamma);
  velocity += surfaceTensionForce * 0.0012 + marangoniForce + gravityWave + capillaryWave + dropletDrive * 0.012 + coalescence;
  phi = mix(phi + velocity, (left.r + right.r + up.r + down.r) * 0.25, clamp(0.015 + gamma * 0.01, 0.0, 0.06));

  temperature = clamp(temperature + bass * 0.01 + treble * sin(dot(uv, vec2<f32>(90.0, 85.0)) - time * 20.0) * 0.01, -1.0, 1.0);

  let refractOffset = gradPhi * optical * 0.015;
  let sampleUV = clampUV(uv - refractOffset);
  let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;

  let normal3 = normalize(vec3<f32>(-gradPhi.x * optical * 0.02, -gradPhi.y * optical * 0.02, 1.0));
  let lightDir = normalize(vec3<f32>(-0.4, -0.5, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfVec = normalize(lightDir + viewDir);
  let specular = pow(max(dot(normal3, halfVec), 0.0), mix(32.0, 110.0, gamma / 1.2)) * (0.15 + 0.65 * interfaceDelta * texel.x * resolution.x);
  let contactLine = smoothstep(0.04, 0.30, interfaceDelta * texel.x * resolution.x) * (0.12 + 0.28 * treble);
  let capillaryTint = vec3<f32>(0.05, 0.18, 0.24) * (0.5 + 0.5 * marangoni) + vec3<f32>(0.0, 0.08, 0.12) * abs(curvature) * 0.02;
  let finalColor = clamp(baseColor * (0.88 + 0.12 * phi + 0.05 * mids) + capillaryTint * contactLine + vec3<f32>(1.0, 0.96, 0.88) * specular, vec3<f32>(0.0), vec3<f32>(1.0));
  let alpha = clamp(0.84 + 0.12 * contactLine + 0.04 * specular, 0.0, 1.0);
  let depthProxy = clamp(depthSample * 0.55 + 0.20 + phi * 0.20 + abs(curvature) * 0.003 + contactLine * 0.15, 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(phi, velocity, temperature, mergeSignal));
  textureStore(dataTextureB, global_id.xy, vec4<f32>(clamp(curvature * 0.01 + 0.5, 0.0, 1.0), clamp(interfaceDelta * texel.x * resolution.x * 0.1, 0.0, 1.0), clamp(capillaryOmega * 0.05, 0.0, 1.0), specular));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthProxy, 0.0, 0.0, 1.0));
}
