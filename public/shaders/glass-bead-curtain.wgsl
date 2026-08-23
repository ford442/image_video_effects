// ═══════════════════════════════════════════════════════════════════
//  Glass Bead Curtain v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
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
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453);
}

fn acesTonemap(color: vec3<f32>) -> vec3<f32> {
  let m1 = mat3x3<f32>(
    0.59719, 0.07600, 0.02840,
    0.35458, 0.90834, 0.13383,
    0.04823, 0.01566, 0.83777
  );
  let m2 = mat3x3<f32>(
    1.60475, -0.10208, -0.00327,
    -0.53108, 1.10813, -0.07276,
    -0.07367, -0.00605, 1.07602
  );
  let v = m1 * color;
  let a = v * (v + 0.0245786) - 0.000090537;
  let b = v * (0.983729 * v + 0.4329510) + 0.238081;
  return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn fresnelSchlick(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(1.0 - abs(cosTheta), 5.0);
}

fn sphereRefract(incident: vec2<f32>, n: vec2<f32>, eta: f32) -> vec2<f32> {
  let cosI = clamp(-dot(incident, n), -1.0, 1.0);
  let sinT2 = eta * eta * (1.0 - cosI * cosI);
  let cosT = sqrt(max(0.0, 1.0 - sinT2));
  return incident * eta + n * (eta * cosI - cosT);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  // Persistent state logic for bounded spring (held-pointer response)
  if (gid.x == 0u && gid.y == 0u) {
    let target = select(0.0, 1.0, u.config.y > 0.0);
    var pos = extraBuffer[133];
    var vel = extraBuffer[134];
    let dt = 0.016;
    let force = (target - pos) * 100.0 - vel * 12.0;
    vel += force * dt;
    pos += vel * dt;
    extraBuffer[133] = clamp(pos, -0.5, 1.5);
    extraBuffer[134] = clamp(vel, -20.0, 20.0);
  }

  let springState = clamp(extraBuffer[133], 0.0, 1.0);

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  
  // Truthful three-band audio
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let beadCount = mix(6.0, 32.0, 1.0 - u.zoom_params.x) * (0.5 + depth * 0.5);
  let refraction = u.zoom_params.y * 0.10;
  let interactTension = mix(0.05, 0.45, u.zoom_params.z);
  let density = mix(0.25, 1.0, u.zoom_params.w);

  // Exact textureLoad from dataTextureC
  let prevC = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
  
  var rippleEffect = 0.0;
  var rippleNormal = vec2<f32>(0.0);
  for (var i = 0u; i < 50u; i++) {
    let r = u.ripples[i];
    if (r.w > 0.0) {
      let delta = uv - r.xy;
      let d = length(delta * vec2<f32>(aspect, 1.0));
      let timeSince = time - r.z;
      let radius = timeSince * 1.5;
      let distFromFront = abs(d - radius);
      let intensity = smoothstep(0.15, 0.0, distFromFront) * smoothstep(2.0, 0.0, radius);
      rippleEffect += intensity;
      if (d > 0.0) {
        rippleNormal += (delta / d) * intensity * smoothstep(2.0, 0.0, radius);
      }
    }
  }
  
  let curtainUV = vec2<f32>(uv.x * beadCount * aspect, uv.y * beadCount);
  let beadId = floor(curtainUV);
  let beadCenter = beadId + 0.5;
  let beadPhase = hash12(beadId) * 6.28318;

  let windSway = sin(time * (1.2 + bass * 2.5) + beadId.y * 0.35 + beadPhase) * (0.10 + bass * 0.12);
  let neighborLeft = hash22(beadId + vec2<f32>(-1.0, 0.0)).x * 0.06;
  let neighborRight = hash22(beadId + vec2<f32>(1.0, 0.0)).x * 0.06;
  
  // Continuous geometry response from mouse
  let mouseDelta = (beadCenter / beadCount) - mouse;
  let mouseDist = length(mouseDelta * vec2<f32>(aspect, 1.0));
  let collisionPush = (neighborLeft - neighborRight) * (1.0 - smoothstep(0.0, 0.5, mouseDist));
  let verticalCoupling = sin(time * 0.8 + beadId.y * 0.6 + beadId.x * 0.3) * 0.04 * bass;
  
  // Held-pointer interactive pull
  let mousePull = mouseDelta * springState * smoothstep(0.5, 0.0, mouseDist) * 0.2;
  
  let beadLocal = curtainUV - beadCenter + vec2<f32>(windSway + collisionPush, verticalCoupling) + mousePull * beadCount;
  let beadDist = length(beadLocal);
  let beadMask = 1.0 - smoothstep(0.30, 0.50, beadDist);
  let sphereHeight = sqrt(max(0.0, 1.0 - beadDist * beadDist * 4.0));

  let beadCenterUV = vec2<f32>((beadCenter.x - windSway) / (beadCount * aspect), beadCenter.y / beadCount);
  let pullDelta = (beadCenterUV - mouse) * vec2<f32>(aspect, 1.0);
  let pullDist = length(pullDelta);
  let pull = (1.0 - smoothstep(0.0, 0.40, pullDist)) * interactTension;

  let normal = normalize(beadLocal + normalize(pullDelta + vec2<f32>(0.001, 0.0)) * pull + rippleNormal * 1.5 * beadCount);
  let viewDir = vec2<f32>(0.0, 1.0);
  let cosTheta = max(0.0, dot(normal, viewDir));
  let f0 = 0.04;
  let fresnel = fresnelSchlick(cosTheta, f0);

  let etaGlass = 1.5;
  let etaAir = 1.0;
  let etaRatio = etaAir / etaGlass;
  let refractDir = sphereRefract(viewDir, normal, etaRatio);

  // Optical/Prismatic feel
  let chromatic = vec3<f32>(1.00, 0.97, 0.94) + vec3<f32>(0.0, 0.02, 0.05) * rippleEffect;
  let rOff = refractDir * refraction * chromatic.r * beadMask * (1.0 + treble * 0.9);
  let gOff = refractDir * refraction * chromatic.g * beadMask * (1.0 + treble * 0.6);
  let bOff = refractDir * refraction * chromatic.b * beadMask * (1.0 + treble * 0.3);
  let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(uv + rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let sampleG = textureSampleLevel(readTexture, u_sampler, clamp(uv + gOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(uv + bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var refracted = vec3<f32>(sampleR, sampleG, sampleB);

  // Blend in prevC
  refracted += prevC.rgb * 0.02;

  let causticFocus = pow(max(0.0, 1.0 - beadDist * 2.2), 4.0);
  let causticPattern = pow(sin(beadLocal.x * 18.0 + beadLocal.y * 14.0 + time * 2.5 + beadPhase) * 0.5 + 0.5, 5.0);
  let causticRing = pow(sin(beadDist * 12.0 - time * 1.5) * 0.5 + 0.5, 3.0);
  let causticIntensity = causticFocus * (causticPattern * 0.6 + causticRing * 0.4) * (0.35 + mids * 0.65) * beadMask;

  let sssColor = mix(vec3<f32>(0.95, 0.35, 0.15), vec3<f32>(0.12, 0.60, 0.95), hash12(beadId));
  let sss = sssColor * causticIntensity * density * 0.55;

  let specAngle = max(0.0, dot(normal, vec2<f32>(0.25, 0.75)));
  let specularSharp = pow(specAngle, 64.0) * (0.25 + treble * 0.45) * beadMask * fresnel;
  let specularBroad = pow(specAngle, 8.0) * 0.15 * beadMask * (1.0 - fresnel);
  let specular = specularSharp + specularBroad;

  let envReflect = pow(max(0.0, normal.y), 2.0) * 0.15 * fresnel * beadMask;

  var finalColor = refracted * (1.0 - fresnel * beadMask * density * 0.8) + sss;
  finalColor = finalColor + vec3<f32>(1.0, 0.95, 0.85) * specular;
  finalColor = finalColor + vec3<f32>(0.7, 0.8, 0.9) * envReflect;
  finalColor = finalColor + vec3<f32>(0.25, 0.55, 0.9) * causticIntensity * 0.35 * density;

  let sparkle = pow(max(0.0, 1.0 - beadDist * 1.7), 6.0) * (0.15 + treble * 0.4);
  finalColor = finalColor + vec3<f32>(0.85, 0.92, 1.0) * sparkle;

  // Add prismatic high-end touch from ripples
  finalColor += vec3<f32>(0.2, 0.5, 1.0) * rippleEffect * beadMask * 0.5;

  finalColor = acesTonemap(finalColor * 1.15);

  let causticAlpha = causticIntensity * 0.75 + sparkle * 0.25 + beadMask * 0.15;
  
  // Semantic alpha: represents surface occlusion + glass density + emissive features
  let baseAlpha = clamp(beadMask * density + causticAlpha * 0.5, 0.0, 1.0);
  let semanticAlpha = clamp(baseAlpha * (0.5 + depth * 0.5) + rippleEffect * 0.3, 0.05, 0.98);

  let finalRGBA = vec4<f32>(finalColor, semanticAlpha);

  let depthOut = clamp(mix(depth, depth * 0.25 + beadMask * sphereHeight * 0.75, 0.42), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), finalRGBA);
  textureStore(dataTextureA, vec2<i32>(gid.xy), finalRGBA);
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
