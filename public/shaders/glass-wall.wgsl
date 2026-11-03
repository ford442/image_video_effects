// ═══════════════════════════════════════════════════════════════
// Glass Wall — Upgraded with Alpha-Channel Translucency Blending
// Category: interactive-mouse
// Features: refraction, spectral-tint, upgraded-rgba
// Upgraded: 2026-11-01
// Ideas: per-channel refraction (R/G/B sample at 1-k / 1 / 1+k of the glass offset, k from thickness); hammered-glass curvature caustic (Laplacian of the height field focuses warm filaments on convex crests)
// A packing: display RGBA (ACES) + semantic alpha
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ Math Snippets ═══
fn ACESFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (lambda < 440.0) { r = (440.0 - lambda) / 60.0; b = 1.0; }
  else if (lambda < 490.0) { g = (lambda - 440.0) / 50.0; b = 1.0; }
  else if (lambda < 510.0) { g = 1.0; b = (510.0 - lambda) / 20.0; }
  else if (lambda < 580.0) { r = (lambda - 510.0) / 70.0; g = 1.0; }
  else if (lambda < 645.0) { r = 1.0; g = (645.0 - lambda) / 65.0; }
  else { r = 1.0; }
  var intensity = 1.0;
  if (lambda < 420.0) { intensity = 0.3 + 0.7 * (lambda - 380.0) / 40.0; }
  else if (lambda > 700.0) { intensity = 0.3 + 0.7 * (780.0 - lambda) / 80.0; }
  return clamp(vec3(r, g, b) * intensity, vec3(0.0), vec3(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p2 = fract(p * vec2<f32>(127.1, 311.7));
    p2 += dot(p2, p2.yx + 19.19);
    return fract((p2.x + p2.y) * p2);
}

// Continuous geometry
fn glassHeight(uv: vec2<f32>, time: f32, bass: f32, mid: f32) -> f32 {
    var p = uv * 5.0;
    var h = 0.0;
    var amp = 1.0;
    for(var i=0; i<4; i++) {
        p += sin(p.yx * 1.5 + time * 0.5) * (0.5 + bass * 0.1);
        h += sin(p.x) * cos(p.y) * amp;
        p *= 1.8;
        amp *= 0.5;
        p += vec2<f32>(mid * 0.2);
    }
    return h;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let time = u.config.x;
  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / dims.y;
  let pointerDown = u.zoom_config.w;

  // Single writer for bounded spring state
  if (gid.x == 0u && gid.y == 0u) {
    var posX = extraBuffer[133];
    var posY = extraBuffer[134];
    var velX = extraBuffer[135];
    var velY = extraBuffer[136];
    
    let dt = 0.016;
    let stiffness = 100.0;
    let damping = 10.0;
    var targetX = 0.5;
    var targetY = 0.5;
    
    if (pointerDown > 0.5) {
      targetX = u.zoom_config.y;
      targetY = u.zoom_config.z;
    }
    
    let forceX = (targetX - posX) * stiffness - velX * damping;
    let forceY = (targetY - posY) * stiffness - velY * damping;
    
    velX += forceX * dt;
    velY += forceY * dt;
    
    let maxVel = 4.0;
    let speed = sqrt(velX * velX + velY * velY);
    if (speed > maxVel) {
      velX = (velX / speed) * maxVel;
      velY = (velY / speed) * maxVel;
    }
    
    extraBuffer[133] = posX + velX * dt;
    extraBuffer[134] = posY + velY * dt;
    extraBuffer[135] = velX;
    extraBuffer[136] = velY;
    extraBuffer[137] = targetX;
    extraBuffer[138] = targetY;
  }

  // Use spring position
  let springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Exact textureLoad from dataTextureC
  let dataC = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);

  // Capped click ripples. HEAD gated on ripples[i].w, which is always 0 (padding), so clicks never
  // reached the glass; the age now comes from ripples[i].z like every other shader.
  var rippleOffset = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let rAge = time - r.z;
    if (rAge >= 0.0 && rAge < 4.0) {
      let d = distance(uv, r.xy);
      let waveFront = rAge * 0.8;
      let distFromFront = abs(d - waveFront);
      if (distFromFront < 0.1) {
        let wave = sin((d - waveFront) * 50.0) * smoothstep(0.1, 0.0, distFromFront);
        let attenuation = exp(-rAge * 1.5) / (1.0 + d * 5.0);
        rippleOffset += normalize(uv - r.xy + 0.0001) * wave * attenuation * 0.03;
      }
    }
  }

  // Calculate intricate geometry normal
  let eps = 0.002;
  let gridScale = mix(1.0, 5.0, u.zoom_params.y);
  let h = glassHeight(uv * gridScale, time, bass, mid);
  let hx = glassHeight((uv + vec2<f32>(eps, 0.0)) * gridScale, time, bass, mid);
  let hy = glassHeight((uv + vec2<f32>(0.0, eps)) * gridScale, time, bass, mid);
  // Floor fix (not an idea): HEAD's z of eps*15 left the normal almost horizontal everywhere, so the
  // tilt sat at ~1, the spectral tint pinned to 650 nm and the whole wall rendered as a red wash
  // (the shipped thumbnail is that wash). eps*200 keeps the tilt in the 0.2..0.6 range the tint expects.
  var normal = normalize(vec3<f32>(h - hx, h - hy, eps * 200.0));

  // Idea 2: hammered-glass curvature caustic. Second differences of the same height field (two more
  // evaluations on the minus side). Where the surface is convex (negative Laplacian) it acts as a
  // converging lens and focuses light into bright filaments; concave and flat regions get nothing.
  let hxm = glassHeight((uv - vec2<f32>(eps, 0.0)) * gridScale, time, bass, mid);
  let hym = glassHeight((uv - vec2<f32>(0.0, eps)) * gridScale, time, bass, mid);
  let lapH = ((hx + hxm - 2.0 * h) + (hy + hym - 2.0 * h)) / (eps * eps);
  let convexity = clamp(-lapH / (gridScale * gridScale * 420.0), 0.0, 3.0);
  let causticFocus = smoothstep(0.55, 1.6, convexity);

  // Add spring pointer influence
  let interactionRad = mix(1.0, 8.0, u.zoom_params.z);
  let pointerDist = distance(uv * vec2<f32>(aspect, 1.0), springPos * vec2<f32>(aspect, 1.0));
  let pointerInfluence = exp(-pointerDist * interactionRad);
  normal = normalize(normal + vec3<f32>(normalize(uv - springPos + 0.0001) * pointerInfluence * 0.3, 0.0));

  // Add ripple influence
  normal = normalize(normal + vec3<f32>(rippleOffset * 20.0, 0.0));

  // Refraction
  let refractionStrength = (0.08 + bass * 0.02) * mix(0.1, 2.0, u.zoom_params.x);
  let offset = normal.xy * refractionStrength;
  let finalUV = uv + offset;
  
  // Idea 1: per-channel refraction. Blue bends more than red through glass, so the three channels
  // sample at 1-k / 1 / 1+k of the offset, with k growing with the local thickness. The spectral tint
  // below stays; this adds the lateral fringe it only imitated.
  let thickness = 0.1 + abs(h) * 0.2;
  let dispK = (0.05 + thickness * 0.25) * (1.0 + bass * 0.5);
  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uv + offset * (1.0 - dispK), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uv + offset * (1.0 + dispK), 0.0).b
  );

  // Prismatic chromatic aberration / spectral tint
  let tiltMag = length(normal.xy);
  let wavelength = mix(450.0, 650.0, clamp(tiltMag * 2.0 + treble * 0.5, 0.0, 1.0));
  let spectralColor = wavelengthToRGB(wavelength);
  color = mix(color, color * spectralColor * 2.0, smoothstep(0.0, 0.5, tiltMag));

  // Glass physical properties
  // Evaluate unused parameters
  let unused_x = u.zoom_params.x;
  let unused_y = u.zoom_params.y;
  let unused_z = u.zoom_params.z;

  let glassDensity = u.zoom_params.w * 2.0 + 0.5;
  
  // Specular lighting
  let lightDir = normalize(vec3<f32>(0.5, 0.5, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfDir = normalize(lightDir + viewDir);
  // Exponent 32 -> 160: with the rescued (flatter) normal the old lobe covered the whole frame as a veil.
  let spec = pow(max(dot(normal, halfDir), 0.0), 160.0);
  
  // Fresnel
  let cosTheta = max(dot(viewDir, normal), 0.0);
  let F0 = 0.04;
  let fresnel = F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);

  // Absorption
  let glassBaseColor = vec3<f32>(0.92, 0.97, 1.0);
  let absorption = exp(-(vec3<f32>(1.0) - glassBaseColor) * thickness * glassDensity * 5.0);
  color = color * absorption;
  
  // Add specular and fresnel
  color += vec3<f32>(spec) * (0.8 + treble * 0.2) + fresnel * 0.5;
  color += vec3<f32>(1.0, 0.92, 0.72) * causticFocus * (0.25 + thickness) * (0.55 + bass * 0.4 + treble * 0.2);

  // Depth compositing
  let depthOut = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let backgroundDepth = smoothstep(0.0, 0.8, depthOut);
  color *= mix(1.0, 0.6, backgroundDepth);
  
  // Use dataC somehow to avoid warnings if it's strictly required
  color += dataC.xyz * 0.0001;

  // ACES Tone mapping
  color = ACESFilm(color);

  // Semantic alpha based on optical density and pointer interaction
  let alpha = clamp(thickness * 1.5 + pointerInfluence * 0.5 + fresnel, 0.3, 0.95);

  textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
  textureStore(dataTextureA, gid.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
