// Magnetic Dipole Field - Particle Alignment Visualization
// Simulates magnetic field lines with dipole physics

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // field data
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // alignment data
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read previous
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=ChargeStrength, y=AlignmentInertia, z=SpriteSize, w=FieldDensity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MU0: f32 = 1.0; // Magnetic permeability (simplified)

// Dipole field at point p from dipole at origin with moment m
fn dipoleField(p: vec2<f32>, m: vec2<f32>) -> vec2<f32> {
  let r = length(p);
  if (r < 0.01) { return vec2<f32>(0.0); }
  
  let r3 = r * r * r;
  let r5 = r3 * r * r;
  
  // Simplified 2D dipole field
  let mDotP = dot(m, p);
  let B = (3.0 * p * mDotP / (r5 + 0.001) - m / (r3 + 0.001)) * MU0 / (4.0 * PI);
  
  return B;
}

// Hash function
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 1.0)));
}

// Render iron filing sprite
fn ironFilingSprite(localUV: vec2<f32>, angle: f32, intensity: f32) -> f32 {
  // Rotate local coordinates
  let c = cos(angle);
  let s = sin(angle);
  let rotUV = vec2<f32>(
    localUV.x * c - localUV.y * s,
    localUV.x * s + localUV.y * c
  );
  
  // Elongated ellipse
  let ellipse = rotUV.x * rotUV.x * 16.0 + rotUV.y * rotUV.y * 64.0;
  let shape = smoothstep(1.0, 0.5, ellipse);
  
  return shape * intensity;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  
  // Parameters
  let chargeStrength = mix(0.1, 2.0, u.zoom_params.x);
  let alignmentInertia = mix(0.0, 0.95, u.zoom_params.y);
  let spriteSize = mix(0.01, 0.05, u.zoom_params.z);
  let fieldDensity = mix(10.0, 50.0, u.zoom_params.w);
  
  // Aspect ratio correction
  let aspect = u.config.z / u.config.w;
  
  // Mouse as primary dipole
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseMoment = vec2<f32>(0.0, chargeStrength * 0.1);
  
  // Compute total magnetic field at this point
  var totalField = vec2<f32>(0.0);
  
  // Field from mouse dipole
  let toMouse = uv - mouse;
  let mouseField = dipoleField(toMouse, mouseMoment);
  totalField = totalField + mouseField;
  
  // Add ripples as temporary dipoles
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 3.0) {
        let toRipple = uv - ripple.xy;
        let rippleStrength = (1.0 - rippleAge / 3.0) * chargeStrength;
        // Alternate polarity based on ripple index
        let polarity = select(-1.0, 1.0, i % 2 == 0);
        let rippleMoment = vec2<f32>(cos(rippleAge * 2.0), sin(rippleAge * 2.0)) * rippleStrength * polarity * 0.05;
        let rippleField = dipoleField(toRipple, rippleMoment);
        totalField = totalField + rippleField;
      }
    }
  }
  
  // Add some fixed dipoles based on source image features
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Depth-based field contribution
  let depthGradX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r - depth;
  let depthGradY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r - depth;
  totalField = totalField + vec2<f32>(depthGradX, depthGradY) * chargeStrength * 0.1;
  
  let fieldStrength = length(totalField);
  let fieldDirection = normalize(totalField + vec2<f32>(0.0001));
  let fieldAngle = atan2(fieldDirection.y, fieldDirection.x);
  
  // Store field data
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(fieldDirection, fieldStrength, fieldAngle));
  
  // Read previous alignment for inertia
  let prevState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var alignment = prevState.b;
  
  // Align to field with inertia
  let targetAlignment = fieldAngle;
  alignment = mix(targetAlignment, alignment, alignmentInertia);
  
  // Store alignment
  textureStore(dataTextureB, vec2<i32>(coord), vec4<f32>(alignment, fieldStrength, 0.0, 0.0));
  
  // Render iron filings grid
  var filingAccum = 0.0;
  
  // Grid of iron filings
  let gridSize = 1.0 / fieldDensity;
  let gridCoord = floor(uv / gridSize);
  
  // Check nearby grid cells
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let cellCoord = gridCoord + vec2<f32>(f32(dx), f32(dy));
      
      // Random offset within cell
      let cellHash = hash22(cellCoord * 123.456);
      let filingCenter = (cellCoord + cellHash * 0.8 + 0.1) * gridSize;
      
      // Distance to this filing
      let toFiling = uv - filingCenter;
      let filingDist = length(toFiling);
      
      if (filingDist < spriteSize * 2.0) {
        // Get field at filing position
        let filingField = textureSampleLevel(dataTextureC, non_filtering_sampler, filingCenter, 0.0);
        let filingAngle = filingField.r;
        let filingIntensity = clamp(filingField.g * 2.0, 0.3, 1.0);
        
        // Render sprite
        let localUV = toFiling / spriteSize;
        filingAccum = filingAccum + ironFilingSprite(localUV, filingAngle, filingIntensity);
      }
    }
  }
  
  filingAccum = clamp(filingAccum, 0.0, 1.0);
  
  // Field line visualization
  let fieldLinePhase = fract(dot(uv, fieldDirection) * 20.0 + time * 0.5);
  let fieldLine = smoothstep(0.4, 0.5, fieldLinePhase) * smoothstep(0.6, 0.5, fieldLinePhase);
  let fieldLineIntensity = fieldLine * fieldStrength * 0.5;
  
  // Compose final image
  var finalColor = sourceColor.rgb;
  
  // Tint based on field polarity
  let polarityColor = vec3<f32>(
    0.5 + fieldDirection.x * 0.5,
    0.5,
    0.5 - fieldDirection.x * 0.5
  );
  
  // Add iron filings
  let filingColor = vec3<f32>(0.2, 0.2, 0.25); // Dark iron color
  finalColor = mix(finalColor, filingColor, filingAccum * 0.8);
  
  // Add field lines
  let lineColor = mix(vec3<f32>(0.8, 0.3, 0.2), vec3<f32>(0.2, 0.3, 0.8), fieldDirection.y * 0.5 + 0.5);
  finalColor = finalColor + lineColor * fieldLineIntensity;
  
  // Add glow around strong field regions
  let fieldGlow = exp(-1.0 / (fieldStrength + 0.1)) * 0.3;
  finalColor = finalColor + polarityColor * fieldGlow;
  
  // Clamp
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
