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

// Kimi Ripple Touch - Interactive water ripple effect at mouse position
// Creates expanding ripples from mouse clicks and subtle waves on movement

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Mouse position and state
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
    
    // Ripple parameters from zoom_params
    let rippleCount = u.zoom_params.x * 10.0 + 1.0;      // 1-11 ripples
    let rippleSpeed = u.zoom_params.y * 5.0 + 1.0;       // Speed of expansion
    let rippleStrength = u.zoom_params.z * 0.1;          // Distortion amount
    let rippleDecay = u.zoom_params.w * 2.0 + 0.5;       // How fast they fade
    
    // Calculate ripple waves
    var ripple = 0.0;
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let wavePhase = time * rippleSpeed - dist * 10.0 + fi * 1.5;
        let waveAmp = exp(-dist * rippleDecay) * (1.0 - fi / 5.0);
        ripple += sin(wavePhase) * waveAmp;
    }
    
    // Click creates burst
    let clickBurst = mouseDown * exp(-dist * 5.0) * sin(dist * 20.0 - time * 10.0);
    ripple += clickBurst * 0.5;
    
    // Apply distortion to UV
    let distortion = normalize(p - mousePos + 0.0001) * ripple * rippleStrength;
    var sampleUV = uv - distortion;
    
    // Sample with chromatic aberration for rainbow edges
    let caStrength = abs(ripple) * 0.01;
    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(caStrength, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(caStrength, 0.0), 0.0).b;
    
    var color = vec3<f32>(r, g, b);
    
    // Add subtle blue glow at ripple peaks
    let glow = max(0.0, ripple) * 0.3;
    color += vec3<f32>(0.2, 0.5, 1.0) * glow;
    
    // Vignette around mouse for focus
    let vignette = smoothstep(0.8, 0.2, dist);
    color = mix(color * 0.9, color, vignette * mouseDown);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}
