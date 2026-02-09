@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Kimi Spotlight - Flashlight/spotlight effect following mouse
// Reveals full color under the beam while surroundings are desaturated/darkened

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Mouse position
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    var p = uv;
    p.x *= aspect;
    
    let mousePos = mouse;
    mousePos.x *= aspect;
    
    // Distance from mouse
    let dist = length(p - mousePos);
    
    // Spotlight parameters from zoom_params
    let spotSize = u.zoom_params.x * 0.5 + 0.1;          // 0.1 to 0.6
    let spotSoftness = u.zoom_params.y * 0.5 + 0.01;     // Edge softness
    let edgeDarkness = u.zoom_params.z * 0.9 + 0.1;      // How dark the edges get
    let saturationBoost = u.zoom_params.w * 2.0 + 1.0;   // Color boost in spotlight
    
    // Create spotlight mask
    var spotlight = 1.0 - smoothstep(spotSize - spotSoftness, spotSize + spotSoftness, dist);
    
    // Click makes spotlight bigger and brighter temporarily
    let clickPulse = mouseDown * sin(time * 10.0) * 0.1;
    spotlight = min(1.0, spotlight + clickPulse);
    
    // Sample original color
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Convert to grayscale for outside spotlight
    let gray = dot(original, vec3<f32>(0.299, 0.587, 0.114));
    let desaturated = vec3<f32>(gray) * 0.3; // Darkened grayscale
    
    // Boost saturation inside spotlight
    let luminance = dot(original, vec3<f32>(0.299, 0.587, 0.114));
    let saturated = mix(vec3<f32>(luminance), original, saturationBoost);
    
    // Mix between desaturated (outside) and saturated (inside)
    var color = mix(desaturated * edgeDarkness, saturated, spotlight);
    
    // Add subtle light beam effect
    let beamWidth = spotSize * 0.1;
    let beamDist = abs(dist - spotSize * 0.8);
    let beam = smoothstep(beamWidth, 0.0, beamDist) * 0.2 * spotlight;
    color += vec3<f32>(0.9, 0.95, 1.0) * beam;
    
    // Center hotspot
    let hotspot = smoothstep(spotSize * 0.3, 0.0, dist) * 0.3;
    color += vec3<f32>(hotspot);
    
    // Noise grain in dark areas for film effect
    let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    color += (noise - 0.5) * 0.02 * (1.0 - spotlight);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}
