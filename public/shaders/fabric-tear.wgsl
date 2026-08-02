// Fabric of Reality — strain + tear mask
// dataTextureB: .r strain, .g tear (0/1), .b weave phase, .a debris age
// zoom_params.y = tearThreshold, .w = selfHeal (reconnect when > ~0.35)

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const REST_LENGTH: f32 = 1.0;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let tearThreshold = mix(1.5, 4.0, u.zoom_params.y);
  let selfHeal = u.zoom_params.w;
  let treble = plasmaBuffer[0].z;

  let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let pos = state.xy;

  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let restLen = texelSize.x * REST_LENGTH;

  let leftUV = uv + vec2<f32>(-texelSize.x, 0.0);
  let upUV = uv + vec2<f32>(0.0, -texelSize.y);
  let leftPos = textureSampleLevel(dataTextureC, non_filtering_sampler, leftUV, 0.0).xy;
  let upPos = textureSampleLevel(dataTextureC, non_filtering_sampler, upUV, 0.0).xy;

  var totalStrain = 0.0;
  var isTorn = false;
  if (coord.x > 0u) {
    let d = length(pos - leftPos);
    totalStrain = totalStrain + abs(d - restLen) / max(restLen, 1e-5);
    if (d >= tearThreshold * restLen) { isTorn = true; }
  }
  if (coord.y > 0u) {
    let d = length(pos - upPos);
    totalStrain = totalStrain + abs(d - restLen) / max(restLen, 1e-5);
    if (d >= tearThreshold * restLen) { isTorn = true; }
  }
  totalStrain = clamp(totalStrain * 2.0, 0.0, 1.0);

  // Prior tear mask (host copies previous frame B→C? — tear writes B fresh each frame;
  // use strain persistence via soft heal fade when selfHeal is active)
  var tearMask = select(0.0, 1.0, isTorn);

  // Self heal: gradually clear tears when springs are near rest length again
  if (selfHeal > 0.35) {
    let healRate = mix(0.88, 0.55, clamp((selfHeal - 0.35) / 0.65, 0.0, 1.0));
    if (totalStrain < 0.35) {
      tearMask = tearMask * healRate;
    } else if (selfHeal > 0.7 && totalStrain < 0.6) {
      tearMask = tearMask * mix(1.0, healRate, 0.5);
    }
  }

  // Treble sparkle on fresh tears
  let weavePhase = fract(uv.x * 12.0 + uv.y * 8.0 + time * 0.2 + treble * 0.1);
  let debrisAge = tearMask * time;

  textureStore(dataTextureB, vec2<i32>(coord),
    vec4<f32>(totalStrain, tearMask, weavePhase, debrisAge));
}
