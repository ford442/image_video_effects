// ═══════════════════════════════════════════════════════════════════
//  Cyber Glitch Hologram v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Chunks From: cyber-glitch-hologram, structure-tensor
//  Upgraded: 2026-05-30
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
  return fract(sin(dot(p, vec2<f32>(41.0, 289.0))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(41.0, 289.0)));
  return fract(vec2<f32>(n, n * 1.618) * 43758.5453);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn structure_tensor(uv: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
  let e = vec2<f32>(1.0) / res;
  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-e.x, 0.0), 0.0).r;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(e.x, 0.0), 0.0).r;
  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, e.y), 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -e.y), 0.0).r;
  return vec2<f32>(r - l, t - b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let aspect = resolution.x / resolution.y;
  let holoIntensity = u.zoom_params.x;
  let glitchAmount = u.zoom_params.y;
  let scanSpeed = u.zoom_params.z;
  let blockScale = mix(16.0, 96.0, u.zoom_params.w);
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let mouseDist = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
  let mouseInfluence = smoothstep(0.35, 0.0, mouseDist) * holoIntensity;
  let deadZone = smoothstep(0.12, 0.0, mouseDist) * 0.7;

  let blockUV = floor(uv * blockScale) / blockScale;
  let blockHash = hash12(blockUV * 13.37 + floor(time * 3.0));
  let swapTrigger = step(0.88 - bass * 0.22, blockHash);
  let swapDir = hash22(blockUV * 7.91 + floor(time * 2.0)) - 0.5;
  let swapOffset = swapDir * swapTrigger * glitchAmount * 0.07;

  let motion = structure_tensor(uv, resolution);
  let datamosh = motion * glitchAmount * 0.04 * (0.5 + bass * 0.5);
  let baseUV = clamp(uv + swapOffset + datamosh, vec2<f32>(0.001), vec2<f32>(0.999));

  let parallax = depth * 0.025 * vec2<f32>(sin(time * 1.4), cos(time * 1.1));
  let layer1 = clamp(baseUV + parallax, vec2<f32>(0.001), vec2<f32>(0.999));
  let layer2 = clamp(baseUV - parallax * 0.5, vec2<f32>(0.001), vec2<f32>(0.999));

  let chroma = vec2<f32>(0.005 + treble * 0.012, 0.0) * mouseInfluence;
  let uvR1 = clamp(layer1 + chroma * 1.5, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB1 = clamp(layer1 - chroma * 1.2, vec2<f32>(0.001), vec2<f32>(0.999));
  let col1 = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR1, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, layer1, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB1, 0.0).b
  );

  let uvR2 = clamp(layer2 + chroma * 0.8, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB2 = clamp(layer2 - chroma * 0.6, vec2<f32>(0.001), vec2<f32>(0.999));
  let col2 = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR2, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, layer2, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB2, 0.0).b
  );

  let baseColor = mix(col1, col2, depth * 0.5 + 0.25);

  let fringeFreq = 180.0 + mids * 60.0;
  let fringe = cos((uv.x + uv.y * 0.7) * fringeFreq + time * 4.0) * 0.5 + 0.5;
  let hologram = vec3<f32>(0.0, 0.85, 1.0) * fringe * mouseInfluence * 0.25 +
                 vec3<f32>(1.0, 0.0, 0.75) * (1.0 - fringe) * mouseInfluence * 0.18;

  let scanline = sin((uv.y + time * scanSpeed * (1.0 + treble * 0.4)) * resolution.y * 0.22) * 0.5 + 0.5;
  let banding = step(0.35, scanline) * 0.12 * mouseInfluence;

  let glitchCorruption = swapTrigger * glitchAmount * 0.45 + deadZone * 0.25;
  let noise = hash12(uv * 200.0 + time * 50.0);
  let deadZoneMask = deadZone * noise * 0.3;

  var hdr = baseColor * (0.8 + mouseInfluence * 0.3) + hologram + banding;
  hdr = hdr * (1.0 - deadZoneMask) + vec3<f32>(0.05, 0.12, 0.15) * deadZoneMask;
  let tonemapped = aces_tonemap(hdr);

  let confidence = mouseInfluence * (1.0 - deadZone * 0.6);
  let alpha = clamp(confidence * (1.0 - glitchCorruption) * 0.85 + banding * 0.3 + bass * 0.04, 0.06, 0.92);
  let outDepth = clamp(depth + mouseInfluence * 0.06, 0.0, 1.0);
  let finalPixel = vec4<f32>(tonemapped, alpha);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(confidence, glitchCorruption, fringe, alpha));
}
