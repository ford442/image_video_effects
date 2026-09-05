// ═══════════════════════════════════════════════════════════════════
//  Kinetic Tiles
//  Category: geometric
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: kinetic traveling wave cascade + rotating bevel tile shear
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GridDensity, y=MouseRadius, z=RotationAmt, w=TileScale
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotateVec(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[2].z;
  let binB = plasmaBuffer[6].y;

  // Single-writer spring-damper cursor in extraBuffer[133..138]
  var spring = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 14.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-4.0), vec2<f32>(4.0));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
  }

  // Four saved controls preserved
  let gridDensity = mix(8.0, 72.0, u.zoom_params.x) * (1.0 + bass * 0.25);
  let mouseRadius = mix(0.08, 0.85, u.zoom_params.y) * select(1.0, 1.35, held);
  let rotationAmt = (u.zoom_params.z * 3.14159265 * 2.0) * (1.0 + treble * 0.45);
  let tileScale = mix(0.45, 1.0, u.zoom_params.w);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.6, 1.4, depth);

  // Capped click ripple wavefronts
  var rippleFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let d = length((uv - r.xy) * aspectVec);
      let front = exp(-abs(d - age * 0.42) * 28.0) * exp(-age * 1.5);
      rippleFront += front;
    }
  }

  // Aspect-corrected square cell lattice
  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let cellIndex = floor(uvAspect * gridDensity);
  let cellUV = fract(uvAspect * gridDensity);
  let cellCenterAspect = (cellIndex + 0.5) / gridDensity;
  let cellCenter = vec2<f32>(cellCenterAspect.x / aspect, cellCenterAspect.y);

  // Proximity to smoothed spring pointer
  let toCenter = (cellCenter - spring) * aspectVec;
  let distCenter = length(toCenter);

  // Kinetic cascade wave
  let cascadePhase = distCenter * 16.0 - time * (3.5 + bass * 3.0) + sin(cellIndex.x * 0.5 + cellIndex.y * 0.3);
  let waveMotion = sin(cascadePhase) * 0.5 + 0.5;

  var pct = 0.0;
  if (distCenter < mouseRadius) {
    pct = 1.0 - smoothstep(0.0, mouseRadius, distCenter);
  }
  let totalImpulse = clamp(pct + rippleFront * 0.85 + waveMotion * 0.18 * (mids + 0.2), 0.0, 2.5);

  let currentAngle = totalImpulse * rotationAmt;
  let effectiveScale = clamp(tileScale * (1.0 - totalImpulse * 0.25 * (1.0 - tileScale)), 0.3, 1.0);

  // Rotate and scale cell coordinate
  let centeredUV = cellUV - 0.5;
  let rotatedUV = rotateVec(centeredUV, currentAngle);
  let scaledUV = rotatedUV / effectiveScale;
  let inTileUV = scaledUV + 0.5;

  // Bevel edge metric
  let edgeDist = min(min(inTileUV.x, 1.0 - inTileUV.x), min(inTileUV.y, 1.0 - inTileUV.y));
  let bevel = smoothstep(0.0, 0.08, edgeDist);
  let borderGlint = smoothstep(0.08, 0.01, edgeDist) * (0.3 + treble * 0.7 + binA * 0.4);

  var color = vec3<f32>(0.0);
  var validTile = false;

  if (inTileUV.x >= 0.0 && inTileUV.x <= 1.0 && inTileUV.y >= 0.0 && inTileUV.y <= 1.0) {
    validTile = true;
    let cellWidth = vec2<f32>(1.0 / (gridDensity * aspect), 1.0 / gridDensity);
    let sampleUV = clamp(cellCenter + (inTileUV - 0.5) * cellWidth, vec2<f32>(0.0), vec2<f32>(1.0));
    
    // Chromatic aberration at high tile velocity
    let chromaShift = (currentAngle * 0.006 + rippleFront * 0.008) * (1.0 + binB);
    let rCol = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let gCol = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let bCol = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    
    color = vec3<f32>(rCol, gCol, bCol) * (0.75 + 0.25 * bevel);
    
    // Metallic specular glint based on angle
    let glintAngle = abs(sin(currentAngle * 2.0 + time * 2.0));
    color += vec3<f32>(1.0, 0.9, 0.7) * pow(glintAngle, 8.0) * borderGlint * 1.5;
  } else {
    // Gap underneath tiles - show underlying raw texture darkened with shadow
    let underCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    color = underCol * 0.15;
  }

  // Load exact temporal history from dataTextureC
  let hist = textureLoad(dataTextureC, coord, 0);
  let trailMix = mix(0.08, 0.35, clamp(totalImpulse * 0.5, 0.0, 1.0));
  var hdr = mix(color, hist.rgb, trailMix);

  // Kinetic border glow palette
  let glowPalette = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + totalImpulse * 2.5 + time * 0.6);
  hdr += glowPalette * borderGlint * 0.6 + glowPalette * rippleFront * 0.4;

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp(select(0.25, 0.96, validTile) + totalImpulse * 0.2 + borderGlint * 0.3, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, select(0.1, 0.85, validTile) * depthFactor, 0.35), 0.0, 1.0), 0.0, 0.0, 0.0));
}
