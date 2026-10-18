// ═══════════════════════════════════════════════════════════════════
//  Temporal Slit Paint
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-10-04 (prev 2026-08-30)
//  Ideas: revived velocity stretch from a C state texel; slit-scan stamping along the stroke; exposure frame-lines
//  A packing: raw canvas RGBA (linear paint / coverage) — display is ACES on writeTexture; texel (0,0) = cursor state (prevMouse.xy, vel.xy)
//  Motion: velocity-stretched brush + traveling slit-head runners
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadC(c: vec2<i32>, maxC: vec2<i32>) -> vec4<f32> {
  // Texel (0,0) holds cursor state, not paint; substitute its diagonal neighbour.
  let cc = clamp(c, vec2<i32>(0), maxC);
  let isState = cc.x == 0 && cc.y == 0;
  return textureLoad(dataTextureC, select(cc, vec2<i32>(1, 1), isState), 0);
}

fn brushMask(local: vec2<f32>, size: f32, shapeType: i32, softness: f32) -> f32 {
  var d = length(local);
  let box = length(max(abs(local) - vec2<f32>(size * 0.72), vec2<f32>(0.0)));
  let starA = atan2(local.y, local.x);
  let n = 5.0;
  let sector = TAU / n;
  let a = fract(starA / sector + 0.5) * sector - sector * 0.5;
  let star = cos(a) * length(local);
  let p = pow(pow(abs(local.x), 2.5) + pow(abs(local.y), 2.5), 0.4);
  d = mix(mix(d, p, select(0.0, 1.0, shapeType == 1)), mix(star, box, select(0.0, 1.0, shapeType == 3)), select(0.0, 1.0, shapeType >= 2));
  let inner = size * (1.0 - softness);
  return 1.0 - smoothstep(inner, size, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let maxC = vec2<i32>(i32(dims.x) - 1, i32(dims.y) - 1);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[1].y;
  let binB = plasmaBuffer[5].z;

  // Idea 1 — revived velocity stretch. HEAD's extraBuffer spring never persisted (the
  // scratch buffer is re-uploaded every frame), so springVel was always zero and the
  // stretch/orientation below was dead. Cursor state now lives in A texel (0,0):
  // (prevMouse.xy, smoothed per-frame velocity.xy), read back exactly from C.
  let isStateTexel = gid.x == 0u && gid.y == 0u;
  let stateC = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let mouseValid = all(mouse >= vec2<f32>(0.0)) && all(mouse <= vec2<f32>(1.0));
  let rawVel = select(vec2<f32>(0.0), clamp(mouse - stateC.xy, vec2<f32>(-0.08), vec2<f32>(0.08)), mouseValid);
  let frameVel = mix(clamp(stateC.zw, vec2<f32>(-0.08), vec2<f32>(0.08)), rawVel, 0.35);
  let spring = mouse;
  let springVel = frameVel * 60.0; // uv per second at 60 fps, the units HEAD's stretch expects

  let brushSize = mix(0.01, 0.2, u.zoom_params.x) * (1.0 + bass * 0.15);
  let shapeType = i32(clamp(u.zoom_params.y * 3.0 + 0.5, 0.0, 3.0));
  let softness = u.zoom_params.z;
  let diffusion = u.zoom_params.w;

  let speed = length(springVel);
  let velAng = atan2(springVel.y, springVel.x + 0.0001);
  let stretch = 1.0 + clamp(speed * 0.55, 0.0, 2.2);
  var local = (uv - spring) * vec2<f32>(aspect, 1.0);
  let ca = cos(-velAng);
  let sa = sin(-velAng);
  local = vec2<f32>(local.x * ca - local.y * sa, local.x * sa + local.y * ca);
  local.x = local.x / stretch;

  let mask = brushMask(local, brushSize, shapeType, softness);
  let slitHead = exp(-abs(local.y) * (18.0 + treble * 8.0)) * smoothstep(brushSize * 1.6, 0.0, abs(local.x));
  let runner = pow(max(0.0, sin(local.x * 28.0 - time * (7.0 + mids * 3.0)) * 0.5 + 0.5), 5.0) * slitHead;

  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 2.0;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    click = click + select(0.0, exp(-abs(rd - age * 0.5) * 14.0) * exp(-age * 1.4), alive);
  }

  let hist = loadC(coord, maxC);  // (0,0) reads (1,1): the state texel is never paint
  let n1 = loadC(coord + vec2<i32>(1, 0), maxC);
  let n2 = loadC(coord + vec2<i32>(-1, 0), maxC);
  let n3 = loadC(coord + vec2<i32>(0, 1), maxC);
  let n4 = loadC(coord + vec2<i32>(0, -1), maxC);
  let laplacian = (n1 + n2 + n3 + n4) * 0.25;
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Idea 2 — slit-scan stamping: while moving, a painted pixel takes the live frame from
  // the slit through the brush centre (keeping only its across-stroke coordinate), so the
  // drag direction becomes a time axis and the stroke smears a strip of video.
  let slitMix = smoothstep(0.15, 1.0, speed);
  let slitOffset = vec2<f32>(local.y * sa, local.y * ca); // R(+velAng) * (0, local.y); sa = sin(-velAng)
  let slitUV = clamp(spring + slitOffset / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let slitColor = textureSampleLevel(readTexture, u_sampler, slitUV, 0.0).rgb;
  // Idea 3 — exposure frame-lines: a brief darkening every quarter second marks equal time
  // intervals across a moving stroke, like frame lines on slit-scan film.
  let frameLine = mix(0.72, 1.0, smoothstep(0.0, 0.1, fract(time * 4.0)));
  let stampColor = mix(current.rgb, slitColor * mix(1.0, frameLine, slitMix), slitMix);

  let stamp = max(mask * select(0.15, 1.0, held), runner * 0.65 + click * 0.45);
  var canvas = mix(hist, vec4<f32>(stampColor, 1.0), clamp(stamp, 0.0, 1.0));
  canvas = mix(canvas, laplacian, diffusion * 0.12);
  canvas.a = clamp(mix(hist.a * 0.992, 1.0, stamp) + runner * 0.08, 0.0, 1.0);

  textureStore(dataTextureA, coord, select(canvas, vec4<f32>(select(stateC.xy, mouse, mouseValid), frameVel), isStateTexel));

  var hdr = mix(current.rgb, canvas.rgb, canvas.a);
  hdr = hdr + vec3<f32>(0.95, 0.55, 1.0) * runner * (0.25 + binA * 0.1);
  hdr = hdr + vec3<f32>(0.4, 0.9, 1.0) * click * 0.22;
  let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  hdr = luma + (hdr - vec3<f32>(luma)) * (1.15 + binB * 0.2);
  let rgb = acesToneMap(hdr * 1.06);
  let alpha = clamp(canvas.a * 0.7 + stamp * 0.35 + depth * 0.1, 0.08, 0.98);

  textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
