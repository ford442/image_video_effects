// ═══════════════════════════════════════════════════════════════════
//  Glass Bead Curtain v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba, semantic-alpha, temporal-state
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: string through the bore (a thin smoky thread runs through every bead column, wider seen through the glass, hanging in the gaps, swaying with its bead); off-axis chromatic focal spot (each ball lens throws its caustic on the side away from the light, blue focusing tighter than red → rainbow-edged hot spot); swing wake (the cursor spring's velocity drags nearby beads along the travel and they swing back). Rescued: DID NOT COMPILE (`let target` reserved); beads used a 2-D normal/view vector (upper half of every bead was Fresnel-mirror dark, no real rim) → 3-D sphere normal; click ripples dead (`r.w` is always 0); the (0,0) spring lived in the zeroed scratch buffer (held pull dead) → held-pull + cursor springs in two A texels; mouse delta mixed curtain units with uv; displaced beads were clipped at their own cell border → nearest bead over the 3×3 neighbourhood; the per-pixel depth-scaled lattice sheared every bead into a slanted oval → uniform lattice with the depth scale applied per bead radius; the reflected half of the Fresnel split was missing (rim just went dark) and the Hill-fit ACES at exposure 1.15 left the plain photo ~25 % dark → env reflection added, exposure 1.55. Review fixes: the click/hold pull follows a LIVE ripple (age < 1.4 s) instead of `u.config.y` (the ripple COUNT, which latched the pull on forever after one click); sway phase is per COLUMN (one smooth sinusoid down each thread — per-bead phases kinked the thread) and bass drives only the sway AMPLITUDE (a bass term inside the phase teleported the beads); pull + wake displacement clamped to 0.9 bead so a fast cursor cannot empty the window of beads.
//  A packing: ACES display RGBA (HEAD, 2 % C ghost). Texels (0,0) = (cursor centre.xy, velocity.xy) and (1,0) = (fract(lastTime), held-pull pos, held-pull vel, 0.7371 sentinel) are STATE, not pixels (top-left corner, invisible); C reads of those texels are masked.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const SENT: f32 = 0.7371;

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

// Displacement of one bead (bead units: curtainUV − centre + offset, so the bead appears moved by −offset).
// Wind sway + neighbour collision + vertical coupling are HEAD's; the cursor pull is HEAD's ×0.2 but with the
// aspect/unit mix fixed (distances in aspect-corrected uv, pull converted to bead units), and Idea 3's wake.
fn beadOffset(id: vec2<f32>, beadCount: f32, aspect: f32, time: f32, bass: f32,
              mouse: vec2<f32>, pullGain: f32, wakeUV: vec2<f32>) -> vec2<f32> {
  // One sway phase / collision hash per COLUMN (the bead sits on a string; `id.y * 0.35` is the travelling wave
  // down it), so neighbouring beads of a column move together and the thread through them stays continuous.
  // Bass only changes the amplitude: HEAD put it inside the phase (`time * (1.2 + bass * 2.5)`), which teleports
  // the whole pattern by time·Δbass whenever bass moves.
  let phase = hash12(vec2<f32>(id.x, 0.0)) * 6.28318;
  let windSway = sin(time * 1.2 + id.y * 0.35 + phase) * (0.10 + bass * 0.12);
  let neighborLeft = hash22(vec2<f32>(id.x - 1.0, 0.0)).x * 0.06;
  let neighborRight = hash22(vec2<f32>(id.x + 1.0, 0.0)).x * 0.06;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let ctrUV = vec2<f32>((id.x + 0.5) / (beadCount * aspect), (id.y + 0.5) / beadCount);
  let mDelta = ctrUV - mouse;
  let mDist = length(mDelta * aspectVec);
  let collisionPush = (neighborLeft - neighborRight) * (1.0 - smoothstep(0.0, 0.5, mDist));
  let verticalCoupling = sin(time * 0.8 + id.y * 0.6 + id.x * 0.3) * 0.04 * bass;
  let near = smoothstep(0.5, 0.0, mDist);

  // Held-pointer pull toward the cursor (bead units)
  let pullB = mDelta * aspectVec * beadCount * (pullGain * near * 0.2);

  // ── Idea 3: swing wake — beads near the cursor are dragged along its travel
  let wakeB = -wakeUV * aspectVec * beadCount * near;

  // The 3×3 nearest-bead search only finds beads displaced by less than ~1.5 cells (sway ≤ 0.32 included), so the
  // combined pull + wake is capped at 0.9 cell; unbounded it left a bead-free hole around a moving cursor.
  var drag = pullB + wakeB;
  drag = drag * min(1.0, 0.9 / max(length(drag), 0.0001));

  return vec2<f32>(windSway + collisionPush, verticalCoupling) + drag;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let isStateTexel = (gid.y == 0u && gid.x < 2u);

  // Click ripples that are alive right now. u.config.y is the ripple COUNT, and ripples are never aged out of the
  // list, so `config.y > 0` is true for the rest of the session after the first click (HEAD's "ripple alive" test
  // latched the held-pull spring on forever). Alive = inside the same 1.4 s window the ripple loop below uses.
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleAlive = false;
  for (var ri = 0u; ri < rippleCount; ri++) {
    let rz = u.ripples[ri].z;
    if (rz > 0.0 && time - rz > 0.0 && time - rz < 1.4) { rippleAlive = true; }
  }

  // Truthful three-band audio
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  // ── Sprung cursor + held-pull spring, persisted in two A texels ──
  // HEAD's spring (target = "any ripple alive", pos/vel in extraBuffer[133..134] written by thread (0,0))
  // lived in the scratch buffer that is re-uploaded zeroed every frame: springState ≈ 0, the held pull was dead.
  // Texel (0,0) = (cursor.xy, cursor vel.xy), texel (1,0) = (fract(lastTime), pullPos, pullVel, SENT).
  // Every thread integrates the same step from the stored state; the sentinel guards the first frame / inherited C.
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  var mouse = select(rawMouse, st0.xy, stateOk);
  var mouseVel = select(vec2<f32>(0.0), st0.zw, stateOk);
  var pullPos = select(0.0, st1.y, stateOk);
  var pullVel = select(0.0, st1.z, stateOk);
  let springDt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
  // cursor: critically damped, omega 8
  mouseVel = mouseVel + ((rawMouse - mouse) * 64.0 - mouseVel * 16.0) * springDt;
  mouse = mouse + mouseVel * springDt;
  // held pull: HEAD's 100 / 12 spring (omega 10, zeta 0.6) toward "held or a click ripple is alive"
  let pullTarget = select(0.0, 1.0, held || rippleAlive);
  pullVel = clamp(pullVel + ((pullTarget - pullPos) * 100.0 - pullVel * 12.0) * springDt, -20.0, 20.0);
  pullPos = clamp(pullPos + pullVel * springDt, -0.5, 1.5);
  // f16 rest-snap (A is rgba16float on most tiers): settle exactly once near and slow.
  let curSettled = all(abs(rawMouse - mouse) < vec2<f32>(0.004)) && length(mouseVel) < 0.06;
  mouse = select(mouse, rawMouse, curSettled);
  mouseVel = select(mouseVel, vec2<f32>(0.0), curSettled);
  let pullSettled = abs(pullTarget - pullPos) < 0.004 && abs(pullVel) < 0.06;
  pullPos = select(pullPos, pullTarget, pullSettled);
  pullVel = select(pullVel, 0.0, pullSettled);
  let springState = clamp(pullPos, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  // HEAD scaled the lattice count per PIXEL by (0.5 + depth·0.5): any depth gradient then sheared every bead into
  // a slanted oval and bent the strung threads. The lattice is now uniform (0.75 = HEAD's factor at mid depth) and
  // "depth controls perspective bead size" acts per bead below (radius scaled by the depth at the bead centre).
  let beadCount = mix(6.0, 32.0, 1.0 - u.zoom_params.x) * 0.75;
  let refraction = u.zoom_params.y * 0.10;
  let interactTension = mix(0.05, 0.45, u.zoom_params.z);
  let density = mix(0.25, 1.0, u.zoom_params.w);

  // Exact textureLoad from dataTextureC (state texels are not colour)
  let prevCRaw = textureLoad(dataTextureC, pixel, 0);
  let prevC = select(prevCRaw, vec4<f32>(0.0), isStateTexel);

  // Click ripples. HEAD gated on `r.w > 0.0`, but ripples[i].w is always 0 (padding), so every click was dead.
  var rippleEffect = 0.0;
  var rippleNormal = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i++) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (r.z > 0.0 && age > 0.0 && age < 1.4) {
      let delta = uv - r.xy;
      let d = length(delta * aspectVec);
      let radius = age * 1.5;
      let distFromFront = abs(d - radius);
      let intensity = smoothstep(0.15, 0.0, distFromFront) * smoothstep(2.0, 0.0, radius);
      rippleEffect += intensity;
      if (d > 0.0) {
        rippleNormal += (delta * aspectVec / d) * intensity * smoothstep(2.0, 0.0, radius);
      }
    }
  }

  // Swing wake: the sprung cursor's velocity (alive now), scaled by the Interact Tension slider
  let wakeUV = clamp(mouseVel * 0.08 * (interactTension / 0.25), vec2<f32>(-0.07), vec2<f32>(0.07));

  // Bead lattice. A swayed / pulled bead leaves its own cell, so take the nearest displaced bead over the 3×3
  // neighbourhood (HEAD drew a bead only from the pixel's own cell, clipping it at the cell border).
  let curtainUV = vec2<f32>(uv.x * beadCount * aspect, uv.y * beadCount);
  let baseId = floor(curtainUV);
  var beadId = baseId;
  var beadOff = vec2<f32>(0.0);
  var beadLocal = vec2<f32>(10.0);
  var bestD = 1.0e9;
  for (var j = -1; j <= 1; j++) {
    for (var k = -1; k <= 1; k++) {
      let id = baseId + vec2<f32>(f32(k), f32(j));
      let off = beadOffset(id, beadCount, aspect, time, bass, mouse, springState, wakeUV);
      let loc = curtainUV - (id + 0.5) + off;
      let dd = dot(loc, loc);
      if (dd < bestD) {
        bestD = dd;
        beadId = id;
        beadOff = off;
        beadLocal = loc;
      }
    }
  }
  let beadCenter = beadId + 0.5;
  let beadPhase = hash12(beadId) * 6.28318;
  // Perspective size per bead: radius ∈ [0.75, 1]·cell from the depth at the bead's (displaced) centre.
  let beadDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    clamp(vec2<f32>((beadCenter.x - beadOff.x) / (beadCount * aspect), (beadCenter.y - beadOff.y) / beadCount), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let beadScale = min(1.0, 0.75 / (0.5 + 0.5 * beadDepth));
  let threadLocal = beadLocal;
  beadLocal = beadLocal / beadScale;
  let beadDist = length(beadLocal);
  let beadMask = 1.0 - smoothstep(0.30, 0.50, beadDist);
  let sphereHeight = sqrt(max(0.0, 1.0 - beadDist * beadDist * 4.0));

  // Pull / ripple tilt of the bead surface (bead units). Ripples used 1.5·beadCount (≈ 28×, would flip every
  // bead edge-on); recalibrated to bead units.
  let beadCenterUV = vec2<f32>((beadCenter.x - beadOff.x) / (beadCount * aspect), (beadCenter.y - beadOff.y) / beadCount);
  let pullDelta = (beadCenterUV - mouse) * aspectVec;
  let pullDist = length(pullDelta);
  let pull = (1.0 - smoothstep(0.0, 0.40, pullDist)) * interactTension;
  let tilt = normalize(pullDelta + vec2<f32>(0.001, 0.0)) * pull + rippleNormal * 0.35;

  // Real 3-D sphere normal (HEAD: 2-D normal against a 2-D "view" (0,1): cosθ = max(0, n.y) made the whole upper
  // half of every bead Fresnel-mirror dark and left no rim). Radius 0.5 bead, view along +z.
  let p2 = beadLocal * 2.0;
  let zN = sqrt(max(0.0, 1.0 - dot(p2, p2)));
  let n3 = normalize(vec3<f32>(p2 + tilt, max(zN, 0.02)));
  let cosTheta = n3.z;
  let f0 = 0.04;
  let fresnel = fresnelSchlick(cosTheta, f0);

  // Ball-lens refraction offset (inverted image through the bead)
  let refractDir = -n3.xy * 1.3;

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

  // ── Idea 1: string through the bore ──────────────────────────────
  // The beads are strung: a thin smoky thread runs down every bead column. Through the glass the bore reads wider
  // (a ball lens magnifies it); between beads it hangs as a fine line. It lives in beadLocal, so it sways with
  // its bead and stays continuous down the column.
  let threadHalf = mix(0.024, 0.034, beadMask);
  let threadMask = 1.0 - smoothstep(threadHalf * 0.55, threadHalf, abs(threadLocal.x));
  refracted = mix(refracted, vec3<f32>(0.10, 0.085, 0.08), threadMask * 0.82);

  // ── Idea 2: off-axis chromatic focal spot ────────────────────────
  // A glass ball throws its focus on the side AWAY from the light, and blue focuses nearer than red
  // (longitudinal chromatic aberration). The (HEAD) white-blue spot sat dead-centre; now the focus centre moves
  // against the light direction and each channel has its own focal radius (R widest … B tightest), so the hot
  // spot has a red halo and a blue-white core.
  let lightXY = normalize(vec2<f32>(-0.6, -0.6));
  let focusLocal = beadLocal + lightXY * 0.14;
  let fd = length(focusLocal);
  let causticFocus = vec3<f32>(
    pow(max(0.0, 1.0 - fd * 2.0), 4.0),
    pow(max(0.0, 1.0 - fd * 2.2), 4.0),
    pow(max(0.0, 1.0 - fd * 2.5), 4.0));
  let causticPattern = pow(sin(beadLocal.x * 18.0 + beadLocal.y * 14.0 + time * 2.5 + beadPhase) * 0.5 + 0.5, 5.0);
  let causticRing = pow(sin(beadDist * 12.0 - time * 1.5) * 0.5 + 0.5, 3.0);
  let causticMod = (causticPattern * 0.6 + causticRing * 0.4) * (0.35 + mids * 0.65) * beadMask;
  let causticRGB = causticFocus * causticMod;
  let causticIntensity = causticRGB.y;

  let sssColor = mix(vec3<f32>(0.95, 0.35, 0.15), vec3<f32>(0.12, 0.60, 0.95), hash12(beadId));
  let sss = sssColor * causticRGB * density * 0.55;

  // Blinn glint on the dome (HEAD multiplied the sharp lobe by Fresnel ≈ 0.04 at the glint → invisible)
  let lightDir3 = normalize(vec3<f32>(-0.6, -0.6, 0.9));
  let halfV = normalize(lightDir3 + vec3<f32>(0.0, 0.0, 1.0));
  let nh = max(dot(n3, halfV), 0.0);
  let specularSharp = pow(nh, 96.0) * (0.85 + treble * 0.5) * beadMask;
  let specularBroad = pow(nh, 12.0) * 0.12 * beadMask * (1.0 - fresnel);
  let specular = specularSharp + specularBroad;

  // Reflected half of the Fresnel split (HEAD only subtracted it from the transmission, so the rim just went dark):
  // a sky-above / dark-ground-below environment, energy-matched to the transmission term below (uv y points down).
  let envColor = mix(vec3<f32>(0.18, 0.16, 0.18), vec3<f32>(0.75, 0.85, 1.0), clamp(0.5 - 0.5 * n3.y, 0.0, 1.0));
  let envReflect = fresnel * beadMask * density * 0.8;

  var finalColor = refracted * (1.0 - fresnel * beadMask * density * 0.8) + sss;
  finalColor = finalColor + vec3<f32>(1.0, 0.95, 0.85) * specular;
  finalColor = finalColor + envColor * envReflect;
  finalColor = finalColor + vec3<f32>(0.25, 0.55, 0.9) * causticRGB * 0.35 * density;

  let sparkle = pow(max(0.0, 1.0 - beadDist * 1.7), 6.0) * (0.15 + treble * 0.4);
  finalColor = finalColor + vec3<f32>(0.85, 0.92, 1.0) * sparkle;

  // Add prismatic high-end touch from ripples
  finalColor += vec3<f32>(0.2, 0.5, 1.0) * rippleEffect * beadMask * 0.5;

  // Exposure 1.55 (HEAD 1.15): the Hill-fit ACES maps a mid-grey photo to ~0.37, so gap pixels (the plain photo) came out ~25 % dark.
  finalColor = acesTonemap(max(finalColor, vec3<f32>(0.0)) * 1.55);

  let causticAlpha = causticIntensity * 0.75 + sparkle * 0.25 + beadMask * 0.15;

  // Semantic alpha: represents surface occlusion + glass density + emissive features (+ the thread, which is opaque)
  let baseAlpha = clamp(beadMask * density + causticAlpha * 0.5, 0.0, 1.0);
  let semanticAlpha = clamp(max(baseAlpha * (0.5 + depth * 0.5), threadMask * 0.85) + rippleEffect * 0.3, 0.05, 0.98);

  let finalRGBA = vec4<f32>(finalColor, semanticAlpha);

  let depthOut = clamp(mix(depth, depth * 0.25 + beadMask * sphereHeight * 0.75, 0.42), 0.0, 1.0);

  // State texels carry the springs instead of pixels (writeTexture is unaffected).
  var aOut = finalRGBA;
  if (gid.y == 0u && gid.x == 0u) { aOut = vec4<f32>(mouse, mouseVel); }
  if (gid.y == 0u && gid.x == 1u) { aOut = vec4<f32>(fract(time), pullPos, pullVel, SENT); }

  textureStore(writeTexture, pixel, finalRGBA);
  textureStore(dataTextureA, pixel, aOut);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
