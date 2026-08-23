// ================================================================
//  Glass Shatter
//  Category: distortion
//  Features: mouse-driven, chromatic-aberration, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: glass-shatter
//  Created: 2026-05-30
//  By: Copilot
// ================================================================

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=ShardSize, y=Displacement, z=Edge, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

struct VoronoiResult {
  dist: f32,
  id: vec2<f32>,
  center: vec2<f32>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn voronoi(uv: vec2<f32>, scale: f32) -> VoronoiResult {
  let g = floor(uv * scale);
  let f = fract(uv * scale);
  var res = VoronoiResult(8.0, vec2<f32>(0.0), vec2<f32>(0.0));

  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let lattice = vec2<f32>(f32(x), f32(y));
      let offset = hash22(g + lattice);
      let p = lattice + offset - f;
      let d = dot(p, p);
      if (d < res.dist) {
        res.dist = d;
        res.id = g + lattice;
        res.center = (g + lattice + offset) / scale;
      }
    }
  }

  res.dist = sqrt(res.dist);
  return res;
}

fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let dt = 0.016;
  if (global_id.x == 0u && global_id.y == 0u) {
    let target = select(0.0, 1.0, u.zoom_config.w > 0.5);
    var pos = extraBuffer[133];
    var vel = extraBuffer[134];
    
    let tension = 150.0;
    let damping = 12.0;
    let force = tension * (target - pos) - damping * vel;
    vel += force * dt;
    pos += vel * dt;
    pos = clamp(pos, -0.5, 1.5);
    
    extraBuffer[133] = pos;
    extraBuffer[134] = vel;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let audioPulse = bass * 0.50 + mid * 0.30 + treble * 0.20;

  let time = u.config.x;
  let heldState = extraBuffer[133];

  let shardScale = u.zoom_params.x * 20.0 + 3.0;
  let displacement = u.zoom_params.y * 0.42;
  let edge = u.zoom_params.z;
  let aberration = u.zoom_params.w * 0.05 + treble * 0.015;

  let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
  let v = voronoi(aspectUV, shardScale);
  let mouseVec = v.center - vec2<f32>(mouse.x * aspect, mouse.y);
  let mouseDist = length(mouseVec);
  let repelDir = select(vec2<f32>(0.0), mouseVec / max(mouseDist, 0.0001), mouseDist > 0.0001);
  let repelMask = (1.0 - smoothstep(0.0, 0.6, mouseDist)) * mix(0.18, 1.0, heldState);

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var rippleIndex: u32 = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
    let ripple = u.ripples[rippleIndex];
    let rippleAge = max(time - ripple.z, 0.0);
    if (rippleAge < 3.0) {
      let front = abs(distance(uv, ripple.xy) - rippleAge * (0.24 + bass * 0.12));
      clickFront += exp(-front * 125.0) * exp(-rippleAge * 1.7);
    }
  }
  clickFront = min(clickFront, 2.0);

  let shardPhase = dot(hash22(v.id), vec2<f32>(5.3, 8.7)) * 6.2831853;
  let shardRunner = pow(max(0.0, sin(shardPhase + length(v.center - vec2<f32>(0.5)) * 34.0 - time * (12.0 + mid * 7.0))), 12.0);
  let edgeRunner = pow(max(0.0, sin(v.dist * 72.0 + shardPhase - time * (17.0 + treble * 8.0))), 18.0);
  let offset = repelDir * (repelMask * (displacement + audioPulse * 0.06) + clickFront * 0.055);
  let randBase = hash22(v.id) - 0.5;
  let randOffset = randBase * (0.005 + max(displacement, 0.08) * 0.025);
  let finalUV = clamp(uv - offset - randOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  let tiltVec = offset + randOffset;
  let tiltLen = length(tiltVec);
  let shardTilt = select(vec2<f32>(0.0, 0.0), tiltVec / max(tiltLen, 0.0001), tiltLen > 0.0001);
  let sampleDir = select(vec2<f32>(1.0, 0.0), shardTilt, tiltLen > 0.0001);
  let normal = normalize(vec3<f32>(shardTilt * (1.5 + audioPulse), 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let cosTheta = max(dot(viewDir, normal), 0.0);
  let fresnel = 0.04 + (1.0 - 0.04) * pow(1.0 - cosTheta, 5.0);
  let edgeHighlight = pow(1.0 - cosTheta, 3.0) * (0.25 + edge * 0.75) + edgeRunner * (0.08 + treble * 0.28);

  let thickness = 0.04 + (1.0 - clamp(v.dist, 0.0, 1.0)) * 0.08 + edge * 0.04;
  let density = 0.70 + edge * 1.50;
  let glassTint = mix(vec3<f32>(0.90, 0.97, 1.00), vec3<f32>(1.0, 0.82, 0.55), audioPulse * 0.35);
  let absorption = exp(-(1.0 - glassTint) * thickness * density);
  let transmission = clamp((1.0 - fresnel) * dot(absorption, vec3<f32>(0.33333334)), 0.08, 0.98);

  let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + sampleDir * aberration, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - sampleDir * aberration, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var finalColor = vec3<f32>(r, g, b) * absorption;

  let lightDir = normalize(vec3<f32>(-0.4, 0.5, 0.8));
  let specular = pow(max(dot(lightDir, normal), 0.0), 20.0) * (0.20 + 0.40 * edge + 0.30 * treble);
  finalColor = finalColor + glassTint * edgeHighlight * 0.25 + vec3<f32>(specular);
  finalColor += vec3<f32>(0.58, 0.82, 1.0) * shardRunner * (0.04 + mid * 0.18) +
                vec3<f32>(1.0, 0.72, 0.35) * clickFront * 0.16;
                
  let prevColor = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
  finalColor = mix(finalColor, prevColor, 0.15 * heldState);

  finalColor = aces_tonemap(finalColor);
  let alpha = clamp(transmission + (shardRunner + clickFront) * 0.5 + dot(finalColor, vec3<f32>(0.333)), 0.0, 1.0);
  let finalRGBA = vec4<f32>(finalColor, alpha);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.35 + 0.55 * (1.0 - transmission), 0.20 + 0.35 * edge), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalRGBA);
  textureStore(dataTextureA, vec2<i32>(global_id.xy), finalRGBA);
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
