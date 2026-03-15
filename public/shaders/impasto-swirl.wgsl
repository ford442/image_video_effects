// ═══════════════════════════════════════════════════════════════
//  Impasto Swirl - Physical Media Simulation with Alpha
//  Category: artistic
//  Features: paint thickness → alpha, brush stroke depth, drying
// ═══════════════════════════════════════════════════════════════

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

// Simple hash noise
fn hash12(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Canvas texture
fn canvasTexture(uv: vec2<f32>) -> f32 {
    let noise = fract(sin(dot(uv * 200.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    return 0.9 + 0.1 * noise;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  var mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let brushSize = u.zoom_params.x * 0.1 + 0.01;
  let smudgeStrength = u.zoom_params.y;
  let drySpeed = u.zoom_params.z * 0.1 + 0.001;
  let paintLoad = u.zoom_params.w; // Amount of paint on brush

  // Aspect correct distance
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // Determine if we are under the "brush"
  let brushMask = smoothstep(brushSize, brushSize * 0.5, dist);

  // Read current input and history
  let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let historyFrame = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Paint thickness tracking (stored in history alpha)
  let prev_thickness = historyFrame.a;

  // Initialize output
  var finalColor = currentFrame;
  var paint_thickness = prev_thickness;

  if (historyFrame.a == 0.0) {
      finalColor = currentFrame;
      paint_thickness = 0.5; // Initial thin wash
  } else {
      // Create swirl offset for brush effect
      let angle = time * 2.0;
      let offset = vec2<f32>(cos(angle), sin(angle)) * brushSize * 0.5;

      // If brush is active here
      if (brushMask > 0.0) {
         // Sample from rotated position to simulate brush dragging
         let rotUV = uv + vec2<f32>(dVec.y, -dVec.x) * smudgeStrength * 2.0;
         let mixedSample = textureSampleLevel(dataTextureC, u_sampler, rotUV, 0.0);

         // Mix current frame with smeared history
         finalColor = mix(currentFrame, mixedSample, smudgeStrength * brushMask);
         
         // Add paint thickness when brushing (impasto effect)
         let added_thickness = brushMask * paintLoad * 0.5;
         paint_thickness = min(1.0, paint_thickness + added_thickness);
      } else {
         // Outside brush, slowly fade back to current frame (paint drying/settling)
         finalColor = mix(historyFrame, currentFrame, drySpeed);
         
         // Paint settles and thins slightly as it dries
         paint_thickness = mix(paint_thickness, 0.7, drySpeed * 0.1);
      }
  }

  // Canvas texture overlay
  let canvas = canvasTexture(uv);
  finalColor = mix(finalColor, finalColor * (0.9 + 0.2 * canvas), 0.3);

  // IMPASTO PAINT ALPHA CALCULATION
  // Impasto technique creates thick, textured paint application
  
  // PAINT THICKNESS → ALPHA MAPPING
  // - Heavy impasto (thick): opaque, catches light (alpha 0.85-0.98)
  // - Medium application: semi-opaque (alpha 0.5-0.8)
  // - Thin glaze/wash: translucent (alpha 0.2-0.5)
  // - Canvas showing through: very low alpha
  
  // Base alpha from paint thickness
  var paint_alpha = mix(0.3, 0.95, paint_thickness * paint_thickness);
  
  // Wet paint is more translucent, dry paint more opaque
  // (drySpeed represents drying/settling over time)
  let wet_factor = 1.0 - drySpeed * 5.0; // Higher when freshly applied
  paint_alpha = mix(paint_alpha * 0.85, paint_alpha, wet_factor);
  
  // Canvas texture creates micro-variations in paint coverage
  // Paint pools in canvas valleys, is thinner on peaks
  let canvas_relief = canvas;
  let relief_alpha = mix(0.9, 1.0, canvas_relief);
  paint_alpha *= relief_alpha;
  
  // Brush stroke edges have thinner paint
  if (brushMask > 0.0 && brushMask < 0.8) {
      let edge_thinning = smoothstep(0.0, 0.8, brushMask);
      paint_alpha *= mix(0.6, 1.0, edge_thinning);
  }
  
  // Color modification based on thickness
  // Thicker paint = deeper, richer color (more pigment)
  // Thinner areas = lighter, more desaturated
  let thickness_saturation = mix(0.85, 1.15, paint_thickness);
  let thickness_value = mix(1.1, 0.9, paint_thickness);
  
  // Apply subtle color shift for thick paint
  let luminance = dot(finalColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let chroma = finalColor.rgb - vec3<f32>(luminance);
  finalColor.rgb = vec3<f32>(luminance) + chroma * thickness_saturation;
  finalColor.rgb *= thickness_value;
  
  // Specular highlight for wet thick paint
  let specular = pow(max(canvas * paint_thickness - 0.3, 0.0), 4.0) * 0.3 * wet_factor;
  finalColor.rgb += vec3<f32>(specular);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor.rgb, paint_alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor.rgb, paint_thickness));

  // Store paint thickness in depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(paint_thickness, 0.0, 0.0, paint_alpha));
}
