// ═══════════════════════════════════════════════════════════════════
//  Sketch Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-04
//  Ideas: tonal-art-map hatch layers (single → cross → diagonal); persistent watercolour wash from C; dried-edge pigment rim
//  A packing: raw fields (edge, wash, sketchBase, alpha) — C.g is read back as the wash
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

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn sampleLuma(uv: vec2<f32>) -> f32 {
  return luminance(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let f = fract(p * vec2<f32>(123.34, 456.21));
  return fract(dot(f, vec2<f32>(1.0, 1.0)) * 78.233);
}

// One pencil line family: thin graphite strokes of period 1 along `x`.
fn hatchLine(x: f32, width: f32) -> f32 {
  return 1.0 - smoothstep(width, width + 0.12, abs(fract(x) - 0.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;
  let bass = audio.x;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let brushSize = mix(0.05, 0.55, u.zoom_params.x);
  let edgeStrength = mix(0.8, 3.0, u.zoom_params.y);
  let sketchContrast = mix(1.0, 3.5, u.zoom_params.z);
  let brushSoftness = mix(0.02, 0.30, u.zoom_params.w);

  let px = vec2<f32>(1.0 / dims.x, 1.0 / dims.y);
  let c = sampleLuma(uv);

  // Image gradients for hatching direction
  let edgeX = sampleLuma(uv + vec2<f32>(px.x, 0.0)) - sampleLuma(uv - vec2<f32>(px.x, 0.0));
  let edgeY = sampleLuma(uv + vec2<f32>(0.0, px.y)) - sampleLuma(uv - vec2<f32>(0.0, px.y));
  let edge = clamp(length(vec2<f32>(edgeX, edgeY)) * edgeStrength * 4.0, 0.0, 1.0);
  let gradAngle = atan2(edgeY, edgeX + 0.0001);

  // Depth controls stroke size perspective
  let depthStrokeScale = mix(1.0, 0.4, depth);

  // Cross-hatching density based on luminance
  let hatchDir1 = dot(uv, vec2<f32>(cos(gradAngle), sin(gradAngle))) * 220.0 * depthStrokeScale;
  let hatchDir2 = dot(uv, vec2<f32>(-sin(gradAngle), cos(gradAngle))) * 180.0 * depthStrokeScale;
  let hatch1 = 0.5 + 0.5 * sin(hatchDir1 + time * 0.5 + bass * 3.0);
  let hatch2 = 0.5 + 0.5 * sin(hatchDir2 + time * 0.7 + bass * 2.5);
  let hatchDensity = mix(hatch1, hatch2, c) * (1.0 - c * 0.6);
  // Idea 1: tonal art map. Darkness unlocks stroke layers one at a time,
  // as an illustrator builds tone: lines along the gradient, then a cross
  // layer, then a 45° diagonal layer in the deepest shadows.
  let darkness = clamp(pow(1.0 - c, mix(1.0, 1.6, u.zoom_params.z)), 0.0, 1.0);
  let tamFreq = 34.0 * depthStrokeScale;
  let diagDir = vec2<f32>(cos(gradAngle + 0.785398), sin(gradAngle + 0.785398));
  let jitter = (hash21(floor(uv * 64.0)) - 0.5) * 0.25;
  let layer1 = hatchLine(hatchDir1 / 6.2832 + jitter, 0.06) * smoothstep(0.22, 0.30, darkness);
  let layer2 = hatchLine(hatchDir2 / 6.2832 - jitter, 0.05) * smoothstep(0.48, 0.56, darkness);
  let layer3 = hatchLine(dot(uv * vec2<f32>(aspect, 1.0), diagDir) * tamFreq + jitter, 0.045) * smoothstep(0.72, 0.80, darkness);
  let tam = max(max(layer1, layer2 * 0.9), layer3 * 0.85);

  // Paper tooth texture
  let paperNoise = hash21(uv * 512.0) * 0.06;
  let paperTooth = 1.0 - paperNoise;

  // Pencil/charcoal sketch
  let sketchBase = clamp(pow(1.0 - c, sketchContrast) + edge * 0.7 + hatchDensity * 0.15, 0.0, 1.0);
  let graphiteSheen = 0.92 + 0.08 * sin(gradAngle * 3.0 + time);
  let pencilTint = vec3<f32>(0.78, 0.76, 0.72) * graphiteSheen;
  let charcoalTint = vec3<f32>(0.35, 0.38, 0.42);
  var sketchColor = mix(charcoalTint, pencilTint, sketchBase) * paperTooth;

  // Chromatic edge darkening
  let edgeDarken = vec3<f32>(0.95, 0.92, 0.88) * (1.0 - edge * 0.25);
  sketchColor = sketchColor * edgeDarken;
  sketchColor = sketchColor * (1.0 - tam * 0.38 * (0.8 + bass * 0.2));

  // Mouse reveal (pencil adds strokes)
  let brushDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let reveal = 1.0 - smoothstep(brushSize, brushSize + brushSoftness, brushDist);
  let revealProgress = reveal * (1.0 + bass * 0.4);
  // Idea 2: the brush leaves a watercolour wash. C.g is last frame's wash
  // (A has always stored the reveal in .g); it dries slowly, longer for a
  // softer, wetter brush.
  let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
  let dryRate = mix(0.990, 0.997, u.zoom_params.w);
  let wash = clamp(max(revealProgress, prev.g * dryRate), 0.0, 1.25);

  // Smudge effect near brush
  let smudgeOffset = vec2<f32>(cos(time * 2.0), sin(time * 2.0)) * brushSoftness * 0.5 * reveal;
  let smudgeColor = textureSampleLevel(readTexture, u_sampler, clamp(uv + smudgeOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  // Away from the live brush the wash is thinner pigment on toothy paper.
  let washPigment = mix(sourceColor, vec3<f32>(0.96, 0.94, 0.89), 0.18) * (1.0 - paperNoise * 1.5);
  let liveColor = mix(washPigment, mix(smudgeColor, sourceColor, 0.7), clamp(revealProgress, 0.0, 1.0));
  // Idea 3: dried edge. Pigment migrates to the drying front of a wash and
  // leaves a darker rim where the wash thins out.
  let rim = smoothstep(0.08, 0.28, wash) * (1.0 - smoothstep(0.30, 0.62, wash)) * (1.0 - reveal);
  let pooled = liveColor * mix(vec3<f32>(1.0), liveColor * 0.85 + vec3<f32>(0.05), rim * 0.75);
  var finalColor = mix(sketchColor, pooled, clamp(wash, 0.0, 1.0));
  finalColor = finalColor + vec3<f32>(1.0, 0.85, 0.65) * edge * (1.0 - reveal) * 0.12;

  // ACES tone mapping
  finalColor = acesToneMap(finalColor * 1.1);

  // Semantic alpha: reveal_progress * stroke_density * depth
  let strokeDensity = sketchBase * edge * 2.0 + hatchDensity * 0.3 + tam * 0.25;
  let finalAlpha = clamp(wash * strokeDensity * depth * 3.0, 0.12, 0.92);
  let depthOut = clamp(mix(depth, 0.20 + edge * 0.75, 0.24), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(edge, wash, sketchBase, finalAlpha));
}
