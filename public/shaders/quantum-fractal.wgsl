// ═══════════════════════════════════════════════════════════════════
//  Quantum Fractal
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-16
//  Ideas: phase fringes of the first wavefunction; photo pulled by the second phase
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

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

fn quantumFractal(z_in: vec2<f32>, c: vec2<f32>, maxIter: u32, time: f32, zoom_params_w: f32) -> WaveFunction {
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
      sin(time * 0.5 * zoom_params_w + f32(i) * 0.1),
      cos(time * 0.3 * zoom_params_w + f32(i) * 0.07)
    );
    
    psi = complexAdd(z_squared, WaveFunction(c.x, c.y));
    psi = complexMul(psi, tunnel);
    
    // Probability collapse visualization
    potential.real = potential.real + psi.real / (f32(i) + 1.0);
    potential.imaginary = potential.imaginary + psi.imaginary / (f32(i) + 1.0);
    
    // Escape condition with quantum uncertainty
    if (waveFunctionMagnitude(psi) > 4.0 + sin(time * 0.1 * zoom_params_w) * 0.5) {
      break;
    }
  }
  
  return potential;
}

fn colormap(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  var b = vec3<f32>(0.5, 0.5, 0.5);
  let c = vec3<f32>(1.0, 1.0, 1.0);
  let d = vec3<f32>(0.26, 0.42, 0.65);
  
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let scale = u.zoom_params.x; // Default ~3.0
  let iterParam = u.zoom_params.y; // Default ~100
  let entanglementStrength = u.zoom_params.z; // Default ~1.0
  let zoom_params_w = u.zoom_params.w; // Edge glow / animation speed
  
  let maxIter = u32(max(10.0, iterParam));

  // Animate fractal center
  var center = vec2<f32>(
    sin(time * 0.23 * u.zoom_params.w) * 0.3,
    cos(time * 0.31 * u.zoom_params.w) * 0.3
  );
  let pointer = (clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0)) - vec2<f32>(0.5)) * 0.45;
  center = center + pointer;
  
  // Create multiple entangled fractal points
  let c1 = vec2<f32>(
    -0.7269 + sin(time * 0.1 * zoom_params_w) * 0.05,
    0.1889 + cos(time * 0.15 * zoom_params_w) * 0.05
  );
  
  let c2 = vec2<f32>(
    0.285 + cos(time * 0.07 * zoom_params_w) * 0.03,
    0.01 + sin(time * 0.09 * zoom_params_w) * 0.03
  );
  
  // Coordinate transformation with cosmic rotation
  let rot = time * 0.1 * zoom_params_w;
  let rotatedUV = vec2<f32>(
    (uv.x - 0.5) * cos(rot) - (uv.y - 0.5) * sin(rot) + 0.5,
    (uv.x - 0.5) * sin(rot) + (uv.y - 0.5) * cos(rot) + 0.5
  );
  
  let z = (rotatedUV - vec2<f32>(0.5, 0.5)) * vec2<f32>(aspect, 1.0) * scale + center;
  
  // Calculate primary quantum fractal
  let psi1 = quantumFractal(z, c1, maxIter, time, zoom_params_w);
  let mag1 = waveFunctionMagnitude(psi1);
  
  // Secondary entangled fractal with phase shift
  let phaseShift = vec2<f32>(sin(time * 0.5 * zoom_params_w), cos(time * 0.5 * zoom_params_w)) * 0.1;
  let psi2 = quantumFractal(z + phaseShift, c2, u32(f32(maxIter) * 0.8), time, u.zoom_params.w);
  let mag2 = waveFunctionMagnitude(psi2);
  
  // Quantum entanglement visualization
  let entanglement = sin(mag1 * 10.0 + time) * cos(mag2 * 8.0 + time * 1.3 * zoom_params_w) * entanglementStrength;
  
  // Probability interference pattern
  let probability = abs(mag1 - mag2) * (1.0 + entanglement);
  
  // Chromatic aberration through probability space
  let r = sin(probability * 3.0 + time) * 0.5 + 0.5;
  let g = sin(probability * 3.0 + time + 2.094) * 0.5 + 0.5;  // 2π/3
  var b = sin(probability * 3.0 + time + 4.188) * 0.5 + 0.5;  // 4π/3
  
  // Add temporal evolution
  let evolution = sin(time * 2.0 * zoom_params_w + probability * 10.0) * 0.1;
  
  // Idea 2 — the photo is sampled along the second wavefunction's phase.
  let phase2 = atan2(psi2.imaginary, psi2.real);
  let pull = vec2<f32>(cos(phase2), sin(phase2)) * entanglementStrength * 0.02 * (1.0 + mids * 0.25);
  let src = textureSampleLevel(readTexture, u_sampler, clamp(uv + pull, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  
  // Quantum decoherence effect, folded into the phase fringe below.
  let decoherence = 0.05 * sin(time * 0.7 * zoom_params_w + uv.x * 10.0) * cos(time * 0.9 * zoom_params_w + uv.y * 10.0);
  
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
  
  // Idea 1 — phase fringes from the argument of the first wavefunction.
  let phase1 = atan2(psi1.imaginary, psi1.real);
  let fringe = 0.5 + 0.5 * cos(phase1 * 8.0);
  let fringeMix = clamp(fringe * (0.28 + treble * 0.12 + decoherence), 0.0, 1.0);
  color = mix(color, color * vec3<f32>(0.72, 0.88, 1.2), fringeMix);

  // Mix with source image (instead of feedback) to ground it
  color = mix(color, src, 0.2 + bass * 0.04);
  
  // Output with HDR for glow effects
  color = color * (1.5 + sin(time * 0.5 * zoom_params_w) * 0.2);
  
  // Add infinite regression effect (Simulated by sampling source at different scale)
  let regressUV = fract(uv * exp(sin(time * 0.1 * zoom_params_w) * 0.5) + time * 0.01 * zoom_params_w);
  let regress = textureSampleLevel(readTexture, u_sampler, regressUV, 0.0).rgb * 0.1;
  color = color + regress;
  
  let alpha = clamp(0.35 + fringe * 0.25 + clamp(probability, 0.0, 1.0) * 0.3 + entanglementStrength * 0.1, 0.0, 1.0);
  let display = aces(max(color, vec3<f32>(0.0)));
  let pixel = vec2<i32>(global_id.xy);
  textureStore(writeTexture, pixel, vec4<f32>(display, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(display, alpha));

  let sceneDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let relief = clamp(probability * 0.12, 0.0, 1.0);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(mix(sceneDepth, relief, 0.35), 0.0, 0.0, 0.0));
}
