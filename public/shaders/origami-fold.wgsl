// ═══════════════════════════════════════════════════════════════════
//  Origami Fold
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, paper-fold, mountain-valley, chromatic-edge, semantic-alpha
//  Complexity: Very High
//  Created: 2024-01-01
//  Updated: 2026-06-01
//  By: Kimi Agent (4-Agent Swarm Upgrade)
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

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn paperTexture(uv: vec2<f32>) -> f32 {
  let fiber = sin(uv.x * 200.0 + hash12(uv * 3.0) * 0.5) * 0.5 + 0.5;
  let grain = hash12(uv * 47.0) * 0.08;
  return 0.92 + fiber * 0.06 - grain;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn kawasakiAngle(angles: vec4<f32>) -> f32 {
  let alt1 = angles.x + angles.y;
  let alt2 = angles.z + angles.w;
  return select(alt2, alt1, alt1 < alt2);
}

fn timePhase(t: f32) -> f32 {
  return t;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;
  let clickCount = u.config.y;
  let isMouseDown = u.zoom_config.w > 0.5;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthShadow = mix(0.55, 1.15, depth);

  let foldSpeed = u.zoom_params.x * (0.5 + bass * 0.5);
  let shadowStrength = u.zoom_params.y * depthShadow;
  let baseAngle = u.zoom_params.z;
  let paperOpacity = u.zoom_params.w;

  let mountainValley = fract(clickCount * 0.5) > 0.25;
  let animPhase = baseAngle + bass * 0.4;
  let foldDir = vec2<f32>(cos(animPhase), sin(animPhase));

  let toPoint = uv - mousePos;
  let dist = dot(toPoint, foldDir);

  let creaseAngles = vec4<f32>(
    abs(atan2(toPoint.y, toPoint.x)),
    abs(atan2(toPoint.y + 0.01, toPoint.x)),
    abs(atan2(toPoint.y, toPoint.x + 0.01)),
    abs(atan2(toPoint.y - 0.01, toPoint.x - 0.01))
  );
  let kAngle = kawasakiAngle(creaseAngles);
  let dihedral = smoothstep(0.0, 1.57, kAngle) * foldSpeed;

  let isFolded = select(dist > 0.0, dist < 0.0, mountainValley);
  var finalColor = vec3<f32>(0.0);
  var foldAlpha = 0.0;

  if (!isFolded) {
    let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    finalColor = texColor.rgb;
    foldAlpha = texColor.a;
  } else {
    let reflectDir = toPoint - 2.0 * dist * foldDir;
    let sourceUV = clamp(mousePos + reflectDir, vec2<f32>(0.0), vec2<f32>(1.0));
    let texColor = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);

    let shadow = 1.0 - smoothstep(0.0, 0.12 + foldSpeed * 0.1, abs(dist)) * shadowStrength;
    let paper = paperTexture(uv * 3.0 + vec2<f32>(animPhase * 0.1));
    let darkened = texColor.rgb * 0.88 * paper * shadow;

    let edge = smoothstep(0.0, 0.06, abs(dist));
    let chroma = treble * 0.025 * edge * (1.0 + bass * 0.5);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(sourceUV + vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(sourceUV - vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    let specAngle = abs(dist) * 20.0;
    let specular = pow(smoothstep(0.92, 1.0, sin(specAngle + bass * 3.0)), 12.0) * (0.3 + mids * 0.4);

    finalColor = vec3<f32>(r, darkened.g, b);
    finalColor += vec3<f32>(specular) * vec3<f32>(0.95, 0.92, 0.85);
    foldAlpha = texColor.a * paperOpacity;

    let creaseGlow = bass * 0.12 * smoothstep(0.06, 0.0, abs(dist)) * select(1.0, 2.0, isMouseDown);
    finalColor += vec3<f32>(creaseGlow, creaseGlow * 0.55, creaseGlow * 0.15);
  }

  let layerOrder = smoothstep(0.0, 0.08, abs(dist)) * (0.6 + depth * 0.4);
  let edgeDarken = smoothstep(0.0, 0.04, abs(dist)) * 0.15 * treble;
  finalColor = mix(finalColor, finalColor * 0.7, edgeDarken);

  finalColor = acesToneMap(finalColor * (1.0 + bass * 0.15));

  let semantic_alpha = clamp(abs(dihedral) * foldAlpha * (0.5 + depth * 0.5), 0.2, 0.98);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, semantic_alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, semantic_alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * layerOrder, 0.0, 0.0, 0.0));
}
