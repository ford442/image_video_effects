// ═══════════════════════════════════════════════════════════════════
//  crystal-illuminator-iridescence — Faceted Thin-Film Crystal
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            voronoi-facets, thin-film-interference, fresnel,
//            semantic-alpha, ACES
//  Complexity: Very High
//  Upgraded: 2026-10-18
//  Ideas: uniaxial crystal birefringent double refraction (o-ray / e-ray optic-axis split) & crystallographic cleavage growth steps; sub-facet internal reflection bounce between neighboring grain boundaries & fluid-inclusion sparkle
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=CellDensity, y=IORMix, z=LightPower, w=FilmThickness

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn fresnelIOR(cosTheta: f32, ior: f32) -> f32 {
  let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
  return fresnelSchlick(cosTheta, F0);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
  let g = 1.0 - abs(t - 0.45) * 2.5;
  let b = 1.0 - smoothstep(0.0, 0.45, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
  let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
  let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
  let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
  var color = vec3<f32>(0.0);
  var sampleCount = 0.0;
  for (var lambda = 380.0; lambda <= 700.0; lambda += 25.0) {
    let phase = opd / lambda;
    let interference = cos(phase * 6.2831853) * 0.5 + 0.5;
    color += wavelengthToRGB(lambda) * interference;
    sampleCount += 1.0;
  }
  return color / max(sampleCount, 1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Critically damped spring cursor in extraBuffer[133..138]
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
    let stiffness = 42.0;
    let damping = 12.96; // 2 * sqrt(42)
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

  // Exact parameter contracts
  let cell_density = mix(5.0, 30.0, u.zoom_params.x) * (1.0 + bass * 0.15);
  let iorMix = u.zoom_params.y;
  let light_power = u.zoom_params.z * 2.0 * (1.0 + mids * 0.3);
  let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.w) * (1.0 + treble * 0.2);
  let filmIOR = mix(1.2, 2.4, u.zoom_params.y);

  let IOR_QUARTZ: f32 = 1.54;
  let IOR_DIAMOND: f32 = 2.42;
  let ior = mix(IOR_QUARTZ, IOR_DIAMOND, iorMix);

  // Voronoi grid
  let uv_scaled = uv * cell_density;
  let uv_id = floor(uv_scaled);
  let uv_st = fract(uv_scaled);

  var min_dist = 100.0;
  var second_min_dist = 100.0;
  var cell_center = vec2<f32>(0.0);
  var cell_id = vec2<f32>(0.0);

  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let seed = hash22(uv_id + neighbor);
      let anim = 0.5 + 0.5 * sin(time * 0.5 + 6.2831853 * seed);
      let p = neighbor + seed * anim;
      let dist = length(uv_st - p);
      if (dist < min_dist) {
        second_min_dist = min_dist;
        min_dist = dist;
        cell_center = p;
        cell_id = uv_id + neighbor;
      } else if (dist < second_min_dist) {
        second_min_dist = dist;
      }
    }
  }

  // Facet normal + Idea 1: Crystallographic cleavage growth steps along per-grain optic axis
  let n_hash = hash22(cell_id + vec2<f32>(12.34, 56.78));
  let opticAngle = hash21(cell_id + vec2<f32>(7.13, 3.91)) * 6.2831853;
  let opticAxis = vec2<f32>(cos(opticAngle), sin(opticAngle));
  let local_uv = uv_st - cell_center;
  let cleavageCoord = dot(local_uv, opticAxis) * 14.0;
  let cleavageStep = smoothstep(0.38, 0.48, abs(fract(cleavageCoord) - 0.5));
  let cleavageNormal = vec3<f32>(opticAxis * cleavageStep * 0.22, 0.0);

  var facet_normal = normalize(vec3<f32>(n_hash.x - 0.5, n_hash.y - 0.5, 0.5) + cleavageNormal);
  let curvature = vec3<f32>(local_uv, sqrt(max(0.0, 1.0 - dot(local_uv, local_uv))));
  let roughness = 0.2;
  facet_normal = normalize(mix(facet_normal, curvature, roughness));

  // Light from spring mouse
  let light_pos = vec3<f32>(mouse, 0.2);
  let pixel_pos = vec3<f32>(uv, 0.0);
  let light_vec = light_pos - pixel_pos;
  let light_dist = length(light_vec);
  let light_dir = normalize(light_vec);
  let view_dir = vec3<f32>(0.0, 0.0, 1.0);
  let cosTheta = max(dot(facet_normal, view_dir), 0.0);
  let fresnel = fresnelIOR(cosTheta, ior);

  let edge_dist = second_min_dist - min_dist;
  let edge_factor = smoothstep(0.05, 0.0, edge_dist);

  let diffuse = max(0.0, dot(facet_normal, light_dir));
  let specular = pow(max(0.0, dot(reflect(-light_dir, facet_normal), view_dir)), 32.0);
  let attenuation = 1.0 / (1.0 + light_dist * light_dist * 10.0);
  let lighting = (diffuse + specular) * light_power * attenuation;
  let ambient = 0.5;

  let refract_offset = facet_normal.xy * 0.1 * (ior - 1.0);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleDistort = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleDistort += rDir * wave * 0.03;
    }
  }

  // Idea 1: Uniaxial crystal birefringent double refraction (o-ray / e-ray optic-axis split)
  let sinThetaSq = max(0.0, 1.0 - cosTheta * cosTheta);
  let birefringentSplit = opticAxis * (0.004 + 0.014 * iorMix) * (0.35 + 0.65 * sinThetaSq);
  let read_uv_o = clamp(uv + refract_offset - birefringentSplit + rippleDistort, vec2<f32>(0.001), vec2<f32>(0.999));
  let read_uv_e = clamp(uv + refract_offset + birefringentSplit + rippleDistort, vec2<f32>(0.001), vec2<f32>(0.999));
  let tex_o = textureSampleLevel(readTexture, u_sampler, read_uv_o, 0.0).rgb;
  let tex_e = textureSampleLevel(readTexture, u_sampler, read_uv_e, 0.0).rgb;
  let polAngle = dot(normalize(local_uv + vec2<f32>(0.0001)), opticAxis);
  let malusWeight = polAngle * polAngle;
  let tex_color = mix(tex_o, vec3<f32>(tex_e.r, mix(tex_o.g, tex_e.g, 0.6), tex_e.b), 0.35 + 0.45 * malusWeight);

  // Thin-Film Iridescence per Facet
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let toCenter = uv - vec2<f32>(0.5);
  let distCenter = length(toCenter);
  let viewCosTheta = sqrt(max(1.0 - distCenter * distCenter * 0.5, 0.01));

  let cellThickness = filmThicknessBase * (0.7 + depth * 0.6 + hash21(cell_id) * 0.3 + cleavageStep * 0.14);
  let mouseDist = length(uv - mouse);
  let mouseInfluence = exp(-mouseDist * mouseDist * 800.0) * held;
  let thickness = cellThickness + mouseInfluence * 300.0 * sin(time * 3.0 + mouseDist * 30.0);

  let iridescent = thinFilmColor(thickness, viewCosTheta, filmIOR);

  // Idea 2: Sub-facet internal reflection bounce off steep inter-grain boundaries & fluid-inclusion sparkle
  let boundaryWall = smoothstep(0.18, 0.015, edge_dist) * (1.0 - edge_factor);
  let boundaryNormal = normalize(vec3<f32>(-local_uv, 0.25));
  let internalBounceSpec = pow(max(0.0, dot(reflect(-light_dir, boundaryNormal), view_dir)), 18.0);
  let internalFacetBounce = iridescent * boundaryWall * internalBounceSpec * light_power * attenuation * 1.35;
  let incSeed = hash22(cell_id * 3.7 + floor(local_uv * 6.0));
  let incDist = length(fract(local_uv * 6.0) - vec2<f32>(0.5) - (incSeed - 0.5) * 0.35);
  let inclusionGlint = smoothstep(0.12, 0.01, incDist) * step(0.72, incSeed.x) * pow(max(0.0, dot(facet_normal, light_dir)), 8.0) * light_power * attenuation;

  let fresnelBlend = pow(1.0 - viewCosTheta, 3.0);
  let facetColor = mix(tex_color, iridescent, fresnelBlend * 0.7);

  var final_color = facetColor * (ambient + lighting);
  final_color += vec3<f32>(specular * attenuation * light_power);
  final_color += vec3<f32>(fresnel * 0.3);
  final_color += internalFacetBounce + mix(vec3<f32>(1.0, 0.92, 0.7), iridescent, 0.5) * inclusionGlint * 0.85;
  final_color = mix(final_color, iridescent * 1.5, edge_factor * 0.5);

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, coord, 0).rgb;
  final_color = mix(final_color, prevC, 0.07);

  let finalRGB = aces(final_color);

  let path_length = mix(0.05, 0.3, min_dist * 2.0);
  let cell_purity = 0.6 + 0.4 * hash21(cell_id);
  let absorptionCoeff = mix(0.3, 2.0, 1.0 - cell_purity);
  let absorption = exp(-absorptionCoeff * path_length);
  let transmission = absorption * (1.0 - fresnel) * cell_purity;
  let tir = smoothstep(0.3, 0.0, cosTheta) * 0.3;
  let alpha = clamp(transmission + tir + held * 0.1, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(dataTextureA, coord, finalPixel);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
