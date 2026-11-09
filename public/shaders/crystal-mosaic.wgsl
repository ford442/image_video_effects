// ═══════════════════════════════════════════════════════════════════
//  Crystal Mosaic
//  Category: geometric
//  Features: mouse-driven, audio-reactive, depth-parallax, chromatic-edges,
//            crystal-refraction, caustics, rim-lighting, subsurface-scattering,
//            upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09, 2026-11-09
//  Ideas: facet crease along u=v; lead came at triangle borders;
//         chamfered tessera refraction with edge dispersion; chamfer faces lit by the cursor lamp;
//         hand-set tesserae (per-tile rotation + tint jitter)
//  A packing: ACES display RGBA
//  Rescue: rotation pivot / mouse-influence centre drifted off the tile (triCenter y, odd-row shift);
//          "edge" mask was the tile core (chromatic split moved to the real chamfer); dead radial chromaticAberration() branch removed;
//          per-frame hash sparkle strobe replaced by a smooth per-tile blink
//          mouse-influence zone aspect-corrected (round on wide screens); lamp has a reach (fades by 0.55)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = hash21(p);
  return vec2<f32>(h, fract(h * 43758.5453));
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// ═══ Crystal Fresnel Falloff ═══
fn crystalFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ Caustics Simulation (projected light patterns through crystal) ═══
fn caustics(uv: vec2<f32>, time: f32, intensity: f32) -> vec3<f32> {
  let p = uv * 8.0;
  var caustic = 0.0;
  // Overlapping wave interference patterns
  caustic = caustic + sin(p.x * 3.0 + time * 1.5) * cos(p.y * 2.5 - time * 1.2);
  caustic = caustic + sin(p.x * 2.0 - p.y * 3.0 + time * 2.0) * 0.5;
  caustic = caustic + sin(length(p) * 4.0 - time * 3.0) * 0.3;
  caustic = caustic * 0.5 + 0.5;
  caustic = pow(max(caustic, 0.0), 3.0); // Sharpen caustic bands

  // Warm caustic color: golden + cyan mix
  let warmCaustic = vec3<f32>(1.0, 0.85, 0.5) * caustic * intensity;
  let coolCaustic = vec3<f32>(0.5, 0.85, 1.0) * (1.0 - caustic) * intensity * 0.5;
  return warmCaustic + coolCaustic;
}

// ═══ Rim Lighting ═══
fn rimLighting(viewDir: vec3<f32>, normal: vec3<f32>, strength: f32) -> f32 {
  let rim = 1.0 - max(dot(viewDir, normal), 0.0);
  return pow(rim, 3.0) * strength;
}

// ═══ Subsurface Scattering Glow (light penetrating crystal) ═══
fn subsurfaceGlow(uv: vec2<f32>, lightPos: vec2<f32>, thickness: f32, intensity: f32) -> f32 {
  let d = length(uv - lightPos);
  // Light penetrates thin crystal edges, scatters inside
  let penetration = exp(-d * d * 8.0) * thickness;
  let scatter = exp(-d * 3.0) * 0.5;
  return (penetration + scatter) * intensity;
}

// ═══ Light Attenuation ═══
fn lightAttenuation(d: f32, k: f32, q: f32) -> f32 {
  return 1.0 / (1.0 + k * d + q * d * d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthShift = mix(-0.02, 0.02, depth);

    let density = mix(5.0, 40.0, u.zoom_params.x);
    let rotationAmt = u.zoom_params.y;
    let chromaticEdge = u.zoom_params.z * 0.01;
    let mouseInfluence = u.zoom_params.w;

    let s = uv * density;
    let i = floor(s.x);
    let j = floor(s.y * 0.8660254);
    let rowParity = i32(j) & 1;
    let u_frac = fract(s.x);
    let v_frac = fract(s.y * 0.8660254);

    // Triangle inside rhombus
    let triID = vec2<f32>(i + f32(rowParity) * 0.5, j);
    // R1: the true centre of the DRAWN tile. HEAD used (j + 0.57735)/density for y (drifts
    // 0.1547·j/density down the screen) and shifted odd rows half a tile the grid never had,
    // so the rotation pivot and the mouse-influence centre sat off their own tile.
    let tileCell = vec2<f32>(i, j);
    let triCenter = (tileCell + vec2<f32>(0.5)) / vec2<f32>(density, density * 0.8660254);

    // aspect-corrected (HEAD's influence zone was an ellipse on wide screens)
    let dToMouse = length((triCenter - mousePos) * vec2<f32>(aspect, 1.0));
    let influence = smoothstep(0.4, 0.0, dToMouse) * mouseInfluence;

    // ── Idea 3: hand-set tesserae ───────────────────────────────────────
    // Real mosaic tiles are set one by one, never at the same angle. Each tile gets its own
    // rotation offset (amplitude = the Rotation slider, so 0 keeps the grid aligned) and a
    // small brightness / warm-cool tint, so neighbours stop rotating in lockstep.
    let tileH = hash21(tileCell + vec2<f32>(7.3, 19.1));
    let tileT = hash21(tileCell + vec2<f32>(41.7, 5.3));
    let jitter = (tileH - 0.5) * rotationAmt * 1.4;
    let tileTint = (0.93 + 0.14 * tileT) * mix(vec3<f32>(1.02, 0.99, 0.95), vec3<f32>(0.95, 0.99, 1.03), tileT);

    // Rotate triangle based on mouse + audio
    let rot = (rotationAmt + influence + bass * 0.1) * 0.5 + jitter;
    let localUV = uv - triCenter;
    let c = cos(rot);
    let s_rot = sin(rot);
    let rotatedUV = vec2<f32>(
        localUV.x * c - localUV.y * s_rot,
        localUV.x * s_rot + localUV.y * c
    ) + triCenter + vec2<f32>(depthShift, depthShift);

    // Distance to the nearest tile border (tile units) and which side it is
    let du = min(u_frac, 1.0 - u_frac);
    let dv = min(v_frac, 1.0 - v_frac);
    let borderDist = min(du, dv);

    // R2: HEAD's "edge" is 1 at the tile CORE (a flat diamond), not at the edges. Caustics,
    // sparkle, env-Fresnel, rim and the SSS thickness keep it under its real name (a domed tile
    // focuses light in the middle; their strengths were tuned to that small core). Only the
    // chromatic split, which is named for edges, moves to the chamfer band below.
    let core = smoothstep(0.15, 0.0, abs(v_frac - 0.5) + abs(u_frac - 0.5) * 0.5);

    // ── Idea 1: chamfered tessera refraction + edge dispersion ──────────
    // A glass tessera has a chamfer just inside the lead came: a planar prism wedge. It deviates
    // the image toward the tile centre (small-angle thin-prism shift, scaled by tile size) and
    // splits R/B along that slope — the Chromatic Edge slider is the dispersion amplitude,
    // now where its name says (HEAD's radial branch was ~4e-5 uv and its live split sat
    // in the tile core).
    let useU = step(du, dv);
    let dirIn = mix(vec2<f32>(0.0, select(-1.0, 1.0, v_frac < 0.5)),
                    vec2<f32>(select(-1.0, 1.0, u_frac < 0.5), 0.0), useU);
    let bevel = 1.0 - smoothstep(0.17, 0.21, borderDist);
    let bevelDir = dirIn * bevel;
    let chamfer = bevelDir * (0.12 / density);
    let disp = bevelDir * chromaticEdge * 1.6;

    let rUV = clamp(rotatedUV + chamfer + disp * (1.0 + bass), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(rotatedUV + chamfer, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(rotatedUV + chamfer - disp * (1.0 + treble), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    var color = vec3<f32>(r, g, b) * tileTint;

    // ═══ CAUSTICS LIGHTING ═══
    // Project caustics onto tile surfaces, animated by time
    let causticIntensity = 0.5 + mids * 0.5 + influence * 0.3;
    let causticColor = caustics(triCenter + time * 0.05, time, causticIntensity);
    color = color + causticColor * core * (0.3 + bass * 0.2);

    // ═══ CRYSTAL FRESNEL REFLECTIONS ═══
    // Build approximate normal from tile orientation
    let tileNormal = normalize(vec3<f32>(cos(rot), sin(rot), 0.5 + core * 0.5));
    let viewDir = normalize(vec3<f32>(uv.x - 0.5, uv.y - 0.5, 1.0));
    let cosTheta = max(dot(viewDir, tileNormal), 0.0);
    let fresnel = crystalFresnel(cosTheta, 0.04); // Glass F0
    // Reflect environment color based on fresnel
    let envReflect = vec3<f32>(0.6, 0.7, 0.8) * fresnel * (0.5 + treble * 0.3);
    color = color + envReflect * core;

    // ═══ RIM LIGHTING (tile core, as HEAD) ═══
    let rim = rimLighting(viewDir, tileNormal, 1.0 + bass * 1.5);
    let rimColor = vec3<f32>(0.8, 0.9, 1.0) * rim * core * (0.5 + influence * 0.5);
    color = color + rimColor;

    // ── Idea 2: chamfer faces lit by the cursor lamp ────────────────────
    // The four chamfer faces of a tile lean outward (they slope down to the came). The lamp is
    // the cursor (the file already owns it): faces turned toward it brighten over what a flat
    // tile gets, faces turned away darken, and a Blinn glint runs on the faces whose tilt
    // matches the half-vector. Pointer strength rides Mouse Influence over its WHOLE range
    // (0 = no lamp, 1 = twice the default) and the lamp has a reach: it fades out by 0.55
    // (height units) so the picture far from the cursor stays as it was (review fix).
    let lampVec = vec3<f32>((mousePos - uv) * vec2<f32>(aspect, 1.0), 0.25);
    let lampDir = lampVec / max(length(lampVec), 1e-4);
    let chamferN = normalize(vec3<f32>(-dirIn * 0.55, 1.0));
    let lamb = max(dot(chamferN, lampDir), 0.0);
    let halfV = normalize(lampDir + vec3<f32>(0.0, 0.0, 1.0));
    let glint = pow(max(dot(chamferN, halfV), 0.0), 28.0);
    let lampReach = smoothstep(0.55, 0.10, length(lampVec.xy));
    let lampAmt = mouseInfluence * 2.0 * lampReach;
    color = color * max(1.0 + bevel * (lamb - lampDir.z) * 1.3 * lampAmt, 0.35);
    color = color + vec3<f32>(1.0, 0.96, 0.88) * bevel * glint * (0.3 + treble * 0.5) * lampAmt;

    // ═══ SUBSURFACE SCATTERING GLOW ═══
    // Light penetrates thin crystal edges
    let thickness = 1.0 - core; // Thinner at edges
    let sssGlow = subsurfaceGlow(uv, mousePos, thickness, 0.8 + mids * 0.5);
    let sssColor = mix(vec3<f32>(0.9, 0.6, 0.3), vec3<f32>(0.3, 0.6, 0.9), sin(time + triID.x * 0.5) * 0.5 + 0.5);
    color = color + sssColor * sssGlow * influence * 0.4;

    // Tile border highlight with light attenuation
    let border = smoothstep(0.05, 0.0, borderDist) * mids;
    let borderAtten = lightAttenuation(borderDist * 20.0, 0.1, 0.05);
    color = color + vec3<f32>(0.3, 0.2, 0.4) * border * borderAtten;

    // ═══ AUDIO-REACTIVE SPARKLE ON CRYSTAL FACETS ═══
    // R4: smooth per-tile blink (HEAD re-hashed every frame, which strobed under treble).
    let blinkRate = 3.0 + 4.0 * hash21(triID);
    let blink = max(sin(time * blinkRate + TAU * hash21(triID.yx)), 0.0);
    let sparkle = blink * blink * blink * blink * treble * core * 0.6;
    color = color + vec3<f32>(1.0, 0.95, 0.85) * sparkle;

    // Idea 1 (2026-09): facet crease — rhombus splits into two flat faces along u=v.
    let crease = 1.0 - smoothstep(0.0, 0.045, abs(u_frac - v_frac));
    color = color * (1.0 - crease * 0.28);

    // Idea 2 (2026-09): lead came — dark grout at triangle borders.
    let came = 1.0 - smoothstep(0.0, 0.07, borderDist);
    color = mix(color, color * vec3<f32>(0.12, 0.10, 0.14), came * 0.72);

    let srcA = textureSampleLevel(readTexture, u_sampler, clamp(rotatedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).a;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.85 + border * 0.15 + luma * 0.2 + bass * 0.05 + core * 0.1 + srcA * 0.05, 0.0, 1.0);
    let mapped = acesToneMap(clamp(color, vec3<f32>(0.0), vec3<f32>(4.0)));
    let outCol = vec4<f32>(mapped, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outCol);
    textureStore(dataTextureA, global_id.xy, outCol);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
