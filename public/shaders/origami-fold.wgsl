// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;

  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;

  // Params
  let radius = u.zoom_params.x;        // Not strictly used for curl yet, maybe for shadow width?
  let shadowStrength = u.zoom_params.y;
  let angle = u.zoom_params.z;
  let transparency = u.zoom_params.w;

  // Define Fold Line
  let foldDir = vec2<f32>(cos(angle), sin(angle));

  // Distance from pixel to the fold line
  // P = mousePos
  // Line defined by P and Normal (foldDir)
  // Signed distance
  let dist = dot(uv - mousePos, foldDir);

  var finalColor = vec4<f32>(0.0);

  // If dist > 0, we are on the side of the paper that got folded "up/away".
  // So there is nothing here (transparent/background).

  if (dist > 0.0) {
    // Empty space
    finalColor = vec4<f32>(0.0);
  } else {
    // We are on the base surface.
    // 1. Sample the base image.
    finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // 2. Check if the flap covers this pixel.
    // Reflect the current pixel across the line to find where it maps to on the "lifted" part.
    // Formula: R = P - 2 * dot(P-LineP, N) * N
    // Here dist is negative, so we subtract 2 * dist * N (which adds, moving towards the line and past it).

    let sourceUV = uv - 2.0 * dist * foldDir;

    // Check if sourceUV is valid (inside 0-1) AND it came from the folded region (dist > 0 relative to line)
    // By geometric definition, if we reflected, it must have come from the other side.
    // Just check image bounds.

    if (sourceUV.x >= 0.0 && sourceUV.x <= 1.0 && sourceUV.y >= 0.0 && sourceUV.y <= 1.0) {

       // Calculate shadow
       // Shadow is stronger near the crease (dist close to 0).
       let shadow = 1.0 - smoothstep(0.0, 0.1 + radius, abs(dist)) * shadowStrength;

       // Sample the "back" of the paper (the image at sourceUV).
       // Note: Since it's a reflection, the image will appear mirrored on the flap, which is physically correct.
       var flapColor = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);

       // Darken flap slightly to distinguish back side
       flapColor = vec4<f32>(flapColor.rgb * 0.9, flapColor.a);

       // Apply shadow to the base BEFORE mixing? Or shadow is cast by flap?
       // Let's apply shadow to the mix boundary.

       // Mix based on transparency (if paper is opaque, transparency = 0, so we see flap fully).
       // Param transparency: 0.0 = Opaque, 1.0 = Invisible Flap.

       finalColor = mix(flapColor, finalColor, transparency);

       // Apply Crease Shadow
       finalColor = vec4<f32>(finalColor.rgb * shadow, finalColor.a);
    }
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

  // Pass through depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
