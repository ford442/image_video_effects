// ═══════════════════════════════════════════════════════════════════
//  Liquid Touch
//  Category: interactive-mouse
//  Features: upgraded-rgba, depth-aware, audio-reactive, exact-state-loads,
//            biharmonic-dispersion, mean-curvature-pressure, crest-microfoam
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

fn sampleState(coord: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dimsI = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(dimsI);
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

  // One exact 13-point stencil drives gradient, curvature and the biharmonic
  // capillary term without sampling rgba32float state through a sampler.
  let center = sampleState(coord, dimsI);
  let left = sampleState(coord + vec2<i32>(-1,  0), dimsI);
  let right = sampleState(coord + vec2<i32>( 1,  0), dimsI);
  let up = sampleState(coord + vec2<i32>( 0, -1), dimsI);
  let down = sampleState(coord + vec2<i32>( 0,  1), dimsI);
  let nw = sampleState(coord + vec2<i32>(-1, -1), dimsI);
  let ne = sampleState(coord + vec2<i32>( 1, -1), dimsI);
  let sw = sampleState(coord + vec2<i32>(-1,  1), dimsI);
  let se = sampleState(coord + vec2<i32>( 1,  1), dimsI);
  let left2 = sampleState(coord + vec2<i32>(-2,  0), dimsI);
  let right2 = sampleState(coord + vec2<i32>( 2,  0), dimsI);
  let up2 = sampleState(coord + vec2<i32>( 0, -2), dimsI);
  let down2 = sampleState(coord + vec2<i32>( 0,  2), dimsI);

  var phi = center.r;
  var velocity = center.g;
  var temperature = center.b * 0.985;

  let gradPhi = vec2<f32>(right.r - left.r, down.r - up.r) * 0.5;
  let interfaceDelta = length(gradPhi);
  let hxx = left.r + right.r - 2.0 * center.r;
  let hyy = up.r + down.r - 2.0 * center.r;
  let hxy = (se.r - ne.r - sw.r + nw.r) * 0.25;
  let slope2 = dot(gradPhi, gradPhi);
  let curvature = ((1.0 + gradPhi.y * gradPhi.y) * hxx
                  - 2.0 * gradPhi.x * gradPhi.y * hxy
                  + (1.0 + gradPhi.x * gradPhi.x) * hyy)
                  / max(pow(1.0 + slope2, 1.5), 1e-6);
  let laplacian = hxx + hyy;
  let biharmonic = 20.0 * center.r
                 - 8.0 * (left.r + right.r + up.r + down.r)
                 + 2.0 * (nw.r + ne.r + sw.r + se.r)
                 + left2.r + right2.r + up2.r + down2.r;

  let normalCenter = safeNormalize(gradPhi);
  let gradTemperature = vec2<f32>(right.b - left.b, down.b - up.b) * 0.5;
  let surfaceTensionForce = gamma * curvature * interfaceDelta;
  let marangoniForce = -dot(gradTemperature, normalCenter) * (0.01 + 0.05 * marangoni);

  let localK = clamp(interfaceDelta * 4.0 + abs(curvature) * 2.0, 0.001, 18.0);
  let capillaryOmega = sqrt(max((gamma / rho) * localK * localK * localK, 0.0001));
  let capillaryWave = sin(capillaryOmega * time * 1.5 + curvature * 0.15) * (0.004 + 0.012 * treble) * smoothstep(0.04, 0.4, interfaceDelta);
  // Discrete gravity-capillary dispersion: Δh supplies the long gravity wave;
  // Δ²h supplies the wavelength-dependent surface-tension correction.
  let gravityWave = laplacian * (0.09 + bass * 0.05)
                   - biharmonic * (0.006 + gamma * 0.032)
                   + bass * sin(time * 1.8 + dot(uv, vec2<f32>(7.0, 4.0))) * 0.006;

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
  let baseSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let baseColor = baseSample.rgb;
  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;

  let normal3 = normalize(vec3<f32>(-gradPhi.x * optical * 0.02, -gradPhi.y * optical * 0.02, 1.0));
  let lightDir = normalize(vec3<f32>(-0.4, -0.5, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfVec = normalize(lightDir + viewDir);
  let specular = pow(max(dot(normal3, halfVec), 0.0), mix(32.0, 110.0, gamma / 1.2)) * (0.15 + 0.65 * interfaceDelta * texel.x * resolution.x);
  let contactLine = smoothstep(0.025, 0.22, interfaceDelta) * (0.12 + 0.28 * treble);
  let crestCompression = max(-biharmonic, 0.0) + max(curvature, 0.0) * 0.8;
  let microfoam = smoothstep(0.08, 0.65, crestCompression + abs(velocity) * 0.6)
                  * (0.18 + 0.55 * treble + 0.25 * mergeSignal);
  let capillaryTint = vec3<f32>(0.05, 0.18, 0.24) * (0.5 + 0.5 * marangoni) + vec3<f32>(0.0, 0.08, 0.12) * abs(curvature) * 0.02;
  let finalColor = acesFilm(baseColor * (0.88 + 0.12 * phi + 0.05 * mids)
                         + capillaryTint * contactLine
                         + vec3<f32>(1.0, 0.96, 0.88) * (specular + microfoam * 0.24));
  let alpha = clamp(mix(baseSample.a * 0.72 + 0.12, 1.0,
                        clamp(contactLine * 0.5 + microfoam * 0.35 + abs(phi) * 0.18, 0.0, 1.0)), 0.0, 1.0);
  let depthProxy = clamp(depthSample * 0.55 + 0.20 + phi * 0.20 + abs(curvature) * 0.003 + contactLine * 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(phi, velocity, temperature, max(mergeSignal, microfoam)));
  textureStore(dataTextureB, coord, vec4<f32>(clamp(curvature * 2.0 + 0.5, 0.0, 1.0), clamp(interfaceDelta * 2.5, 0.0, 1.0), clamp(abs(biharmonic) * 2.0, 0.0, 1.0), microfoam));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthProxy, 0.0, 0.0, 1.0));
}
