// ═══════════════════════════════════════════════════════════════════
//  Glass Brick Wall — Textured Architectural Glass Surface
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            caustic-refraction, chromatic-dispersion, fbm-texture, beer-lambert, ACES
//  Ideas:    1. dome dispersion — R/B split along each brick's dome normal, blue bending
//               hardest, instead of one fixed diagonal offset
//            2. dome caustic — each brick focuses its own light into a hot-spot
//            3. green block edges — Beer-Lambert path grows toward the side walls
//            4. wall reflection — side walls mirror the brick interior (internal reflection)
//            5. cast-block variation — every block has its own iron tint, dome tilt and focus jitter
//            6. hollow-core cavity — inner frame at the cavity wall: weaker refraction inside, lit wall line
//            7. lamp-driven caustic focus — near the pointer lamp each dome focuses on its far side
//  Complexity: High
//  Upgraded: 2026-11-09
//  A packing: ACES display RGBA (unchanged); C is the 7 % display ghost
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=BrickSize, y=Distortion, z=MortarSize, w=GlassDensity

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var total = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    total += amplitude * noise2(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.1;
  }
  return total;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Raw pointer: the old extraBuffer[133..138] spring raced (pixel (0,0) wrote
  // while every other pixel read) and the buffer is re-uploaded each frame.
  let mouse = rawMouse;

  // Exact parameter contracts
  let brickSize = mix(10.0, 54.0, u.zoom_params.x);
  let distortion = mix(0.0, 0.12, u.zoom_params.y);
  let mortarSize = mix(0.01, 0.12, u.zoom_params.z);
  let glassDensity = mix(0.6, 2.6, u.zoom_params.w);

  let gridUV = uv * vec2<f32>(brickSize * aspect, brickSize);
  let cellId = floor(gridUV);
  let cell = fract(gridUV) - 0.5;
  let edgeMax = max(abs(cell.x), abs(cell.y));

  // Idea 5: cast-block variation. Glass blocks are pressed one by one: each has its own iron content,
  // dome tilt and thickness, so the wall reads hand-laid instead of stamped from one tile.
  let blockH = vec3<f32>(hash12(cellId + vec2<f32>(17.3, 5.1)),
                         hash12(cellId + vec2<f32>(41.7, 29.9)),
                         hash12(cellId + vec2<f32>(83.1, 61.3)));

  // Idea 6: hollow-core cavity. A glass block is two fused halves around an air gap; its inner wall is a
  // frame inside the frame. Inside it the ray crosses air, so the dome refracts less (a refractive step).
  let inCavity = 1.0 - smoothstep(0.322, 0.338, edgeMax);

  // FBM-perturbed normal for organic glass surface
  let normalNoise = fbm(cell * 4.0 + cellId * 0.5 + time * 0.05, 5) * 0.15;
  let normalXY = cell * -2.0 + vec2<f32>(normalNoise, normalNoise * 0.7);
  let normalZ = sqrt(max(0.0, 1.0 - dot(normalXY, normalXY)));
  let normal = normalize(vec3<f32>(normalXY, normalZ));
  let mortarMask = smoothstep(0.48 - mortarSize, 0.5, max(abs(cell.x), abs(cell.y)));

  // Pointer interaction
  let p_dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let ptr_influence = smoothstep(0.35 + held * 0.15, 0.0, p_dist) * (1.0 + bass * 0.5);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var click_wave = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rAge = time - rp.z;
    if (rAge >= 0.0 && rAge < 2.0) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - rAge * 0.5) * 30.0) * exp(-rDist * 3.5) * exp(-rAge * 1.4);
      click_wave += abs(wave) * 0.4;
    }
  }

  let castTilt = (blockH.xy - 0.5) * 0.10;   // Idea 5: per-block dome tilt
  let refractOffset = (normal.xy + castTilt) * mix(1.0, 0.55, inCavity) * distortion * (1.0 - mortarMask) * (1.0 + bass * 0.35 + ptr_influence * 0.2 + click_wave * 0.5);
  let frontUV = clamp(uv + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  let gridScale = vec2<f32>(brickSize * aspect, brickSize);
  let brickCenterUV = (cellId + 0.5) / gridScale;

  // Idea 1: dome dispersion. Each colour refracts along the dome normal by its
  // own amount (Cauchy order, so blue bends most), and denser glass disperses
  // more. The fringes follow every brick's curvature instead of one diagonal.
  let dispAmt = distortion * 0.12 * (0.5 + glassDensity * 0.3) * (0.5 + treble * 0.5) * (1.0 - mortarMask);
  let dispDir = normal.xy;
  let cr = textureSampleLevel(readTexture, u_sampler, clamp(frontUV - dispDir * dispAmt, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let cg = textureSampleLevel(readTexture, u_sampler, frontUV, 0.0).g;
  let cb = textureSampleLevel(readTexture, u_sampler, clamp(frontUV + dispDir * dispAmt * 1.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let base_a = textureSampleLevel(readTexture, u_sampler, frontUV, 0.0).a;

  var color = vec3<f32>(cr, cg, cb);

  // Idea 4: wall reflection. Near the side walls of a block, total internal
  // reflection shows the brick's own interior flipped across the wall it
  // faces, compressed into the band.
  let wallBand = smoothstep(0.30, 0.46 - mortarSize * 0.5, edgeMax) * (1.0 - mortarMask);
  var cellR = cell;
  if (abs(cell.x) > abs(cell.y)) { cellR.x = -cell.x * 0.6; } else { cellR.y = -cell.y * 0.6; }
  let wallUV = clamp((cellId + 0.5 + cellR) / gridScale + refractOffset * 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let wallImg = textureSampleLevel(readTexture, u_sampler, wallUV, 0.0).rgb;
  color = mix(color, wallImg * 1.1, wallBand * (0.25 + u.zoom_params.w * 0.3));

  var finalAlpha = base_a;
  let lightDir = normalize(vec3<f32>(0.0, 0.0, 1.0));
  let spec = pow(max(dot(normal, lightDir), 0.0), 32.0) * (0.5 + mids);
  let glassColor = vec3<f32>(0.85, 0.94, 1.0) * (1.0 - glassDensity * 0.15) * (1.0 + (blockH - 0.5) * vec3<f32>(0.05, 0.03, 0.06));

  // Idea 3: green block edges. The light path runs longest through a glass
  // block near its walls, and iron in the glass absorbs red and blue there,
  // which turns the edges bottle-green. Glass Density scales the path.
  let pathLen = glassDensity * (0.3 + edgeMax * edgeMax * 4.8);
  let ironVar = 0.75 + 0.5 * blockH.z;      // Idea 5: iron content differs block to block
  let blockTint = exp(-vec3<f32>(0.35, 0.08, 0.22) * pathLen * 0.6 * ironVar);

  // Idea 2: dome caustic. The domed face focuses light from the whole brick
  // into a soft hot-spot that drifts with the FBM surface, and bass pumps it.
  // Idea 7: lamp-driven focus. A dome focuses on the side AWAY from its light, so inside the pointer's
  // halo each block's hot-spot slides to the far side of the dome from the cursor and burns a little
  // brighter; outside the halo (and with the pointer far away) it keeps HEAD's fixed focus.
  let lampDir = (uv - mouse) * vec2<f32>(aspect, 1.0) / max(p_dist, 1e-3);
  let lampMix = clamp(ptr_influence, 0.0, 1.0);
  let focusHead = vec2<f32>(0.10, -0.08) + vec2<f32>(normalNoise, -normalNoise) * 0.6;
  let focusPt = mix(focusHead + (blockH.xy - 0.5) * 0.12, lampDir * 0.22, lampMix);   // Idea 5 jitter fades near the lamp
  let spotD = length(cell - focusPt);
  let caustic = exp(-spotD * spotD * 60.0) * (1.0 - mortarMask);
  let brickLight = textureSampleLevel(readTexture, u_sampler, brickCenterUV, 0.0).rgb;
  let causticCol = brickLight * caustic * (0.45 + bass * 0.4) * (0.6 + distortion * 5.0) * (0.85 + 0.3 * blockH.x) * (1.0 + 0.8 * lampMix);

  // Idea 6 (cont.): the cavity wall is a thin lit line, bright on the walls that face the lamp
  // (upper-left) and nearly dark on the far walls.
  let wallN = select(vec2<f32>(0.0, sign(cell.y)), vec2<f32>(sign(cell.x), 0.0), abs(cell.x) > abs(cell.y));
  let cavLit = max(dot(wallN, vec2<f32>(-0.6, -0.8)), 0.0);
  let cavLine = (1.0 - smoothstep(0.0, 0.024, abs(edgeMax - 0.33))) * (1.0 - mortarMask);
  let cavityGlow = cavLine * (0.05 + 0.28 * cavLit) * (0.8 + 0.4 * mids);

  let glassCol = color * glassColor * blockTint + spec + causticCol + vec3<f32>(0.85, 0.95, 1.0) * cavityGlow;
  let mortarCol = color * 0.3; // mortar is dark
  let mortarW = smoothstep(0.4, 0.6, mortarMask);
  color = mix(glassCol, mortarCol, mortarW);
  finalAlpha = mix(mix(0.85, 0.3, 1.0 - mortarMask), 0.95, mortarW);
  finalAlpha = finalAlpha - 0.08 * inCavity * (1.0 - mortarW) + cavityGlow * 0.3;   // the air gap transmits more

  // HEAD scaled this by mids alone, so the pointer halo vanished without audio.
  color += ptr_influence * vec3<f32>(0.2, 0.4, 0.8) * (0.2 + mids);
  color += click_wave * vec3<f32>(1.0, 0.85, 0.5);

  // Exact dataTextureC persistence, blended in display space (C holds ACES output).
  let prevC = clamp(textureLoad(dataTextureC, pixel, 0).rgb, vec3<f32>(0.0), vec3<f32>(1.0));   // inherited-C safe
  let finalRGB = mix(aces(color), prevC, 0.07);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, frontUV, 0.0).r;
  let finalPixel = vec4<f32>(finalRGB, clamp(finalAlpha + ptr_influence * 0.1, 0.1, 1.0));

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
