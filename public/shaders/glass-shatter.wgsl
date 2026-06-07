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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let mouse = u.zoom_config.yz;
  let audio = plasmaBuffer[0].xyz;

  let shardScale = u.zoom_params.x * 20.0 + 3.0;
  let displacement = u.zoom_params.y * 0.42;
  let edge = u.zoom_params.z;
  let aberration = u.zoom_params.w * 0.05 + audio.z * 0.015;
  let audioPulse = audio.x * 0.50 + audio.y * 0.30 + audio.z * 0.20;

  let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
  let v = voronoi(aspectUV, shardScale);
  let mouseVec = v.center - vec2<f32>(mouse.x * aspect, mouse.y);
  let mouseDist = length(mouseVec);
  let repelDir = select(vec2<f32>(0.0), mouseVec / max(mouseDist, 0.0001), mouseDist > 0.0001);
  let repelMask = 1.0 - smoothstep(0.0, 0.6, mouseDist);
  let offset = repelDir * repelMask * (displacement + audioPulse * 0.06);
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
  let edgeHighlight = pow(1.0 - cosTheta, 3.0) * (0.25 + edge * 0.75);

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
  let specular = pow(max(dot(lightDir, normal), 0.0), 20.0) * (0.20 + 0.40 * edge + 0.30 * audio.z);
  finalColor = finalColor + glassTint * edgeHighlight * 0.25 + vec3<f32>(specular);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(mix(baseDepth, 0.35 + 0.55 * (1.0 - transmission), 0.20 + 0.35 * edge), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, transmission));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(repelMask, fresnel, edgeHighlight, transmission));
}
