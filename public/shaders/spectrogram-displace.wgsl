// Audio-Visual Spectrogram Displacement - compute skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // audio texture
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

const SPECTRUM_BANDS: u32 = 128u;
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let dim = textureDimensions(readTexture);
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let time = u.config.x;
  
  let freq = f32(coord.y) / f32(dim.y) * f32(SPECTRUM_BANDS);
  let band = u32(freq) % SPECTRUM_BANDS;
  var magnitude = textureLoad(dataTextureC, vec2<i32>(i32(band), 0), 0).r;
  
  // Mouse to focus bands near the pointer
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouse_freq = mouse_pos.y * f32(SPECTRUM_BANDS);
  let band_dist = abs(f32(band) - mouse_freq);
  if (band_dist < 20.0) {
    magnitude *= 1.0 + (1.0 - band_dist / 20.0) * 2.0;
  }
  
  // Ripples create local audio-reactive smears
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 3.0) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.15) {
          magnitude *= 1.0 + (1.0 - ripple_age / 3.0) * 1.5;
        }
      }
    }
  }
  
  let src = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  var displaced_x = i32(coord.x) - i32(magnitude * src.r * 10.0);
  var displaced_xb = i32(coord.x) + i32(magnitude * src.b * 10.0);
  displaced_x = (displaced_x + i32(dim.x)) % i32(dim.x);
  displaced_xb = (displaced_xb + i32(dim.x)) % i32(dim.x);
  let disp = textureLoad(readTexture, vec2<i32>(displaced_x, i32(coord.y)), 0);
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), disp);
}
