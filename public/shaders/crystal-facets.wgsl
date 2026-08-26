// ═══════════════════════════════════════════════════════════════════
//  Crystal Facets — Prismatic Facet Refraction & Birefringence
//  Category: distortion
//  Features: mouse-driven, refraction, fresnel, dispersion, internal-reflection,
//            audio-caustics, depth-prisms, volumetric-gems, semantic-alpha, ACES
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
  zoom_params: vec4<f32>,  // x=FacetCount, y=RefractiveIndex, z=FractureDensity, w=CrystalThickness
  ripples: array<vec4<f32>, 50>,
};

const IOR_GLASS: f32 = 1.50;
const IOR_DIAMOND: f32 = 2.42;

fn hash11(p: f32) -> f32 {
  var p2 = fract(p * 0.1031);
  p2 *= p2 + 33.33;
  p2 *= p2 + p2;
  return fract(p2);
}

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Exact parameter contracts
  let facetCount = floor(mix(3.0, 16.0, u.zoom_params.x));
  let iorMix = u.zoom_params.y;
  let fractureDensity = u.zoom_params.z;
  let crystalThickness = mix(0.1, 2.0, u.zoom_params.w);

  let ior = mix(IOR_GLASS, IOR_DIAMOND, iorMix);
  let refraction = mix(0.02, 0.15, iorMix);
  let rotation = time * 0.1;

  // Critically damped spring cursor in extraBuffer[133..138]
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let isWriter = (gid.x == 0u && gid.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 45.0;
    let damping = 13.416; // 2 * sqrt(45)
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  var center = mouse;
  var dir = (uv - center) * vec2<f32>(aspect, 1.0);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleDisp = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let d = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((d - age * 0.6) * 30.0) * exp(-d * 4.0) * exp(-age * 1.5);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleDisp += rDir * wave * 0.035;
    }
  }
  dir += rippleDisp;

  let dist = length(dir);
  var angle = atan2(dir.y, dir.x) + rotation;

  let rawSector = angle / (6.2831853 / facetCount);
  let sector = floor(rawSector);
  let sectorAngle = sector * (6.2831853 / facetCount);

  let facetID = sector;
  let randomTilt = (hash11(facetID) - 0.5) * 2.0;
  let facetFracture = hash11(facetID + 100.0);

  let offsetDir = vec2<f32>(cos(sectorAngle), sin(sectorAngle));
  let rOffset = offsetDir * refraction * (1.0 + randomTilt * 0.5);
  let gOffset = offsetDir * refraction * 0.5;
  let bOffset = offsetDir * refraction * (0.0 - randomTilt * 0.5);

  let baseUV = center + vec2<f32>(cos(angle - rotation) / aspect, sin(angle - rotation)) * dist;

  let r_val = textureSampleLevel(readTexture, u_sampler, clamp(baseUV - rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g_val = textureSampleLevel(readTexture, u_sampler, clamp(baseUV - gOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b_val = textureSampleLevel(readTexture, u_sampler, clamp(baseUV - bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r_val, g_val, b_val);

  // Exact dataTextureC persistence
  let prev_c = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prev_c, 0.06);

  let angleToNormal = abs(fract(rawSector) - 0.5) * 2.0;
  let cosTheta = cos(angleToNormal * 1.570796);
  let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
  let fresnel = fresnelSchlick(cosTheta, F0);
  let pathLength = crystalThickness / max(abs(cosTheta), 0.01);
  let purity = 1.0 - (fractureDensity * facetFracture);
  let absorptionCoeff = mix(0.5, 5.0, fractureDensity);
  let absorption = exp(-absorptionCoeff * pathLength / max(purity, 0.1));

  let angleLocal = fract(rawSector);
  let edgeDist = min(angleLocal, 1.0 - angleLocal);
  let edgeFactor = smoothstep(0.04, 0.0, edgeDist);

  let transmission = absorption * (1.0 - fresnel) * purity;
  let specular = edgeFactor * fresnel * 0.85;
  color += vec3<f32>(specular);

  let internalScatter = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.95, 1.0), fractureDensity);
  color = color * internalScatter;

  let causticPulse = 1.0 + bass * 0.6 + sin(time * 6.0 + facetID) * treble * 0.4;
  let internalTint = vec3<f32>(1.0 + mids * 0.15, 1.0 - mids * 0.08, 1.0 - mids * 0.12);
  let sparkle = pow(hash11(facetID + time * 12.0), 8.0) * treble * 1.5;

  color = color * internalTint * causticPulse + vec3<f32>(0.85, 0.92, 1.0) * sparkle * edgeFactor;

  // Semantic alpha
  let opticalDepth = pathLength * crystalThickness;
  let abs_coeff = vec3<f32>(0.18, 0.12, 0.25) * (1.0 + fractureDensity * 3.0);
  let abs_val = exp(-abs_coeff * opticalDepth);
  let density = edgeFactor * (1.0 + iorMix) * (1.0 + fractureDensity);
  let volumetricAlpha = 1.0 - exp(-density * opticalDepth * 1.5);
  let transmittanceAlpha = transmission * dot(abs_val, vec3<f32>(0.3333)) * purity;
  let fresnelBoost = fresnel * edgeFactor * 0.4;

  let alpha = clamp(mix(transmittanceAlpha, volumetricAlpha, 0.45) + fresnelBoost + held * 0.1, 0.1, 1.0);

  let finalRGB = aces(color);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
