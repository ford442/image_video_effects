// ═══════════════════════════════════════════════════════════════════
//  Ferrofluid EM — multipole field lines through conductive liquid
//  A owns HDR display history; C is exact previous display state.
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

const TAU: f32 = 6.28318530718;

fn chargeField(p: vec2<f32>, center: vec2<f32>, charge: f32) -> vec3<f32> {
  let delta = p - center;
  let r2 = dot(delta, delta) + 0.006;
  let invR = inverseSqrt(r2);
  let strength = charge * invR * invR;
  return vec3<f32>(delta * invR * strength, charge * invR);
}

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.46, 0.48, 0.52)
    + vec3<f32>(0.46, 0.42, 0.38) * cos(TAU * (vec3<f32>(1.0, 0.88, 0.74) * t + vec3<f32>(0.03, 0.24, 0.51)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn clampPixel(pixel: vec2<i32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let p = (uv - 0.5) * aspectVec;
  let rawMouse = u.zoom_config.yz;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Four legacy generic params now cover spike frequency, field gain,
  // conductivity/persistence, and spectral phase without changing presets.
  let spikeFrequency = mix(8.0, 34.0, u.zoom_params.x);
  let fieldGain = mix(0.35, 1.65, u.zoom_params.y) * (1.0 + bass * 0.35);
  let conductivity = u.zoom_params.z;
  let colorPhase = u.zoom_params.w;

  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var sprungMouse = rawMouse; var chargeVelocity = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) {
    sprungMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]); chargeVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  }
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    var pos = sprungMouse; var vel = chargeVelocity; let seeded = extraBuffer[138] > 0.5;
    if (!seeded) { pos = rawMouse; vel = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
    vel += ((rawMouse - pos) * 190.0 - vel * mix(20.0, 32.0, conductivity)) * dt; pos += vel * dt;
    extraBuffer[133] = pos.x; extraBuffer[134] = pos.y; extraBuffer[135] = vel.x; extraBuffer[136] = vel.y; extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }
  let mouse = (sprungMouse - 0.5) * aspectVec;

  let orbit = 0.29 + sin(time * 0.17) * 0.035;
  let c0 = vec2<f32>(cos(time * 0.31), sin(time * 0.31)) * orbit;
  let c1 = vec2<f32>(cos(time * 0.23 + 2.15), sin(time * 0.23 + 2.15)) * orbit;
  let c2 = vec2<f32>(cos(-time * 0.27 + 4.25), sin(-time * 0.27 + 4.25)) * orbit;
  var em = chargeField(p, c0, 1.0) + chargeField(p, c1, -0.82) + chargeField(p, c2, 0.67);
  let mouseCharge = select(-0.55, 1.35, u.zoom_config.w > 0.5) * fieldGain;
  em += chargeField(p, mouse, mouseCharge);
  em = vec3<f32>(em.xy + chargeVelocity / aspectVec * 0.08 * fieldGain, em.z);

  var clickEnergy = 0.0;
  var clickField = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri += 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.2) {
      let center = (ripple.xy - 0.5) * aspectVec;
      let polarity = select(-1.0, 1.0, (ri % 2u) == 0u);
      let pulse = exp(-age * 1.35) * sin(age * 8.0) * polarity;
      let cf = chargeField(p, center, pulse * 0.7);
      clickField += cf.xy;
      clickEnergy += abs(cf.z) * exp(-age);
    }
  }
  em = vec3<f32>(em.xy + clickField, em.z);

  let magnitude = length(em.xy) * fieldGain;
  let direction = em.xy / max(length(em.xy), 0.001);
  let tangent = vec2<f32>(-direction.y, direction.x);
  let angle = atan2(direction.y, direction.x);
  let potential = em.z;

  // Interference of equipotential and directional families creates magnetic ridges.
  let equipotential = pow(abs(sin(potential * (2.8 + spikeFrequency * 0.16) - time * (0.8 + mids))), 10.0);
  let directional = pow(abs(cos(angle * (4.0 + u.zoom_params.x * 8.0)
    + length(p) * spikeFrequency - time * 2.4)), 14.0);
  let poynting = pow(max(0.0, sin(dot(p, tangent) * spikeFrequency * 1.6
    - time * (4.0 + treble * 3.0) + potential * 2.0)), 18.0);
  let ridge = clamp((equipotential * 0.58 + directional * 0.48 + poynting * 0.35)
    * smoothstep(0.05, 1.5, magnitude) + clickEnergy * 0.08, 0.0, 2.0);
  let height = (1.0 - exp(-magnitude * 0.42)) * (0.22 + ridge * 0.78);

  // Field-aligned distortion with Hall-like transverse drift.
  let hall = mix(0.08, 0.55, conductivity);
  let displacementAspect = (direction * height * 0.045 + tangent * height * hall * 0.035
    + clickField * 0.006) * (0.7 + fieldGain * 0.3);
  let displacedUV = clamp(uv - displacementAspect / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let chroma = tangent * (0.001 + conductivity * 0.008 + treble * 0.003) / aspectVec;
  let srcR = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let srcG = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
  let srcB = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  let srcA = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).a;
  let source = vec3<f32>(srcR, srcG, srcB);

  let normal = normalize(vec3<f32>(-direction * height * (2.0 + ridge * 2.5), 0.45));
  let viewDir = normalize(vec3<f32>(p * 0.35, 1.0));
  let key = normalize(vec3<f32>(-0.4, 0.55, 0.8));
  let halfVector = normalize(viewDir + key);
  let specular = pow(max(dot(normal, halfVector), 0.0), mix(34.0, 150.0, conductivity));
  let fresnel = pow(1.0 - max(dot(normal, viewDir), 0.0), 4.0);
  let fieldColor = max(palette(angle / TAU + potential * 0.08 + colorPhase), vec3<f32>(0.0));
  let darkMetal = source * vec3<f32>(0.08, 0.09, 0.115) + vec3<f32>(0.004, 0.006, 0.01);
  let emGlow = fieldColor * (ridge * (0.2 + mids * 0.3) + poynting * (0.45 + treble * 0.8));
  let fluid = darkMetal + vec3<f32>(0.95, 1.0, 1.08) * specular * 2.1
    + fieldColor * fresnel * 0.55 + emGlow + vec3<f32>(1.0, 0.45, 0.12) * clickEnergy * 0.018;
  let effectMask = clamp(smoothstep(0.03, 0.9, magnitude) * 0.72 + ridge * 0.28, 0.0, 1.0);
  var live = mix(source, fluid, effectMask);

  let drift = vec2<i32>(round((direction * 1.5 + tangent * conductivity * 2.4 + clickField * 0.15)
    * clamp(magnitude, 0.0, 2.5)));
  let prev = textureLoad(dataTextureC, clampPixel(pixel - drift, dims), 0);
  let persistence = mix(0.18, 0.72, conductivity) * effectMask;
  live = mix(live, prev.rgb * 0.968, persistence);
  live = max(live, fluid * 0.62);

  let alphaLive = mix(srcA, clamp(0.35 + height * 0.55 + ridge * 0.12, 0.0, 1.0), effectMask);
  let alpha = mix(alphaLive, prev.a * 0.96, persistence * 0.5);
  textureStore(dataTextureA, pixel, vec4<f32>(min(live, vec3<f32>(8.0)), alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(live), alpha));

  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let generatedDepth = clamp(height * 0.54 + ridge * 0.08, 0.0, 0.92);
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.84, generatedDepth), 0.0, 0.0, 0.0));
}
