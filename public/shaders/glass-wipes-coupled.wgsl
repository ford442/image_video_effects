// Glass Wipes Coupled — rain on glass with Navier-Stokes viscous fluid coupling and wiper mechanics.
// A/C stores raw fluid state [vel.xy, vorticity, density]; ACES is presentation-only on writeTexture; depth passes through source depth.

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

fn rawStateAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
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
  let px = vec2<f32>(1.0) / resolution;

  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  // Parameters
  let rainIntensity = (0.006 + u.zoom_params.x * 0.05) * (1.0 + bass * 0.4);
  let viscosity = mix(0.91, 0.985, u.zoom_params.y);
  let wiperSize = 0.05 + u.zoom_params.z * 0.28;
  let vortexStrength = (0.3 + u.zoom_params.w * 2.2) * (1.0 + mids * 0.3);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mousePos = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Read previous fluid state [vel.xy, vorticity, density]
  let prevRaw = rawStateAt(uv, resolution);
  let prevVel = prevRaw.xy;

  // Semi-Lagrangian advection: trace back along velocity vector
  let backUV = uv - prevVel * px * 2.5;
  let advectedRaw = rawStateAt(backUV, resolution);
  var vel = advectedRaw.xy * viscosity;
  var dens = advectedRaw.w * viscosity;

  // Downward gravity pull for rain streams on glass
  vel.y += 0.0015 * (1.0 + dens * 0.5);

  // Mouse wiper interaction
  if (hasMouse) {
    let toMouse = (uv - mousePos) * aspectVec;
    let dist = length(toMouse);
    let influence = smoothstep(wiperSize, 0.0, dist);

    // Wiper velocity and vortex force
    let wiperPush = normalize(toMouse + vec2<f32>(0.0001)) * influence * 0.35;
    let vortexDir = vec2<f32>(-toMouse.y, toMouse.x) / max(dist, 0.001);
    vel += wiperPush + vortexDir * influence * vortexStrength * select(0.3, 0.7, held);

    // Wiper sweeps fluid clear in central path
    let wipeFactor = smoothstep(wiperSize * 0.8, 0.0, dist);
    dens *= (1.0 - wipeFactor * select(0.65, 0.95, held));
  }

  // Click ripple interactions = fluid impact shockwaves
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let elapsed = time - ripple.z;
    if (elapsed >= 0.0 && elapsed < 2.5) {
      let rToCoord = (uv - ripple.xy) * aspectVec;
      let rDist = length(rToCoord);
      let rWave = sin((rDist - elapsed * 0.35) * 50.0) * exp(-abs(rDist - elapsed * 0.35) * 25.0) * exp(-elapsed * 1.2);
      let outward = rToCoord / max(rDist, 0.0001);
      vel += outward * rWave * 0.035;
      dens += max(0.0, rWave) * 0.45;
    }
  }

  // Procedural rain drops adding to fluid density
  let dropHash = hash12(uv * 80.0 + fract(time * 0.8) * 100.0);
  if (dropHash > (1.0 - rainIntensity)) {
    dens = min(3.0, dens + 0.45 + bass * 0.2);
  }

  // Evaporation
  dens = max(0.0, dens - 0.0012);

  // Border damping to prevent edge reflections
  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.02, 0.08, edgeDist);
  vel *= edgeDamp;
  vel = clamp(vel, vec2<f32>(-0.6), vec2<f32>(0.6));
  dens = clamp(dens, 0.0, 3.0);

  // Compute vorticity (curl of velocity)
  let rightVel = rawStateAt(uv + vec2<f32>(px.x, 0.0), resolution).xy;
  let upVel = rawStateAt(uv + vec2<f32>(0.0, px.y), resolution).xy;
  let vorticity = (rightVel.y - prevVel.y) - (upVel.x - prevVel.x);

  // Store raw fluid state to dataTextureA
  let state = vec4<f32>(vel, vorticity, dens);
  textureStore(dataTextureA, coord, state);

  // ═══ VISUAL COMPOSITING & REFRACTION ═══
  let distortionScale = 0.045;
  let distortion = vel * dens * distortionScale;
  let distortedUV = clamp(uv + distortion, vec2<f32>(0.0), vec2<f32>(1.0));
  let src = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

  // Refractive glass & water surface optical properties
  let normal = normalize(vec3<f32>(distortion * 120.0, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let cosTheta = max(dot(viewDir, normal), 0.0);
  let fresnel = 0.02 + 0.98 * pow(1.0 - cosTheta, 5.0);

  let waterTint = vec3<f32>(0.86, 0.94, 1.0);
  let waterTransmittance = exp(-(vec3<f32>(1.0) - waterTint) * dens * 0.1);
  var outRGB = mix(src.rgb, src.rgb * waterTransmittance, clamp(dens * 0.4, 0.0, 0.85));

  // Specular gleam from light and treble sparkles
  let lightDir = normalize(vec3<f32>(mousePos - uv, 0.6));
  let halfVec = normalize(lightDir + viewDir);
  let spec = pow(max(dot(normal, halfVec), 0.0), 32.0) * clamp(dens * 0.8, 0.0, 1.5);
  let sparkle = pow(hash12(uv * 250.0 + time * 1.5), 18.0) * (treble * 0.8) * dens;
  outRGB += vec3<f32>(spec * 0.85 + sparkle) + vec3<f32>(fresnel * 0.15);

  let alpha = clamp(src.a * 0.75 + dens * 0.35 + fresnel * 0.1, 0.0, 1.0);
  let result = vec4<f32>(aces(max(outRGB, vec3<f32>(0.0))), alpha);

  textureStore(writeTexture, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
