// ═══════════════════════════════════════════════════════════════════
//  Crystal Facets — Prismatic Facet Refraction & Total Internal Reflection
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, refraction, fresnel,
//            dispersion, total-internal-reflection, beer-lambert, semantic-alpha, ACES
//  Ideas:    1. TIR flash — facets tilted past asin(1/n) mirror the far side of the gem
//            2. Beer-Lambert body colour — Crystal Thickness tints the light path
//            3. crown/pavilion rings — radial tiers with half-offset sectors (kite cut)
//            4. scintillation sweep — TIR facets mirror a fixed lamp as the gem turns: bright flash <-> dark extinction
//            5. cloudy inclusion facets — Fracture Density picks which facets are milky; a cloudy facet loses its brilliance
//  Complexity: High
//  Upgraded: 2026-11-09
//  Rescued: facet hash seam through the atan2 branch cut (sector index now wrapped mod facetCount before hashing); refraction direction now follows the facet's true screen azimuth (HEAD leaked `rotation` into it and used the facet's lower edge, so it drifted a full turn after ~63 s)
//  A packing: ACES display RGBA (unchanged); C is the 6 % display ghost
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=FacetCount, y=RefractiveIndex, z=FractureDensity, w=CrystalThickness

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

  // Raw pointer: the old extraBuffer[133..138] spring raced (pixel (0,0) wrote
  // while every other pixel read) and the buffer is re-uploaded each frame.
  let mouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

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
      let rDir = normalize((uv - r.xy) * vec2<f32>(aspect, 1.0) + vec2<f32>(0.0001));
      rippleDisp += rDir * wave * 0.035;
    }
  }
  dir += rippleDisp;

  let dist = length(dir);
  var angle = atan2(dir.y, dir.x) + rotation;

  // Idea 3: crown/pavilion rings — table, crown and pavilion tiers. Each tier
  // shifts its sectors by half a facet, so the cut reads as kites, not pie slices.
  let ringPos = dist / mix(0.10, 0.16, iorMix);
  let ring = min(floor(ringPos), 2.0);
  let ringLocal = select(fract(ringPos), ringPos - 2.0, ring >= 2.0);
  let sectorWidth = 6.2831853 / facetCount;
  let rawSector = angle / sectorWidth + ring * 0.5;
  let sector = floor(rawSector);
  // Rescue R1: atan2's branch cut jumps `sector` by exactly facetCount, which split one facet into two
  // different hashes (a seam on the left of the gem). Hash the index modulo facetCount instead.
  let sectorWrap = sector - facetCount * floor(sector / facetCount + 0.5);
  // Rescue R2: the facet's true screen azimuth (centre of its sector, rotation removed). HEAD used the
  // facet's lower edge in rotated angle space, so the fringe direction drifted away from its facet.
  let facetAz = (sector + 0.5 - ring * 0.5) * sectorWidth - rotation;

  let facetID = sectorWrap + ring * 37.0;
  let randomTilt = (hash11(facetID) - 0.5) * 2.0;
  let facetFracture = hash11(facetID + 100.0);

  let offsetDir = vec2<f32>(cos(facetAz), sin(facetAz));
  let rOffset = offsetDir * refraction * (1.0 + randomTilt * 0.5);
  let gOffset = offsetDir * refraction * 0.5;
  let bOffset = offsetDir * refraction * (0.0 - randomTilt * 0.5);

  let baseUV = center + dir / vec2<f32>(aspect, 1.0);

  let r_val = textureSampleLevel(readTexture, u_sampler, clamp(baseUV - rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g_val = textureSampleLevel(readTexture, u_sampler, clamp(baseUV - gOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b_val = textureSampleLevel(readTexture, u_sampler, clamp(baseUV - bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r_val, g_val, b_val);

  // Idea 5: cloudy inclusion facets. Fracture Density now also picks WHICH facets carry inclusions
  // (the per-facet hash `facetFracture` that HEAD only used for purity): above a density-driven
  // threshold the facet is milky — the picture is seen through four wide scatter taps — and a cloudy
  // stone is dull, so it loses its flash and sparkle. 0 = none, default 0.2 = ~1 in 5, 1 = most.
  let cloudThresh = 1.0 - fractureDensity * 0.9;
  let cloud = smoothstep(cloudThresh, cloudThresh + 0.12, facetFracture);
  if (cloud > 0.01) {
    let hz = 0.016 * (1.0 + ring * 0.3);
    var milk = vec3<f32>(0.0);
    for (var k = 0; k < 4; k = k + 1) {
      let o = vec2<f32>(f32(k & 1) * 2.0 - 1.0, f32(k >> 1) * 2.0 - 1.0) * hz;
      milk += textureSampleLevel(readTexture, u_sampler, clamp(baseUV + o, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    milk = milk * 0.25 * vec3<f32>(0.96, 0.98, 1.0) + vec3<f32>(0.05);
    color = mix(color, milk, 0.85 * cloud);
  }

  let angleToNormal = abs(fract(rawSector) - 0.5) * 2.0;
  let cosTheta = cos(angleToNormal * 1.570796);
  let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
  let fresnel = fresnelSchlick(cosTheta, F0);

  // Idea 1: TIR flash. The facet's tilt grows outward (pavilion facets are the
  // steepest). Past the critical angle asin(1/n) the facet stops transmitting
  // and mirrors the opposite side of the stone, so diamond flashes more facets
  // than glass does.
  let sinI = clamp(0.16 + ring * 0.05 + randomTilt * randomTilt * 0.4 + bass * 0.05, 0.0, 0.99);
  let criticalSin = 1.0 / ior;
  let tir = smoothstep(criticalSin * 0.92, criticalSin, sinI) * (1.0 - 0.85 * cloud);
  let mirrorUV = clamp(center - dir / vec2<f32>(aspect, 1.0) * 0.7 + offsetDir * refraction,
                       vec2<f32>(0.0), vec2<f32>(1.0));
  let mirrored = textureSampleLevel(readTexture, u_sampler, mirrorUV, 0.0).rgb;
  // Idea 4: scintillation sweep. The stone turns (`rotation`) under a fixed lamp: a facet mirrors the lamp
  // when its azimuth lines up with it (cos^6 lobe, the pavilion sees the lamp from further round), so the
  // mirrored facets alternate bright flash <-> dark extinction as it passes. The mean mirror brightness
  // stays near HEAD's flat 1.25x (mean gain ~1.08); only the contrast between facets is new.
  let lampAz = -2.2 + ring * 1.1;
  let lobe = pow(0.5 + 0.5 * cos(facetAz - lampAz), 6.0);
  let mirrorGain = mix(0.7, 2.4, lobe);
  color = mix(color, mirrored * vec3<f32>(1.25, 1.28, 1.35) * mirrorGain + vec3<f32>(0.10, 0.12, 0.16) * (0.4 + 0.6 * lobe), tir * 0.85);

  // Idea 2: Beer-Lambert body colour. The path length through the facet follows
  // its tilt, and the stone absorbs blue a little more than red.
  let cosT = sqrt(max(1.0 - sinI * sinI, 0.0));
  let pathLength = crystalThickness / max(cosT, 0.3) * (1.0 - tir * 0.5);
  let purity = 1.0 - (fractureDensity * facetFracture);
  let absorptionCoeff = mix(0.5, 5.0, fractureDensity);
  let absorption = exp(-absorptionCoeff * pathLength * 0.1 / max(purity, 0.1));
  let bodyCoeff = vec3<f32>(0.05, 0.035, 0.08) * (1.0 + fractureDensity * 2.0);
  let bodyTint = exp(-bodyCoeff * pathLength);
  color = color * bodyTint;

  let angleLocal = fract(rawSector);
  let edgeDist = min(min(angleLocal, 1.0 - angleLocal),
                     select(select(min(ringLocal, 1.0 - ringLocal), 1.0 - ringLocal, ring < 0.5) * 0.5,
                            ringLocal * 0.5, ring >= 2.0));
  let edgeFactor = smoothstep(0.04, 0.0, edgeDist);

  let transmission = absorption * (1.0 - fresnel) * purity;
  let specular = edgeFactor * fresnel * 0.85;
  color += vec3<f32>(specular);
  // (Idea 4, transmitting facets) the same lamp lobe glints on the facets that are not total-reflecting.
  color += vec3<f32>(0.90, 0.95, 1.0) * lobe * (0.06 + 0.75 * fresnel) * (1.0 - tir) * (1.0 - 0.8 * cloud);

  let internalScatter = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.95, 1.0), fractureDensity);
  color = color * internalScatter;

  let causticPulse = 1.0 + bass * 0.6 + sin(time * 6.0 + facetID) * treble * 0.4;
  let internalTint = vec3<f32>(1.0 + mids * 0.15, 1.0 - mids * 0.08, 1.0 - mids * 0.12);
  let sparkle = pow(hash11(facetID + time * 12.0), 8.0) * treble * 1.5 * (1.0 - 0.8 * cloud);

  color = color * internalTint * causticPulse + vec3<f32>(0.85, 0.92, 1.0) * sparkle * (edgeFactor + tir * 0.5);

  // Semantic alpha
  let opticalDepth = pathLength * crystalThickness;
  let abs_coeff = vec3<f32>(0.18, 0.12, 0.25) * (1.0 + fractureDensity * 3.0);
  let abs_val = exp(-abs_coeff * opticalDepth);
  let density = edgeFactor * (1.0 + iorMix) * (1.0 + fractureDensity);
  let volumetricAlpha = 1.0 - exp(-density * opticalDepth * 1.5);
  let transmittanceAlpha = transmission * dot(abs_val, vec3<f32>(0.3333)) * purity;
  let fresnelBoost = fresnel * edgeFactor * 0.4;

  let alpha = clamp(mix(transmittanceAlpha, volumetricAlpha, 0.45) + fresnelBoost + tir * 0.12 + cloud * 0.15 + held * 0.1, 0.1, 1.0);

  // Exact dataTextureC persistence, blended in display space (C holds ACES output).
  let prev_c = clamp(textureLoad(dataTextureC, pixel, 0).rgb, vec3<f32>(0.0), vec3<f32>(1.0));   // inherited-C safe
  let finalRGB = mix(aces(color), prev_c, 0.06);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  // Facets sit proud of the plate where the light path is longest.
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth - pathLength * 0.02, 0.0, 1.0), 0.0, 0.0, 0.0));
}
