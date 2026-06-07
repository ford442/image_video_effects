// DMT Fractal Zoom - Infinite zoom through Mandelbrot-family fractal landscape
// DMT-vision-like complexity with heavy post-processing glow

// ═══════════════════════════════════════════════════════════════════
//  DMT Fractal Zoom
//  Category: generative
//  Features: dmt, fractal, zoom, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: High
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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

const PI: f32 = 3.14159265;

// Ultra-saturated DMT rainbow
fn dmtRainbow(t: f32, shift: f32) -> vec3<f32> {
  let p = abs(fract(t * 2.0 + shift + vec3<f32>(0.0, 0.333, 0.667)) * 6.0 - vec3<f32>(3.0));
  return pow(clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.5)) * 3.0;
}

// Smooth fractal iteration coloring
fn fractalColor(iter: f32, maxIter: f32, zMag: f32, time: f32, colorShift: f32) -> vec3<f32> {
  let smoothIter = iter + 1.0 - log2(log2(max(zMag, 0.0001)));
  let norm = smoothIter / maxIter;
  
  // Layer multiple color waves for DMT complexity
  let c1 = dmtRainbow(norm * 4.0 + time * 0.1, colorShift);
  let c2 = dmtRainbow(norm * 7.0 - time * 0.15, colorShift + 0.3);
  let c3 = dmtRainbow(norm * 11.0 + time * 0.05, colorShift + 0.7);
  
  // Mix based on iteration bands
  let band = fract(norm * 8.0);
  let mix1 = smoothstep(0.0, 0.3, band) * smoothstep(0.6, 0.3, band);
  let mix2 = smoothstep(0.3, 0.5, band) * smoothstep(0.8, 0.5, band);
  
  var col = c1 * 1.5;
  col += c2 * mix1 * 0.8;
  col += c3 * mix2 * 0.6;
  
  return col;
}

// Burning Ship / Mandelbrot hybrid
fn fractalIter(c: vec2<f32>, maxIter: i32, time: f32) -> vec2<f32> {
  var z = vec2<f32>(0.0);
  var iter: f32 = 0.0;
  let hybridMix = sin(time * 0.2) * 0.5 + 0.5;
  
  for (var i: i32 = 0; i < 64; i = i + 1) {
    if (i >= maxIter) { break; }
    
    // Burning Ship variation with periodic hybrid
    let zx = abs(z.x);
    let zy = abs(z.y);
    
    // Mix between Mandelbrot and Burning Ship
    let mx = mix(z.x, zx, hybridMix);
    let my = mix(z.y, zy, 0.7);
    
    z = vec2<f32>(mx * mx - my * my + c.x, 2.0 * mx * my + c.y);
    
    let mag = dot(z, z);
    if (mag > 256.0) {
      iter = f32(i);
      return vec2<f32>(iter, mag);
    }
  }
  
  return vec2<f32>(f32(maxIter), dot(z, z));
}

// Secondary fractal layer - orbit traps coloring
fn orbitTrap(c: vec2<f32>, maxIter: i32, time: f32) -> vec3<f32> {
  var z = vec2<f32>(0.0);
  var minDist: f32 = 1000.0;
  
  let trapPoint = vec2<f32>(sin(time * 0.3) * 0.5, cos(time * 0.4) * 0.3);
  
  for (var i: i32 = 0; i < 40; i = i + 1) {
    if (i >= maxIter) { break; }
    
    let zx = abs(z.x);
    let zy = abs(z.y);
    z = vec2<f32>(zx * zx - zy * zy + c.x, 2.0 * zx * zy + c.y);
    
    let dist = length(z - trapPoint);
    minDist = min(minDist, dist);
    
    if (dot(z, z) > 256.0) { break; }
  }
  
  let trapVal = 1.0 / (1.0 + minDist * 10.0);
  return dmtRainbow(trapVal * 3.0 + time * 0.1, 0.0) * trapVal * 2.0;
}

// Bloom glow approximation
fn glowFactor(r: f32, center: f32, spread: f32) -> f32 {
  return exp(-abs(r - center) * spread);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.z, u.config.w);
  let aspect = res.x / res.y;

  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) {
    return;
  }

  let fragCoord = vec2<f32>(pixel);
  let uv = fragCoord / res;
  let centered = uv - vec2<f32>(0.5);

  let time = u.config.x;
  let mouseNorm = u.zoom_config.yz / res;
  let mouseDown = u.zoom_config.w;
  
  let intensity = u.zoom_params.x;
  let speed = u.zoom_params.y;
  let scale = u.zoom_params.z;
  let colorShift = u.zoom_params.w;

  // Zoom parameters - mouse controls zoom
  let zoomSpeed = speed * 2.0;
  let zoomLevel = exp(time * zoomSpeed * 0.15) * (0.5 + scale * 2.0);
  let zoomDir = select(1.0, -1.0, mouseDown > 0.5);
  let effectiveZoom = zoomLevel * zoomDir;
  
  // Map UV to complex plane with zoom
  let zoomFactor = 3.0 / (abs(effectiveZoom) + 0.5);
  let panX = sin(time * 0.1) * 0.3;
  let panY = cos(time * 0.13) * 0.2;
  
  // Mouse pans the view
  let mouseOffset = (mouseNorm - vec2<f32>(0.5)) * 0.5;
  
  let c = vec2<f32>(
    centered.x * aspect * zoomFactor + (-0.745 + panX + mouseOffset.x),
    centered.y * zoomFactor + (0.13 + panY + mouseOffset.y)
  );

  // Dynamic iteration count based on zoom
  let baseIter = 20 + i32(intensity * 44);
  
  // Main fractal
  let result = fractalIter(c, baseIter, time);
  let iter = result.x;
  let zMag = result.y;
  
  var color: vec3<f32>;
  
  if (iter >= f32(baseIter) - 0.5) {
    // Interior - deep DMT space
    let interiorPhase = time * 0.05 + colorShift;
    color = dmtRainbow(interiorPhase, 0.0) * 0.3;
    color += vec3<f32>(0.05, 0.0, 0.1);
  } else {
    // Exterior - colorful escape
    color = fractalColor(iter, f32(baseIter), zMag, time, colorShift);
    
    // Orbit trap overlay
    let trap = orbitTrap(c, min(baseIter, 30), time);
    color += trap * intensity * 0.5;
    
    // Iteration band glow
    let band = fract(iter * 0.1);
    let bandGlow = smoothstep(0.0, 0.15, band) * smoothstep(0.5, 0.15, band);
    color += dmtRainbow(iter * 0.05 + time * 0.1, colorShift + 0.5) * bandGlow * 0.4;
  }

  // Second fractal layer at different scale for depth
  let c2 = c * 1.5 + vec2<f32>(sin(time * 0.07) * 0.1, cos(time * 0.09) * 0.1);
  let result2 = fractalIter(c2, baseIter / 2, time);
  let layer2 = fractalColor(result2.x, f32(baseIter / 2), result2.y, time * 0.7, colorShift + 0.33);
  color += layer2 * 0.25 * intensity;

  // Radial glow from interesting structures
  let r = length(centered);
  let structGlow = glowFactor(r, 0.15, 8.0) + glowFactor(r, 0.3, 12.0) * 0.5;
  color += dmtRainbow(time * 0.2 + r * 3.0, colorShift) * structGlow * intensity * 0.3;

  // Chromatic aberration / color fringing at edges
  let fringe = pow(r, 3.0) * intensity;
  color = vec3<f32>(color.r * (1.0 + fringe * 0.3), color.g * (1.0 + fringe * 0.1), color.b * (1.0 - fringe * 0.1));

  // Heavy post-processing glow / bloom simulation
  let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = pow(luminance, 2.0) * intensity * 0.5;
  color += vec3<f32>(luminance * 0.8, luminance * 0.6, luminance * 1.0) * bloom;

  // Psychedelic vignette that pulses
  let vignette = 1.0 - pow(r, 2.5) * (0.6 + sin(time * speed * 2.0) * 0.2);
  color *= max(vignette, 0.3);

  // Saturation boost
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(lum), color, 1.4 + intensity * 0.5);

  // Tone mapping
  color = color / (1.0 + color * 0.12);
  color = pow(color, vec3<f32>(0.92));

  textureStore(writeTexture, pixel, vec4<f32>(color, 0.85));
}
