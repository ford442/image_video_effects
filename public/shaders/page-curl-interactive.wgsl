// ═══════════════════════════════════════════════════════════════════
//  Page Curl Interactive
//  Category: image
//  Features: upgraded-rgba, mouse-driven, audio-reactive, temporal, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-05-23
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
  let uv    = vec2<f32>(global_id.xy) / res;
  let coord = vec2<i32>(global_id.xy);
  let time  = u.config.x;

  // params: x=CurlRadius, y=ShadowStrength, z=FeedbackAmount, w=DepthInfluence
  let curlRadius      = max(0.03, u.zoom_params.x * 0.35);
  let shadowIntensity = u.zoom_params.y;
  let feedbackAmt     = u.zoom_params.z;
  let depthInfluence  = u.zoom_params.w;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Bass snaps the radius on strong beats
  let snap   = 1.0 + bass * 0.4 * step(0.6, bass);
  let mouse  = u.zoom_config.yz;
  let curlX  = clamp(mouse.x, 0.05, 0.95);
  let dx     = uv.x - curlX;
  let radius = curlRadius * snap;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // ── Click shockwaves (branchless) ────────────────────────────────
  var shockDisp = 0.0;
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp    = u.ripples[i];
    let rDist = length(uv - rp.xy);
    let rAge  = time - rp.z;
    let rRad  = rAge * 0.45;
    let rBand = abs(rDist - rRad);
    let active = select(0.0, 1.0, rBand < 0.04 && rAge >= 0.0 && rAge < 1.2);
    let decay  = clamp(1.0 - rAge / 1.2, 0.0, 1.0);
    shockDisp += active * decay * 0.025 * sin(rDist * 40.0 - rAge * 12.0);
  }

  // ── Zone 1: Front page (dx < 0) ──────────────────────────────────
  let frontSampUV = clamp(uv + vec2<f32>(shockDisp, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let frontColor  = textureSampleLevel(readTexture, u_sampler, frontSampUV, 0.0);
  // Depth-aware shadow: deeper foreground pixels cast stronger shadow toward fold
  let frontShadow = (1.0 - smoothstep(0.0, max(radius, 0.001), -dx)) * 0.5
                    * shadowIntensity * (1.0 + depth * depthInfluence);
  let frontRGB    = frontColor.rgb * (1.0 - frontShadow);
  let frontAlpha  = clamp(frontColor.a * (1.0 - frontShadow * 0.4), 0.0, 1.0);
  let frontResult = vec4<f32>(frontRGB, frontAlpha);

  // ── Zone 2: Curl cylinder (0 ≤ dx < radius) ──────────────────────
  let theta   = asin(clamp(dx / max(radius, 0.001), -1.0, 1.0));
  let srcX    = clamp(curlX + radius * theta, 0.0, 1.0);
  let srcUV   = vec2<f32>(srcX, uv.y);
  let paperNoise = fbm(srcUV * 40.0 + vec2<f32>(time * 0.01, 0.0), 3) * 0.15;
  // Chromatic split on the curl face — mids driven
  let chromaOff = mids * 0.01;
  let curlR = textureSampleLevel(readTexture, u_sampler,
    clamp(srcUV + vec2<f32>(chromaOff, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let curlG = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0).g;
  let curlB = textureSampleLevel(readTexture, u_sampler,
    clamp(srcUV - vec2<f32>(chromaOff, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let curlBack   = vec3<f32>(curlR, curlG, curlB) * 0.55 + vec3<f32>(paperNoise);
  let normalZ    = cos(theta);
  let highlight  = pow(normalZ, 3.0) * 0.25 * (1.0 + treble * 0.3);
  let foldShadow = smoothstep(0.0, radius * 0.3, dx) * shadowIntensity;
  let curlAlpha  = clamp(mix(0.5, 1.0, 1.0 - foldShadow), 0.0, 1.0);
  let curlResult = vec4<f32>(curlBack + vec3<f32>(highlight), curlAlpha);

  // ── Zone 3: Background (dx ≥ radius) ─────────────────────────────
  let bgResult = vec4<f32>(0.05, 0.05, 0.05, 0.4);

  // ── Blend zones (branchless) ─────────────────────────────────────
  let isFront = dx < 0.0;
  let isCurl  = dx >= 0.0 && dx < radius;
  var col = select(bgResult, curlResult, isCurl);
  col     = select(col, frontResult, isFront);

  // ── Temporal feedback from previous frame ─────────────────────────
  let prev    = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  // Less feedback on front page, more on curl/bg for trailing glow
  let fbBlend = feedbackAmt * 0.25 * (1.0 - select(0.0, 0.7, isFront));
  let finalCol = mix(col, prev, fbBlend);

  textureStore(writeTexture,      coord, vec4<f32>(finalCol.rgb, col.a));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, vec4<f32>(finalCol.rgb, col.a));
}
