// ASCII / Glyph Morphing - compute skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // glyph atlas
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

const GLYPH_GRID: vec2<u32> = vec2<u32>(80u, 45u);
const GLYPH_SIZE: u32 = 16u;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = vec2<f32>(u.config.z, u.config.w);
  let uv = vec2<f32>(gid.xy) / resolution;
  let time = u.config.x;
  
  // Mouse-based displacement
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let to_mouse = uv - mouse_pos;
  let dist_to_mouse = length(to_mouse);
  let mouse_displace = (1.0 - smoothstep(0.0, 0.3, dist_to_mouse)) * 8.0;
  
  // Ripple-based morphing
  var ripple_morph = 0.0;
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 4.0) {
        let to_ripple = uv - ripple.xy;
        let ripple_dist = length(to_ripple);
        ripple_morph += sin(ripple_dist * 30.0 - ripple_age * 8.0) * exp(-ripple_age) * 0.5;
      }
    }
  }
  
  let cell_coord = vec2<u32>(gid.xy);
  let pixel_in_cell = vec2<u32>(vec2<u32>(gid.x % GLYPH_SIZE, gid.y % GLYPH_SIZE));
  let cell_center = vec2<f32>(f32(cell_coord.x) * f32(GLYPH_SIZE), f32(cell_coord.y) * f32(GLYPH_SIZE));
  let src = textureLoad(readTexture, vec2<i32>(i32(cell_center.x), i32(cell_center.y)), 0);
  let saturation = max(src.r, max(src.g, src.b)) - min(src.r, min(src.g, src.b));
  let glyph_index = u32((saturation + ripple_morph * 0.5) * 255.0) % 16u;
  let atlas_uv = (vec2<f32>(f32(pixel_in_cell.x), f32(pixel_in_cell.y)) + vec2<f32>(f32(glyph_index * GLYPH_SIZE), 0.0)) / vec2<f32>(256.0, 16.0);
  let sdf = textureSampleLevel(dataTextureC, u_sampler, atlas_uv, 0.0).r;
  let morph_amount = saturation * 2.0 + mouse_displace * 0.1;
  let morphed_sdf = sdf + sin(f32(pixel_in_cell.x) * 0.5) * morph_amount;
  let hue = atan2(src.g - src.b, src.r - src.g);
  let glyph_color = vec3<f32>(abs(hue), 1.0, 1.0);
  let final_color = mix(vec3<f32>(0.0), glyph_color, smoothstep(0.0, 0.1, morphed_sdf));
  textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(final_color, 1.0));
}
