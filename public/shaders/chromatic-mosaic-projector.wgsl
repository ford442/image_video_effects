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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p * vec2<f32>(0.1031, 0.1030);
  let a = dot(pp, vec2<f32>(127.1, 311.7));
  let b = dot(pp + 1.0, vec2<f32>(269.5, 183.3));
  let c = sin(vec2<f32>(a, b));
  return fract(c * 43758.5453 + pp);
}

fn hash12(p: vec2<f32>) -> f32 {
  let a = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(a) * 43758.5453);
}

fn voronoi(uv: vec2<f32>, cellSize: f32, distort: f32, time: f32) -> vec3<f32> {
  let scaled = uv * cellSize;
  let cellId = floor(scaled);
  let fracPos = fract(scaled);

  var minDist = 1.0;
  var nearCell = cellId;

  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = cellId + vec2<f32>(f32(x), f32(y));
      let h = hash22(neighbor);
      let anim = vec2<f32>(
        sin(time * 0.8 + h.x * 6.28) * distort,
        cos(time * 0.6 + h.y * 6.28) * distort
      );
      let point = h + anim + vec2<f32>(f32(x), f32(y)) - fracPos;
      let d = length(point);
      if (d < minDist) {
        minDist = d;
        nearCell = neighbor;
      }
    }
  }
  return vec3<f32>(minDist, nearCell.x, nearCell.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;

  // Parameters
  let cellSizeBase = mix(8.0, 80.0, u.zoom_params.x);
  let cellSize = cellSizeBase * (1.0 + bass * 0.2);
  let chromaticStrength = u.zoom_params.y * 0.06;
  let voronoiDistort = u.zoom_params.z * 0.4;
  let projectionAngle = (u.zoom_params.w - 0.5) * 1.0;

  let voro = voronoi(uv, cellSize, voronoiDistort, time);
  let cellHash = hash12(vec2<f32>(voro.y, voro.z));
  let cellCenter = (vec2<f32>(voro.y, voro.z) + 0.5) / cellSize;

  // Mouse gravity well
  let mouse = u.zoom_config.yz;
  let toMouse = (mouse - uv) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(toMouse);
  let gravity = 0.2;
  let warp = select(vec2<f32>(0.0), normalize(toMouse) * gravity / (1.0 + mouseDist * 3.0), mouseDist > 0.0001);
  let warpedUV = uv + warp * 0.02;

  // Direction from cell center with projection angle bias
  let dirVec = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dirVec);
  var dir = select(vec2<f32>(1.0, 0.0), normalize(dirVec), dist > 0.0001);
  let angleRot = projectionAngle + cellHash * 0.5;
  let ca = cos(angleRot);
  let sa = sin(angleRot);
  dir = vec2<f32>(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);

  // Per-cell chromatic shift based on cell hash
  let cellChroma = chromaticStrength * (0.5 + cellHash);
  let baseOffset = dir * dist * 0.08;
  let rOff = baseOffset + dir * cellChroma * (1.0 + bass * 0.5);
  let gOff = baseOffset + dir * cellChroma * 0.3;
  let bOff = baseOffset - dir * cellChroma * 0.7;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + gOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r, g, b);

  // Cell boundary transition smoothness
  let edgeFade = smoothstep(0.0, 0.15, voro.x);
  color = color * (0.7 + 0.3 * edgeFade);

  // Light falloff
  let falloff = 1.0 / (1.0 + dist * 2.0);
  color = color * falloff;

  // Audio brightness boost
  color = color * (1.0 + bass * 0.2);

  // Source alpha preserved, smooth boundary transitions
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let alpha = mix(src.a * 0.7, src.a, edgeFade);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
