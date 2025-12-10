// Quantum Fractal Entanglement Shader
// Adapted for Immutable Renderer Infrastructure

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Scale, y=Iterations, z=Entanglement, w=Unused
  ripples: array<vec4<f32>, 50>,
};

struct WaveFunction {
  real: f32,
  imaginary: f32
}

fn complexMul(a: WaveFunction, b: WaveFunction) -> WaveFunction {
  return WaveFunction(
    a.real * b.real - a.imaginary * b.imaginary,
    a.real * b.imaginary + a.imaginary * b.real
  );
}

fn complexAdd(a: WaveFunction, b: WaveFunction) -> WaveFunction {
  return WaveFunction(a.real + b.real, a.imaginary + b.imaginary);
}

fn waveFunctionMagnitude(wf: WaveFunction) -> f32 {
  return sqrt(wf.real * wf.real + wf.imaginary * wf.imaginary);
}

fn quantumFractal(z_in: vec2<f32>, c: vec2<f32>, maxIter: u32, time: f32) -> WaveFunction {
  var psi = WaveFunction(z_in.x, z_in.y);
  var potential = WaveFunction(0.0, 0.0);
  
  for (var i = 0u; i < maxIter; i = i + 1u) {
    // Schrödinger evolution step
    let z_squared = WaveFunction(
      psi.real * psi.real - psi.imaginary * psi.imaginary,
      2.0 * psi.real * psi.imaginary
    );
    
    // Quantum tunneling effect
    let tunnel = WaveFunction(
      sin(time * 0.5 + f32(i) * 0.1),
      cos(time * 0.3 + f32(i) * 0.07)
    );
    
    psi = complexAdd(z_squared, WaveFunction(c.x, c.y));
    psi = complexMul(psi, tunnel);
    
    // Probability collapse visualization
    potential.real = potential.real + psi.real / (f32(i) + 1.0);
    potential.imaginary = potential.imaginary + psi.imaginary / (f32(i) + 1.0);
    
    // Escape condition with quantum uncertainty
    if (waveFunctionMagnitude(psi) > 4.0 + sin(time * 0.1) * 0.5) {
      break;
    }
  }
  
  return potential;
}

fn colormap(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  let b = vec3<f32>(0.5, 0.5, 0.5);
  let c = vec3<f32>(1.0, 1.0, 1.0);
  let d = vec3<f32>(0.26, 0.42, 0.65);
  
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  
  // Parameters
  let scale = u.zoom_params.x; // Default ~3.0
  let iterParam = u.zoom_params.y; // Default ~100
  let entanglementStrength = u.zoom_params.z; // Default ~1.0
  
  let maxIter = u32(max(10.0, iterParam));

  // Animate fractal center
  let center = vec2<f32>(
    sin(time * 0.23) * 0.3,
    cos(time * 0.31) * 0.3
  );
  
  // Create multiple entangled fractal points
  let c1 = vec2<f32>(
    -0.7269 + sin(time * 0.1) * 0.05,
    0.1889 + cos(time * 0.15) * 0.05
  );
  
  let c2 = vec2<f32>(
    0.285 + cos(time * 0.07) * 0.03,
    0.01 + sin(time * 0.09) * 0.03
  );
  
  // Coordinate transformation with cosmic rotation
  let rot = time * 0.1;
  let rotatedUV = vec2<f32>(
    (uv.x - 0.5) * cos(rot) - (uv.y - 0.5) * sin(rot) + 0.5,
    (uv.x - 0.5) * sin(rot) + (uv.y - 0.5) * cos(rot) + 0.5
  );
  
  let z = (rotatedUV - vec2<f32>(0.5, 0.5)) * vec2<f32>(aspect, 1.0) * scale + center;
  
  // Calculate primary quantum fractal
  let psi1 = quantumFractal(z, c1, maxIter, time);
  let mag1 = waveFunctionMagnitude(psi1);
  
  // Secondary entangled fractal with phase shift
  let phaseShift = vec2<f32>(sin(time * 0.5), cos(time * 0.5)) * 0.1;
  let psi2 = quantumFractal(z + phaseShift, c2, u32(f32(maxIter) * 0.8), time);
  let mag2 = waveFunctionMagnitude(psi2);
  
  // Quantum entanglement visualization
  let entanglement = sin(mag1 * 10.0 + time) * cos(mag2 * 8.0 + time * 1.3) * entanglementStrength;
  
  // Probability interference pattern
  let probability = abs(mag1 - mag2) * (1.0 + entanglement);
  
  // Chromatic aberration through probability space
  let r = sin(probability * 3.0 + time) * 0.5 + 0.5;
  let g = sin(probability * 3.0 + time + 2.094) * 0.5 + 0.5;  // 2π/3
  let b = sin(probability * 3.0 + time + 4.188) * 0.5 + 0.5;  // 4π/3
  
  // Add temporal evolution
  let evolution = sin(time * 2.0 + probability * 10.0) * 0.1;
  
  // Sample previous frame for feedback (Simulated with source image + noise since no feedback)
  // We use the source image as a "base reality" that gets entangled
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  
  // Quantum decoherence effect
  let decoherence = 0.05 * sin(time * 0.7 + uv.x * 10.0) * cos(time * 0.9 + uv.y * 10.0);
  
  // Final color with quantum effects
  var color = vec3<f32>(
    r * (1.0 + evolution),
    g * (1.0 - evolution),
    b * (1.0 + evolution * 0.5)
  );
  
  // Add entanglement glow
  color = color + vec3<f32>(0.2, 0.1, 0.3) * entanglement;
  
  // Apply colormap based on probability
  color = mix(color, colormap(probability * 0.5), 0.3);
  
  // Mix with source image (instead of feedback) to ground it
  color = mix(color, src, 0.2);
  
  // Output with HDR for glow effects
  color = color * (1.5 + sin(time * 0.5) * 0.2);
  
  // Add infinite regression effect (Simulated by sampling source at different scale)
  let regressUV = fract(uv * exp(sin(time * 0.1) * 0.5) + time * 0.01);
  let regress = textureSampleLevel(readTexture, u_sampler, regressUV, 0.0).rgb * 0.1;
  color = color + regress;
  
  // Update depth for next frame (required)
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(probability, 0.0, 0.0, 0.0));
  
  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
