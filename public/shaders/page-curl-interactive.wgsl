// ═══════════════════════════════════════════════════════════════════
//  Page Curl Interactive
//  Category: interactive-mouse
//  Features: upgraded-rgba, mouse-driven, audio-reactive, temporal
//  Complexity: Medium
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < octaves; i = i + 1) {
    let n = sin(dot(pp, vec2<f32>(127.1, 311.7)));
    let h = fract(n * 43758.5453);
    v = v + a * h;
    pp = pp * 2.03 + vec2<f32>(1.7, 9.2);
    a = a * 0.5;
  }
  return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / res;
  let time = u.config.x;

  let curlAngle = u.zoom_params.x * 1.5;
  let curlRadius = max(0.03, u.zoom_params.y * 0.25);
  let paperTexAmt = u.zoom_params.z;
  let shadowIntensity = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let snap = 1.0 + bass * 0.4 * step(0.6, bass);

  // Curl axis driven by mouse x
  let mouse = u.zoom_config.yz;
  let curlX = clamp(mouse.x, 0.1, 0.9);

  let dx = uv.x - curlX;
  let radius = curlRadius * snap;

  var col = vec4<f32>(0.0);
  var alpha = 1.0;

  if (dx < 0.0) {
    // Front page
    let shadow = smoothstep(radius, 0.0, -dx) * 0.5 * shadowIntensity;
    col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    col.rgb = col.rgb * (1.0 - shadow);
    alpha = col.a;
  } else if (dx < radius) {
    // Curl cylinder
    let theta = asin(clamp(dx / radius, -1.0, 1.0));
    let arcLen = radius * theta;
    let srcX = curlX + arcLen;
    if (srcX <= 1.0) {
      let srcUV = vec2<f32>(srcX, uv.y);
      // Back face is darker and has paper texture
      let paperNoise = fbm(srcUV * 40.0 + vec2<f32>(time * 0.01, 0.0), 3) * paperTexAmt;
      col = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0);
      col.rgb = col.rgb * 0.55 + vec3<f32>(paperNoise * 0.15);
      // Lighting on cylinder
      let normalZ = cos(theta);
      let highlight = pow(normalZ, 3.0) * 0.25;
      col.rgb = col.rgb + vec3<f32>(highlight);
      // Fold shadow reduces alpha at fold line
      let foldShadow = smoothstep(0.0, radius * 0.3, dx) * shadowIntensity;
      alpha = mix(0.5, col.a, 1.0 - foldShadow);
    } else {
      col = vec4<f32>(0.08, 0.08, 0.08, 0.6);
      alpha = 0.6;
    }
  } else {
    // Revealed background
    col = vec4<f32>(0.05, 0.05, 0.05, 0.4);
    alpha = 0.4;
  }

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col.rgb, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
