// ═══════════════════════════════════════════════════════════════════
//  Glass Brick Distortion
//  Category: distortion
//  Features: mouse-driven, depth-aware, audio-reactive, temporal, chromatic-aberration, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: vertical fluted ribs with crest highlight; grout-edge mirror bevel with specular line; per-brick batch tint and thickness
//  A packing: ACES display RGBA (HEAD; C read back as colour history)
// ═══════════════════════════════════════════════════════════════════
//  Each brick is a plano-convex lens magnifying its own centre, now ribbed
//  like architectural fluted glass. Pointer opens a clear zone; clicks send
//  ripple shocks. The extraBuffer[133..138] spring is HEAD's (runtime zeroes
//  that range each frame, so it is a harmless no-op and mouse = raw pointer).

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BrickSize, y=IORStrength, z=ChromaticAberration, w=DepthInfluence
  ripples: array<vec4<f32>, 50>,
};

fn schlick(cosTheta: f32, R0: f32) -> f32 {
  return R0 + (1.0 - R0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Hoskins hash (no sin; stable for large drifting brick ids)
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
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
    let stiffness = 40.0;
    let damping = 12.65; // 2 * sqrt(40)
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
  let brickCount = u.zoom_params.x * 38.0 + 4.0;
  let iorStr = u.zoom_params.y * 0.14 + 0.01;
  let chromaStr = u.zoom_params.z * 0.08;
  let depthInfl = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let thickness = 0.08 + depth * depthInfl * 0.12;
  let iorEff = iorStr * (1.0 + thickness) * (1.0 + bass * 0.25);

  let drift = time * 0.05 * (1.0 + mids * 0.5);

  // Mouse clear zone
  let mDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let clearMask = 1.0 - smoothstep(0.06, 0.18 + held * 0.15, mDist); // == HEAD's reversed smoothstep

  // Brick grid geometry
  let uvS = (uv + vec2<f32>(drift, -drift)) * vec2<f32>(brickCount * aspect, brickCount);
  let brickId = floor(uvS);
  let brickUV = fract(uvS);
  let bCenter = (brickId + 0.5) / vec2<f32>(brickCount * aspect, brickCount) - vec2<f32>(drift, -drift);

  let groutW = 0.04;
  let isGrout = select(0.0, 1.0, brickUV.x < groutW || brickUV.x > 1.0 - groutW || brickUV.y < groutW || brickUV.y > 1.0 - groutW);

  // Plano-convex lens offset
  let bCentered = brickUV - 0.5;
  let lensMag = dot(bCentered, bCentered);
  let lensOffset = bCentered * (0.5 - lensMag) * iorEff;

  // Idea 1 — Flutes: six vertical ribs per brick. Rib surface h = -cos(phase),
  // so its slope sin(phase) bends the sample sideways; the ribs ride the IOR
  // slider and go through the same R/G/B dispersion as the lens.
  let fluteCount = 6.0;
  let flutePhase = brickUV.x * fluteCount * 6.2831853;
  let fluteOffset = vec2<f32>(sin(flutePhase) * iorEff * 0.045, 0.0);
  let baseOffset = lensOffset + fluteOffset;

  // Prismatic dispersion
  let chDisp = chromaStr * (1.0 + treble * 0.5);
  let offR = baseOffset * 1.0;
  let offG = baseOffset * (1.0 + chDisp);
  let offB = baseOffset * (1.0 + chDisp * 2.1);

  let activeMask = (1.0 - clearMask) * (1.0 - isGrout);
  let uvR = clamp(mix(uv, bCenter + offR, activeMask), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(mix(uv, bCenter + offG, activeMask), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(mix(uv, bCenter + offB, activeMask), vec2<f32>(0.0), vec2<f32>(1.0));

  let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
  var color = vec3<f32>(r, g, b);

  // Fresnel highlight
  let cosTheta = 1.0 - lensMag * 4.0;
  let fresnel = schlick(max(cosTheta, 0.0), 0.04) * activeMask;
  color = mix(color, vec3<f32>(0.92, 0.96, 1.0), fresnel * 0.5);

  // Idea 1 — rib crest highlight: thin vertical glint on each flute's crest.
  let ribCrest = max(-cos(flutePhase), 0.0);
  let ribGlint = ribCrest * ribCrest * ribCrest * ribCrest;
  let ribHL = ribGlint * ribGlint * ribGlint * (0.07 + treble * 0.04) * activeMask;
  color += vec3<f32>(0.95, 0.98, 1.0) * ribHL;

  // Idea 2 — Grout-edge mirror bevel: in a thin band inside the grout the
  // moulded edge tilts steeply, so it shows the image mirrored across the
  // nearest brick edge (compressed, darkened) plus a thin specular line.
  let cellUV = 1.0 / vec2<f32>(brickCount * aspect, brickCount);
  let edgeX = min(brickUV.x, 1.0 - brickUV.x);
  let edgeY = min(brickUV.y, 1.0 - brickUV.y);
  let useX = edgeX < edgeY;
  let edgeDist = min(edgeX, edgeY);
  let outN = select(vec2<f32>(0.0, select(-1.0, 1.0, brickUV.y > 0.5)),
                    vec2<f32>(select(-1.0, 1.0, brickUV.x > 0.5), 0.0), useX);
  let bevelW = 0.08;
  let bevel = (1.0 - smoothstep(groutW, groutW + bevelW, edgeDist)) * (1.0 - isGrout) * (1.0 - clearMask);
  if (bevel > 0.001) {
    let edgeUVDist = edgeDist * dot(abs(outN), cellUV);
    let uvMirror = clamp(uv + outN * edgeUVDist * 2.6, vec2<f32>(0.0), vec2<f32>(1.0));
    let mirrored = textureSampleLevel(readTexture, u_sampler, uvMirror, 0.0).rgb * 0.55;
    color = mix(color, mirrored, bevel * 0.6);
    let specT = (edgeDist - (groutW + 0.014)) / 0.007;
    color += vec3<f32>(0.9, 0.95, 1.0) * exp(-specT * specT) * 0.35 * (1.0 - isGrout) * (1.0 - clearMask);
  }

  // Idea 3 — Per-brick batch tint: mixed-batch glass-block walls vary from
  // green to blue and in thickness. Deviations are centred on HEAD's glass.
  let batchH = hash21(brickId);
  let batchH2 = hash21(brickId + vec2<f32>(17.0, 41.0));
  let batchTint = vec3<f32>(-0.03, 0.02, 0.0) * (batchH - 0.5) * 2.0; // +1 green, -1 blue; mean 0
  let batchThick = 0.8 + batchH2 * 0.4;

  // Physical Beer-Lambert transmission
  let glassColor = clamp(vec3<f32>(0.88, 0.96, 1.0) + batchTint, vec3<f32>(0.0), vec3<f32>(1.0));
  let absorbed = exp(-(1.0 - glassColor) * thickness * batchThick * 3.0);
  color *= mix(vec3<f32>(1.0), absorbed, activeMask);

  // Grout line tint
  color = mix(color, color * 0.25, isGrout * (1.0 - clearMask));

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleDisp = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rAge = time - rp.z;
    if (rAge >= 0.0 && rAge < 2.5) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let rFront = min(rAge * 0.45, 1.5);
      let rRing = sin((rDist - rFront) * 30.0) * exp(-abs(rDist - rFront) * 12.0) * exp(-rAge * 1.5);
      rippleDisp += normalize(uv - rp.xy + vec2<f32>(0.0001)) * rRing * 0.01;
    }
  }

  if (dot(rippleDisp, rippleDisp) > 0.000001) {
    let rSample = clamp(uv + rippleDisp, vec2<f32>(0.0), vec2<f32>(1.0));
    color = mix(color, textureSampleLevel(readTexture, u_sampler, rSample, 0.0).rgb, 0.35);
  }

  // Exact dataTextureC persistence
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prev, 0.08);

  let finalRGB = aces(color);

  // Semantic alpha
  let luminance = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luminance * 0.7 + 0.3 + fresnel * 0.4 + activeMask * 0.25, 0.1, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
