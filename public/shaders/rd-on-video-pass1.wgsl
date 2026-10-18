// ═══════════════════════════════════════════════════════════════════
//  RD on Video (Pass 1: State Update)
//  Category: simulation
//  Features: multi-pass-1, temporal, video-driven, audio-reactive, mouse-driven, upgraded-rgba
//  Upgraded: 2026-10-17
//  Ideas: contour stretch along the video-luma tangent; spot-fission pinch on flat-topped V
//  A packing: raw (U, V, source-luma memory, reaction activity). B is never written.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
fn stateAt(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> { return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0); }
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1);
  let res = vec2<f32>(size); let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0); let time = u.config.x;
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let lum = luma(src.rgb); let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  var s = stateAt(p, hi);
  if (time < 0.12 || s.r + s.g < 0.001) { s = vec4<f32>(1.0, smoothstep(0.72, 0.35, abs(lum - 0.5)) * 0.42, lum, 0.0); }
  let lap = stateAt(p + vec2<i32>(-1, 0), hi) + stateAt(p + vec2<i32>(1, 0), hi)
          + stateAt(p + vec2<i32>(0, -1), hi) + stateAt(p + vec2<i32>(0, 1), hi) - 4.0 * s;
  let feed = mix(0.018, 0.064, u.zoom_params.x) + lum * 0.006 + audio.y * 0.003;
  let kill = mix(0.042, 0.071, u.zoom_params.y) + (1.0 - lum) * 0.004 + audio.x * 0.004;
  let diffusion = mix(0.45, 1.05, u.zoom_params.z); let dt = mix(0.30, 1.0, u.zoom_params.w);
  let reaction = s.r * s.g * s.g; var next = s;
  next.r += (diffusion * lap.r - reaction + feed * (1.0 - s.r)) * dt;
  next.g += (diffusion * 0.42 * lap.g + reaction - (feed + kill) * s.g) * dt;
  // Idea 1: contour stretch. V diffuses along the tangent of the stored luma
  // so spots elongate with the video's edges. gy large → tangent is horizontal.
  let lumaL = stateAt(p + vec2<i32>(-1, 0), hi).b;
  let lumaR = stateAt(p + vec2<i32>(1, 0), hi).b;
  let lumaD = stateAt(p + vec2<i32>(0, -1), hi).b;
  let lumaU = stateAt(p + vec2<i32>(0, 1), hi).b;
  let gLuma = vec2<f32>(lumaR - lumaL, lumaU - lumaD);
  let tx = abs(gLuma.y);
  let ty = abs(gLuma.x);
  let alongV = ((stateAt(p + vec2<i32>(-1, 0), hi).g + stateAt(p + vec2<i32>(1, 0), hi).g) * tx
              + (stateAt(p + vec2<i32>(0, -1), hi).g + stateAt(p + vec2<i32>(0, 1), hi).g) * ty)
              / (tx + ty + 0.001);
  let contour = (alongV - s.g) * smoothstep(0.02, 0.18, length(gLuma));
  next.g += contour * diffusion * 0.55 * dt;
  // Idea 2: spot fission. A flat-topped high-V spot (small laplacian) gets a
  // central kill so the plateau pinches and divides. Peaked spots (large |lap|) stay.
  let plateau = smoothstep(0.28, 0.55, s.g) * (1.0 - smoothstep(0.02, 0.14, abs(lap.g)));
  next.g -= plateau * 0.16 * dt;
  next.r += plateau * 0.06 * dt;
  next.b = mix(s.b, lum, 0.08 + audio.z * 0.04);
  let md = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0));
  let hover = exp(-md * 20.0); let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  next.g += hover * (0.006 + held * (0.32 + audio.x * 0.14));
  var fronts = 0.0; let count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < count; i = i + 1u) {
    let e = u.ripples[i]; let age = time - e.z;
    if (age >= 0.0 && age < 1.5) {
      let d = length((uv - e.xy) * vec2<f32>(aspect, 1.0));
      fronts += exp(-age * 2.2) * exp(-abs(d - age * 0.30) * 74.0);
    }
  }
  next.g += fronts * 0.25; next = clamp(next, vec4<f32>(0.0), vec4<f32>(1.0));
  next.a = clamp(abs(next.g - s.g) * 8.0 + fronts + abs(lum - s.b) * 2.0, 0.0, 1.0);
  textureStore(dataTextureA, p, next);
  let pattern = clamp(next.g * 1.8 + abs(lap.g) * 4.0, 0.0, 1.0);
  let chemistry = vec3<f32>(0.04, 0.35, 1.6) * next.r + vec3<f32>(2.1, 0.22, 0.04) * next.g + vec3<f32>(0.25, 1.2, 0.4) * next.a;
  let hdr = mix(src.rgb, chemistry, 0.30 + pattern * 0.65);
  let alpha = clamp(src.a * (0.45 + 0.35 * (1.0 - pattern)) + pattern * 0.55 + fronts * 0.25, 0.0, 1.0);
  let mapped = aces(max(hdr, vec3<f32>(0.0))); let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha));
  textureStore(writeDepthTexture, p, vec4<f32>(clamp(mix(depth, 1.0 - pattern * 0.72, alpha * 0.48), 0.0, 1.0), 0.0, 0.0, 0.0));
}
